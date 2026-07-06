#!/bin/zsh
# build-engine.sh — build the merged OpenGL + Vulkan FTEQW engine natively for
# Apple Silicon (arm64). Output: engine/release/fteqw-sdl2
#
# Why each workaround exists is documented in docs/PORTING.md. In brief:
#   * We DO NOT run `make makelibs` (its vendored config.sub can't parse
#     arm64-apple-darwin, upstream issue #281). Instead we satisfy the Makefile's
#     libs-<arch>/*.a expectation with symlinks to Homebrew's native static libs.
#   * FTE_TARGET=SDL2 uses SDL for video/audio/input (the maintained macOS path).
#   * m-rel is the MERGED target: both -DGLQUAKE and -DVKQUAKE -> one binary,
#     runtime-switchable via `vid_renderer gl|vk`.
#   * STRIP=SKIP: GNU `strip --strip-unneeded` isn't understood by Apple strip;
#     this upstream-provided escape hatch links straight to the final binary.
#   * CPATH carries FreeType/Opus/Vulkan headers the Makefile doesn't add itself.
source "${0:A:h}/common.sh"

ensure_formulae "${1:-}"        # pass --install to auto-install missing deps
setup_build_env

ARCH="$(fte_arch)"
[[ -n "$ARCH" ]] || die "could not determine FTE arch triple from the Makefile"
log "target arch: $ARCH"

# Satisfy the SDL2 target's static-lib expectations from Homebrew (no makelibs).
L="$ENGINE/libs-$ARCH"
mkdir -p "$L"
ln -sf "$BREW/opt/libpng/lib/libpng.a"            "$L/libpng.a"
ln -sf "$BREW/opt/jpeg-turbo/lib/libjpeg.a"       "$L/libjpeg.a"
ln -sf "$BREW/opt/libvorbis/lib/libvorbisfile.a"  "$L/libvorbisfile.a"
ln -sf "$BREW/opt/libvorbis/lib/libvorbis.a"      "$L/libvorbis.a"
ln -sf "$BREW/opt/libogg/lib/libogg.a"            "$L/libogg.a"
ok "linked Homebrew static libs into libs-$ARCH"

log "building merged GL+Vulkan engine (m-rel)…"
make -C "$ENGINE" m-rel \
  FTE_TARGET=SDL2 PKGCONFIG=pkgconf STRIP=SKIP \
  -j"$(sysctl -n hw.ncpu)"

BIN="$ENGINE/release/fteqw-sdl2"
[[ -f "$BIN" ]] || die "build produced no binary at $BIN"
[[ "$(file -b "$BIN")" == *arm64* ]] || die "binary is not arm64: $(file -b "$BIN")"
# Both renderers must be genuinely compiled in (not stubbed by #ifdef VKQUAKE).
# grep -c (not -q) so the large nm stream is fully consumed — a -q early-exit
# would SIGPIPE nm and trip pipefail even when the symbol is present.
(( $(nm "$BIN" 2>/dev/null | grep -c ' _VK_Init$' || true) > 0 )) \
  || die "Vulkan renderer (_VK_Init) not present in binary"
ok "engine built: $BIN ($(file -b "$BIN"))"
