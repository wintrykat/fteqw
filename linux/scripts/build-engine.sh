#!/usr/bin/env bash
# build-engine.sh — build the merged OpenGL + Vulkan FTEQW engine natively for
# Linux/arm64 (aarch64). Output: engine/release/fteqw-sdl2
#
# Why each choice is made is documented in docs/PORTING-LINUX.md. In brief:
#   * We DO NOT run `make makelibs`. FTE_TARGET=SDL2 links a handful of image/
#     audio libs statically from engine/libs-<arch>/*.a (Makefile line ~726 —
#     the SAME expectation as on macOS). We satisfy it by symlinking the distro's
#     static archives into that dir. `<arch>` is `cc -dumpmachine`.
#   * FTE_TARGET=SDL2 uses SDL for video/audio/input (the maintained path).
#   * m-rel is the MERGED target: both -DGLQUAKE and -DVKQUAKE -> one binary,
#     runtime-switchable via `vid_renderer gl|vk`.
#   * Unlike macOS, GNU strip understands the Makefile's default --strip-unneeded,
#     so we DO let it strip (smaller AppImage). No STRIP=SKIP needed.
#   * No engine source edits are required on Linux (the one-line <limits.h> patch
#     already in vk_init.c is a harmless no-op here — UINT_MAX arrives via other
#     headers). git diff should still show exactly one inserted line.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_packages "${1:-}"        # pass --install to auto-install missing deps

log "target arch: $ARCH"

# --- satisfy the SDL2 target's static-lib expectation (no makelibs) ----------
# find_static <pkgconfig-name> <archive-basename> -> absolute path to the .a
find_static() {
  local pc="$1" a="$2" libdir p
  libdir="$(pkg-config --variable=libdir "$pc" 2>/dev/null || true)"
  for p in "$libdir/$a" "/usr/lib/$ARCH/$a" "/usr/lib/$a" "/usr/lib64/$a"; do
    [[ -n "$p" && -f "$p" ]] && { echo "$p"; return 0; }
  done
  # last resort: search the multiarch dir for a versioned sibling (libpng16.a…)
  p="$(find "/usr/lib/$ARCH" /usr/lib -maxdepth 1 -name "${a%.a}*.a" 2>/dev/null | head -1)"
  [[ -n "$p" ]] && { echo "$p"; return 0; }
  return 1
}

L="$ENGINE/libs-$ARCH"
mkdir -p "$L"
# name  <- pkgconfig  archive
link_static() {
  local pc="$1" a="$2" src
  src="$(find_static "$pc" "$a")" || die "static lib $a not found (install lib${pc}-dev / the *.a variant)"
  ln -sf "$src" "$L/$a"
}
link_static libpng       libpng.a
link_static libjpeg      libjpeg.a
link_static vorbisfile   libvorbisfile.a
link_static vorbis       libvorbis.a
link_static ogg          libogg.a
ok "linked distro static libs into libs-$ARCH"

# --- header search the Makefile doesn't add itself ---------------------------
# The Makefile's LINK_FREETYPE branch (engine/Makefile ~line 1053) BLANKS
# FREETYPE_CFLAGS and instead expects ft2build.h to live in libs-<arch>/ — a
# layout produced only by `make makelibs`, which we deliberately skip (see above).
# The distro ships the FreeType headers in a non-default include dir
# (…/freetype2) that nothing on the default search path covers, so gl_font.c's
# `#include <ft2build.h>` fails. Mirror the macOS build's CPATH trick (see
# macos/scripts/common.sh:setup_build_env): add that dir — derived from
# pkg-config, never hardcoded — so the include resolves with no Makefile edit.
# Opus (-I…/opus), Vulkan and SDL2 headers are already added by the Makefile's
# own pkg-config calls; FreeType is the only gap. See docs/PORTING-LINUX.md §2.4.
FT_INC="$(pkg-config --cflags-only-I freetype2 2>/dev/null | tr ' ' '\n' | sed -n 's/^-I//p' | paste -sd:)"
[[ -n "$FT_INC" ]] || die "FreeType headers not found via pkg-config (install libfreetype-dev)"
export CPATH="$FT_INC${CPATH:+:$CPATH}"
ok "FreeType headers on CPATH: $FT_INC"

# --- build the merged GL+Vulkan engine ---------------------------------------
log "building merged GL+Vulkan engine (m-rel)…"
make -C "$ENGINE" m-rel \
  FTE_TARGET=SDL2 PKGCONFIG=pkg-config \
  -j"$(ncpu)"

# The merged (client+server) SDL2 binary is $(EXE_NAME)-sdl2[BITS]; the gl/vk/sv/
# cl variants carry an infix, so this glob uniquely matches the m-rel output.
BIN="$(ls -1 "$ENGINE/release/"fteqw-sdl2* 2>/dev/null | head -1 || true)"
[[ -n "$BIN" && -f "$BIN" ]] || die "build produced no merged binary at engine/release/fteqw-sdl2*"

# Sanity: right architecture, and BOTH renderers genuinely compiled in.
file -b "$BIN" | grep -qi 'aarch64\|arm aarch64' || die "binary is not aarch64: $(file -b "$BIN")"
# Prefer the UNSTRIPPED .db that m-rel links before stripping (release/fteqw-sdl2.db)
# for precise symbols; also accept strip-proof marker strings (present even after
# strip): "Vulkan-SDL" exists only under -DVKQUAKE, "OpenGL" is the GL renderer
# name. grep -c (not -q) so the large nm stream is fully consumed — a -q early-exit
# would SIGPIPE nm and trip pipefail even when present.
DBG="$BIN.db"; symsrc="$BIN"; [[ -f "$DBG" ]] && symsrc="$DBG"
syms="$(nm "$symsrc" 2>/dev/null || true)"
vk=$(( $(printf '%s\n' "$syms" | grep -cw 'VK_Init'   || true) + $(grep -ac 'Vulkan-SDL' "$BIN" 2>/dev/null || true) ))
gl=$(( $(printf '%s\n' "$syms" | grep -cw 'GLBE_Init' || true) + $(grep -ac 'OpenGL'     "$BIN" 2>/dev/null || true) ))
(( vk > 0 )) || die "Vulkan renderer not present in binary (no VK_Init / Vulkan-SDL)"
(( gl > 0 )) || die "OpenGL renderer not present in binary (no GLBE_Init / OpenGL)"

ok "engine built: $BIN"
file -b "$BIN"
