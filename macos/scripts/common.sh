#!/bin/zsh
# common.sh — shared configuration and helpers for the macOS/Apple-Silicon build.
# Sourced by the other scripts in this directory. Nothing here is machine-specific:
# every path is derived from the Homebrew prefix and this repo's location.

set -euo pipefail

# --- locations ---------------------------------------------------------------
SCRIPT_DIR="${0:A:h}"
# scripts live in <repo>/macos/scripts ; repo root is two levels up
REPO="${SCRIPT_DIR:h:h}"
ENGINE="$REPO/engine"

# Where the finished .app is assembled. Override with FTEQW_APP=/path make-app.sh.
: "${FTEQW_APP:=$HOME/Applications/FTEQW.app}"
# Runtime game-data dir the launcher defaults to (kept OUTSIDE the bundle).
: "${FTEQW_DATA:=$HOME/Library/Application Support/FTEQW}"

# --- toolchain / homebrew ----------------------------------------------------
BREW="$(brew --prefix 2>/dev/null || echo /opt/homebrew)"
export PATH="$BREW/bin:$PATH"

# Homebrew formulae we depend on, split by role.
BUILD_FORMULAE=(pkgconf autoconf automake libtool)                 # build tools
LIB_FORMULAE=(sdl2 libpng jpeg-turbo libvorbis libogg freetype opus speex speexdsp)  # linked libs
VULKAN_FORMULAE=(vulkan-headers vulkan-loader molten-vk vulkan-tools)                 # vulkan/moltenvk
PLUGIN_FORMULAE=(ffmpeg dylibbundler)                              # ffmpeg plugin + bundler

# --- helpers -----------------------------------------------------------------
log()  { print -P "%F{cyan}==>%f $*"; }
ok()   { print -P "%F{green}  ✓%f $*"; }
warn() { print -P "%F{yellow}  !%f $*"; }
die()  { print -P "%F{red}  ✗ $*%f" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# The arch triple the FTEQW Makefile uses for its libs-<arch> directory.
# The Makefile derives it from the compiler target, so we do the same — this is
# fast and avoids parsing `make -p`. Verified equal to the Makefile's $(ARCH).
fte_arch() {
  "${CC:-cc}" -dumpmachine
}

# Build-time environment (include/lib search paths) derived from $BREW.
setup_build_env() {
  export PKG_CONFIG_PATH="$BREW/opt/jpeg-turbo/lib/pkgconfig:$BREW/opt/libpng/lib/pkgconfig:$BREW/opt/libvorbis/lib/pkgconfig:$BREW/opt/libogg/lib/pkgconfig:$BREW/opt/freetype/lib/pkgconfig"
  # Header search: umbrella + keg-only/versioned dirs the Makefile doesn't add itself.
  export CPATH="$BREW/include:$BREW/opt/freetype/include/freetype2:$BREW/include/opus:$BREW/opt/vulkan-headers/include:$BREW/opt/ffmpeg/include"
  # Library search for the plugins' plain -l flags (ffmpeg lives keg-only).
  export LIBRARY_PATH="$BREW/opt/ffmpeg/lib:$BREW/lib"
}

# Verify (optionally --install) all required formulae.
ensure_formulae() {
  local install=0; [[ "${1:-}" == "--install" ]] && install=1
  local missing=()
  for f in $BUILD_FORMULAE $LIB_FORMULAE $VULKAN_FORMULAE $PLUGIN_FORMULAE; do
    brew --prefix "$f" >/dev/null 2>&1 || missing+=("$f")
  done
  if (( ${#missing} )); then
    if (( install )); then
      log "installing missing formulae: $missing"
      brew install $missing
    else
      die "missing Homebrew formulae: $missing  (run: brew install $missing)"
    fi
  fi
  ok "Homebrew dependencies present"
}
