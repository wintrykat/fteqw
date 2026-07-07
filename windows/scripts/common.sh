#!/usr/bin/env bash
# common.sh — shared configuration and helpers for the Windows-on-ARM (arm64)
# build. Sourced by the other scripts in this directory. Nothing here is
# machine-specific: every path is derived from the MSYS2 CLANGARM64 prefix (the
# Homebrew analog) and this repo's location.
#
# Toolchain: MSYS2 CLANGARM64 (native aarch64 clang), triple
# aarch64-w64-windows-gnu. The engine is built with FTE_TARGET=win64 plus
# command-line overrides — NO Makefile edits (see docs/PORTING-WINDOWS.md). "win64"
# is only a build-label; clang targets aarch64, so the PE is genuinely ARM64
# (machine 0xAA64). The tests assert that, guarding against any x86 regression.
set -euo pipefail

# --- locations ---------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# scripts live in <repo>/windows/scripts ; repo root is two levels up
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENGINE="$REPO/engine"

# --- toolchain / MSYS2 CLANGARM64 --------------------------------------------
# Derive the CLANGARM64 prefix from clang's location (do not hardcode C:\msys64).
if ! command -v clang >/dev/null 2>&1; then
  # Fall back to the default MSYS2 install so error messages are useful.
  export PATH="/c/msys64/clangarm64/bin:/c/msys64/usr/bin:$PATH"
fi
command -v clang >/dev/null 2>&1 || { echo "clang not found — install MSYS2 CLANGARM64 (see ensure_packages)"; }
CLANGARM64="$(cd "$(dirname "$(command -v clang 2>/dev/null || echo /c/msys64/clangarm64/bin/clang)")/.." && pwd)"
# Windows-form prefix for flags handed to the native clang (it can't read /c/… ).
CAWIN="$(cygpath -m "$CLANGARM64" 2>/dev/null || echo "$CLANGARM64")"

# MSYS2 pacman packages we depend on, split by role (CLANGARM64 prefix).
CA=mingw-w64-clang-aarch64
BUILD_PACKAGES=(make zip "$CA-clang" "$CA-lld" "$CA-pkgconf" "$CA-ntldd-git")
# Base MSYS2 tools the scripts invoke that aren't always present on a fresh MSYS2
# (e.g. GitHub's setup-msys2): unzip verifies embedded plugin metadata, git
# stamps the version. Checked by command (they may be loose files, not pacman-
# owned) and installed as packages when missing.
BASE_TOOLS=(unzip git)
LIB_PACKAGES=("$CA-SDL2" "$CA-libpng" "$CA-libjpeg-turbo" "$CA-libogg" "$CA-libvorbis" \
              "$CA-freetype" "$CA-opus" "$CA-speex" "$CA-speexdsp" "$CA-zlib")
VULKAN_PACKAGES=("$CA-vulkan-headers" "$CA-vulkan-loader")
PLUGIN_PACKAGES=("$CA-ffmpeg")

# --- output locations --------------------------------------------------------
# The self-contained package folder (analog of macOS FTEQW.app). Honor FTEQW_APP
# for parity with the macOS scripts; else default under the repo's dist dir.
: "${FTEQW_APP:=$REPO/windows/dist/FTEQW}"
FTEQW_PKG="$FTEQW_APP"
# Runtime game-data dir the engine defaults to (kept OUTSIDE the package). Windows
# analog of ~/Library/Application Support/FTEQW. %LOCALAPPDATA% arrives as a
# backslash Windows path under a real MSYS2 shell — normalise to a unix path so
# bash file ops behave.
: "${FTEQW_DATA:=${LOCALAPPDATA:-$HOME/AppData/Local}/FTEQW}"
case "$FTEQW_DATA" in *[\\:]*) FTEQW_DATA="$(cygpath -u "$FTEQW_DATA" 2>/dev/null || echo "$FTEQW_DATA")";; esac

