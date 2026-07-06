#!/bin/zsh
# build-plugins.sh — build FTEQW native plugins for Apple Silicon, bundle their
# dependencies into FTEQW.app, ad-hoc sign, and re-embed FTE plugin metadata.
#
# Ordering matters on macOS (see docs/PORTING.md):
#   1. build WITHOUT metadata  -> clean Mach-O (install_name_tool & codesign refuse
#                                 a file that already has FTE's trailing metadata zip)
#   2. dylibbundler            -> rewrite external deps to @loader_path/../Frameworks
#   3. codesign (ad-hoc)       -> sets the code-limit at the Mach-O's end
#   4. append metadata         -> lands BEYOND the code-limit: signature stays valid
#                                 for the code, dyld still loads it, and FTE's plugin
#                                 manager can read the title/description.
#
# Usage:  build-plugins.sh [plugin ...]        (default: ffmpeg qi)
source "${0:A:h}/common.sh"
setup_build_env

APP="$FTEQW_APP"; FW="$APP/Contents/Frameworks"; RES="$APP/Contents/Resources"
[[ -d "$RES" ]] || die "no app at $APP — run make-app.sh first"

if (( $# )); then plugins=("$@"); else plugins=(ffmpeg qi); fi
ver="$(cd "$REPO" && git describe --always --long 2>/dev/null || echo dev)"

# Plugin metadata — mirrors the EMBEDMETA calls in plugins/Makefile.
typeset -A title desc
title[ffmpeg]="FFMPEG Video Decoding Plugin"
desc[ffmpeg]="Provides support for more audio formats as well as video playback and better capture support."
title[qi]="Quake-Injector Plugin"
desc[qi]="Provides easy access to the Quaddicted mod database."

embed_meta () {   # $1=name  $2=plugin file
  local name="$1" f="$2"
  printf '{\n\tpackage fteplug_%s\n\tver "%s"\n\tcategory Plugins\n\ttitle "%s"\n\tgamedir ""\n\tdesc "%s"\n}' \
    "$name" "$ver" "${title[$name]}" "${desc[$name]}" | zip -q -9 -fz- "$f.metazip" -
  cat "$f.metazip" >> "$f"; zip -q -A "$f"; rm -f "$f.metazip"
}

cd "$ENGINE"
np="${(j: :)plugins}"

# 1) clean build — EMBEDMETA neutralised; Apple-compatible plugin link flags:
#    (drop -static-libgcc/-Bsymbolic/--no-undefined/-Wl,-R; allow engine symbols
#     to resolve at load via -undefined,dynamic_lookup)
for p in $plugins; do rm -f "release/fteplug_$p.so"; done
make plugins-rel FTE_TARGET=SDL2 NATIVE_PLUGINS="$np" AV_BASE= PKGCONFIG=pkgconf \
     STRIP=SKIP EMBEDMETA= \
     PLUG_CFLAGS="-fPIC -fvisibility=hidden" \
     PLUG_LDFLAGS="-lm -Wl,-undefined,dynamic_lookup" -j"$(sysctl -n hw.ncpu)"

for p in $plugins; do
  src="release/fteplug_$p.so"; dst="$RES/fteplug_$p.so"
  [[ -f "$src" ]] || die "$src not built"
  cp "$src" "$dst"
  if otool -L "$dst" | tail -n +2 | grep -q '/opt/homebrew\|/usr/local'; then
    dylibbundler -of -b -x "$dst" -d "$FW/" -p @loader_path/../Frameworks/ >/dev/null
  fi
  codesign --force --sign - "$dst"
  embed_meta "$p" "$dst"
  refs=$(otool -L "$dst" | tail -n +2 | grep -c '/opt/homebrew\|/usr/local' || true)
  ok "fteplug_$p.so — built, bundled, signed, metadata embedded (external refs: $refs)"
done
log "plugins in $RES"
