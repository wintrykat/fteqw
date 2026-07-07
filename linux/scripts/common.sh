#!/usr/bin/env bash
# common.sh — shared configuration and helpers for the Linux/arm64 AppImage build.
# Sourced by the other scripts in this directory. Nothing here is machine-specific:
# every path is derived from the compiler target triple and this repo's location.
#
# This is the Linux analogue of macos/scripts/common.sh. Differences from macOS
# are deliberate and documented in docs/PORTING-LINUX.md:
#   * dependencies come from the distro package manager (apt), not Homebrew;
#   * the graphics stack (OpenGL, the Vulkan *loader*, X11/Wayland, libdrm) is a
#     HOST responsibility — we never bundle it (mirrors the Windows-on-ARM stance
#     that the GPU *driver* provides Vulkan). See ALLOWLIST below;
#   * bundling is done by linuxdeploy (the dylibbundler analogue) + appimagetool.

set -euo pipefail

# --- locations ---------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# scripts live in <repo>/linux/scripts ; repo root is two levels up
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENGINE="$REPO/engine"
LINUX="$REPO/linux"

# All build output lives here (git-ignored). Override with BUILD_DIR=…
: "${BUILD_DIR:=$REPO/build/linux}"
: "${APPDIR:=$BUILD_DIR/FTEQW.AppDir}"
# Runtime game-data dir. FTE natively uses $XDG_DATA_HOME/fteqw; we mirror that so
# the launcher/tests and the engine agree. Kept OUTSIDE the AppImage.
: "${FTEQW_DATA:=${XDG_DATA_HOME:-$HOME/.local/share}/fteqw}"

# --- toolchain ---------------------------------------------------------------
: "${CC:=cc}"
export CC
# The arch triple the FTEQW Makefile uses for its libs-<arch> directory — the
# compiler target (aarch64-linux-gnu). Matches the Makefile's $(ARCH). Mirrors
# macos/common.sh:fte_arch().
fte_arch() { "$CC" -dumpmachine; }
ARCH="$(fte_arch)"
# CPU name as AppImage/uname spell it (aarch64), for the .AppImage filename.
CPU="$(uname -m)"
: "${APPIMAGE:=$BUILD_DIR/FTEQW-$CPU.AppImage}"

# --- distro dependencies (Debian/Ubuntu apt names) ---------------------------
# Split by role, mirroring macOS's BUILD_/LIB_/VULKAN_/PLUGIN_ formulae.
BUILD_PKGS=(build-essential clang pkg-config git patchelf file)          # build tools
# Static image/audio libs FTE_TARGET=SDL2 links from libs-<arch>/*.a (see
# build-engine.sh) plus the dynamically-linked runtime libs we bundle.
LIB_PKGS=(libsdl2-dev libpng-dev libjpeg-dev libvorbis-dev libogg-dev \
          libfreetype-dev libopus-dev libspeex-dev libspeexdsp-dev zlib1g-dev)
# Graphics stack: build-time headers/stubs only — the runtime libs come from the
# user's GPU driver and are never bundled (see ALLOWLIST).
GL_PKGS=(libgl1-mesa-dev libvulkan-dev)
PLUGIN_PKGS=(libavformat-dev libavcodec-dev libavutil-dev libswscale-dev libswresample-dev)
# Icon rasterisation (SVG -> PNG for the .desktop/AppImage icon).
ICON_PKGS=(librsvg2-bin)
# Software rasterisers + virtual display let CI/VMs actually initialise GL and
# Vulkan with no real GPU (llvmpipe / lavapipe). Real-GPU tests stay Tier 2.
TEST_PKGS=(xvfb mesa-utils libgl1-mesa-dri mesa-vulkan-drivers vulkan-tools)

ALL_PKGS=("${BUILD_PKGS[@]}" "${LIB_PKGS[@]}" "${GL_PKGS[@]}" "${PLUGIN_PKGS[@]}" "${ICON_PKGS[@]}")

# --- host-provided libraries (the self-containment ALLOWLIST) ----------------
# On Linux, self-contained means "bundle everything the app links EXCEPT the
# platform ABI and the graphics/display driver stack", which MUST come from the
# host to match the kernel + GPU. Any dependency that resolves OUTSIDE the AppDir
# and is NOT matched here is a self-containment failure (something we forgot to
# bundle or static-link). Prefix-matched against the resolved library basename.
# This is the inverse of macOS's "no /opt/homebrew refs" audit.
ALLOWLIST=(
  # glibc / platform ABI
  ld-linux libc.so libm.so libdl.so libpthread librt.so libresolv libutil
  libgcc_s libstdc++
  # OpenGL / EGL / GLX (provided by the GPU driver)
  libGL libGLX libGLdispatch libOpenGL libEGL libGLU
  # Vulkan loader (the ICD/driver is the user's; mirrors "driver provides Vulkan")
  libvulkan
  # X11 / XCB
  libX11 libxcb libXext libXi libXrandr libXrender libXfixes libXcursor
  libXinerama libXss libXxf86vm libXau libXdmcp libXdamage libXt libSM libICE
  # Wayland / input / KMS
  libwayland libxkbcommon libdecor libdrm libgbm libudev
)