# --- helpers -----------------------------------------------------------------
if [[ -t 1 ]]; then C_CYAN=$'\e[36m'; C_GRN=$'\e[32m'; C_YEL=$'\e[33m'; C_RED=$'\e[31m'; C_0=$'\e[0m'
else C_CYAN=; C_GRN=; C_YEL=; C_RED=; C_0=; fi
log()  { printf '%s==>%s %s\n'  "$C_CYAN" "$C_0" "$*"; }
ok()   { printf '%s  \xe2\x9c\x93%s %s\n' "$C_GRN" "$C_0" "$*"; }
warn() { printf '%s  !%s %s\n'  "$C_YEL" "$C_0" "$*"; }
die()  { printf '%s  \xe2\x9c\x97 %s%s\n' "$C_RED" "$*" "$C_0" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# The arch triple the FTEQW Makefile uses for its libs-<arch> dir; it derives it
# from the compiler, so we do the same. Expected: aarch64-w64-windows-gnu.
fte_arch() { clang -dumpmachine; }

# A Windows-form temp dir. MSYS /bin/sh (make's recipe shell) strips inherited
# TMP/TEMP, so we recompute one and pass it as a make VARIABLE (see fte_make).
fte_tmpwin() { cygpath -m "${TEMP:-${TMP:-/tmp}}"; }

# fte_make <make-args…> — invoke the engine Makefile with the full set of
# Windows-on-ARM overrides. This is the single source of truth for the build
# recipe; every workaround lives here and is explained in docs/PORTING-WINDOWS.md:
#   * CC/CXX carry -I<prefix>/include/opus  → Makefile hardcodes -I/usr/include/opus
#     (line 1029); our opus.h lives in the CLANGARM64 prefix under include/opus.
#   * TMP/TEMP as make vars                 → recipes otherwise see empty TMP and
#     llvm-windres fails ("Unable to create temp file").
#   * STRIP=SKIP                            → upstream escape hatch; avoids strip
#     quirks and keeps symbols for the Tier-1 renderer-presence checks.
#   * PKGCONFIG=pkgconf                     → the arch-prefixed pkg-config the
#     Makefile guesses (aarch64-…-pkg-config) does not exist here.
#   * WINDRES/AR/RANLIB = llvm-*            → the CLANGARM64 binutils analogs.
fte_make() {
  local tmpw; tmpw="$(fte_tmpwin)"
  make -C "$ENGINE" "$@" \
    "CC=clang -I$CAWIN/include/opus" \
    "CXX=clang++ -I$CAWIN/include/opus" \
    AR=llvm-ar RANLIB=llvm-ranlib WINDRES=llvm-windres \
    STRIP=SKIP PKGCONFIG=pkgconf \
    TMP="$tmpw" TEMP="$tmpw" \
    -j"$(nproc)"
}

# Verify (optionally --install) all required MSYS2 packages are present.
ensure_packages() {
  local install=0; [[ "${1:-}" == "--install" ]] && install=1
  local pkgs=("${BUILD_PACKAGES[@]}" "${LIB_PACKAGES[@]}" "${VULKAN_PACKAGES[@]}" "${PLUGIN_PACKAGES[@]}")
  local missing=()
  for p in "${pkgs[@]}"; do
    pacman -Q "$p" >/dev/null 2>&1 || missing+=("$p")
  done
  # Base tools checked by command availability (they may be loose, not pacman-owned).
  local missing_tools=()
  for t in "${BASE_TOOLS[@]}"; do have "$t" || missing_tools+=("$t"); done
  if (( ${#missing[@]} || ${#missing_tools[@]} )); then
    if (( install )); then
      log "installing missing packages: ${missing[*]} ${missing_tools[*]}"
      pacman -S --needed --noconfirm "${missing[@]}" "${missing_tools[@]}"
    else
      die "missing dependencies: ${missing[*]} ${missing_tools[*]}  (run with --install, or: pacman -S ${missing[*]} ${missing_tools[*]})"
    fi
  fi
  ok "MSYS2 CLANGARM64 dependencies present"
}