# --- helpers -----------------------------------------------------------------
if [[ -t 1 ]]; then
  _c() { tput setaf "$1" 2>/dev/null || true; }; _r() { tput sgr0 2>/dev/null || true; }
else
  _c() { :; }; _r() { :; }
fi
log()  { printf '%s==>%s %s\n'  "$(_c 6)" "$(_r)" "$*"; }
ok()   { printf '%s  ✓%s %s\n'  "$(_c 2)" "$(_r)" "$*"; }
warn() { printf '%s  !%s %s\n'  "$(_c 3)" "$(_r)" "$*"; }
die()  { printf '%s  ✗ %s%s\n'  "$(_c 1)" "$*" "$(_r)" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
ncpu() { nproc 2>/dev/null || echo 4; }

# is_allowlisted <library-basename>  — 0 if it's a host-provided (non-bundled) lib
is_allowlisted() {
  local base="$1" p
  for p in "${ALLOWLIST[@]}"; do [[ "$base" == "$p"* ]] && return 0; done
  return 1
}

# Verify (optionally --install) the apt packages the build needs.
ensure_packages() {
  local install=0; [[ "${1:-}" == "--install" ]] && install=1
  local missing=() p
  for p in "${ALL_PKGS[@]}"; do
    dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
  done
  if (( ${#missing[@]} )); then
    if (( install )); then
      log "installing missing apt packages: ${missing[*]}"
      sudo apt-get update -qq
      sudo apt-get install -y --no-install-recommends "${missing[@]}"
    else
      die "missing apt packages: ${missing[*]}  (run with --install, or: sudo apt-get install ${missing[*]})"
    fi
  fi
  ok "apt build dependencies present"
}

# --- linuxdeploy / appimagetool ----------------------------------------------
# These packaging tools are themselves AppImages. Extract-and-run so they work
# in a VM/CI without FUSE (no libfuse2 needed). Cached under $BUILD_DIR/tools.
export APPIMAGE_EXTRACT_AND_RUN=1
TOOLS_DIR="$BUILD_DIR/tools"
LINUXDEPLOY_URL="https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-$CPU.AppImage"
APPIMAGETOOL_URL="https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$CPU.AppImage"

# ensure_tool <name> <url> -> echoes an invocable path (PATH copy or cached download)
ensure_tool() {
  local name="$1" url="$2" dst="$TOOLS_DIR/$1"
  if have "$name"; then command -v "$name"; return; fi
  if [[ ! -x "$dst" ]]; then
    mkdir -p "$TOOLS_DIR"
    log "fetching $name ($url)" >&2
    curl -fL# "$url" -o "$dst" || die "could not download $name"
    chmod +x "$dst"
  fi
  echo "$dst"
}

# --- bundling + self-containment ---------------------------------------------
# resolved_deps <elf>  — print "basename<TAB>resolvedpath" for every ldd entry
# that resolves to a real file (skips the vdso and "not found" lines).
resolved_deps() {
  ldd "$1" 2>/dev/null | awk '/=>/ && $3 ~ /^\// {print $1"\t"$3} !/=>/ && $1 ~ /^\// {n=$1; sub(/.*\//,"",n); print n"\t"$1}'
}

# bundle_so_deps <elf> <libdir>  — copy every NON-allowlisted dependency of <elf>
# into <libdir> (recursively) and patch each copied lib's rpath to $ORIGIN. Used
# for the ffmpeg plugin's libav* closure, which linuxdeploy doesn't scan because
# the plugin isn't the AppImage's main executable. Idempotent.
bundle_so_deps() {
  local elf="$1" libdir="$2" base path
  mkdir -p "$libdir"
  while IFS=$'\t' read -r base path; do
    [[ -z "$base" ]] && continue
    is_allowlisted "$base" && continue
    [[ -f "$libdir/$base" ]] && continue
    cp -L "$path" "$libdir/$base"
    patchelf --set-rpath '$ORIGIN' "$libdir/$base" 2>/dev/null || true
    bundle_so_deps "$libdir/$base" "$libdir"     # pull transitive deps too
  done < <(resolved_deps "$elf")
}

# audit_selfcontained <elf> [elf …]  — fail if any dependency resolves OUTSIDE
# the AppDir and is not on the host ALLOWLIST. Echoes the offending libs. The
# positive-space inverse of macOS's "no /opt/homebrew refs" check.
audit_selfcontained() {
  local bad=() elf base path
  for elf in "$@"; do
    [[ -f "$elf" ]] || continue
    while IFS=$'\t' read -r base path; do
      [[ -z "$base" ]] && continue
      case "$path" in "$APPDIR"/*) continue ;; esac   # bundled — fine
      is_allowlisted "$base" && continue              # host driver/ABI — fine
      bad+=("$base ($path)")
    done < <(resolved_deps "$elf")
  done
  if (( ${#bad[@]} )); then
    printf '%s\n' "${bad[@]}" | sort -u
    return 1
  fi
  return 0
}
