#!/usr/bin/env bash
# build-plugins.sh — build the FTEQW native plugins for Linux/arm64, drop them
# next to the engine in the AppDir, and bundle their extra runtime deps.
#
# Much simpler than the macOS path (docs/PORTING-LINUX.md §plugins):
#   * Linux is FTE's native plugin target, so the default PLUG_CFLAGS/PLUG_LDFLAGS
#     work as-is — none of the macOS -undefined,dynamic_lookup gymnastics.
#   * There is no codesigning, so upstream's default EMBEDMETA (a trailing-zip the
#     plugin manager reads) is left ON and needs no reorder — the plugin ships
#     with its title/description already embedded.
# The only real work is deploying the ffmpeg plugin's libav* closure, which
# linuxdeploy didn't see (the plugin isn't the AppImage's main executable): we
# copy the non-allowlisted deps into usr/lib and rpath the plugin at them.
#
# Usage:  build-plugins.sh [plugin …]        (default: ffmpeg qi)
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

[[ -d "$APPDIR/usr/bin" ]] || die "no AppDir at $APPDIR — run make-appdir.sh first"

if (( $# )); then plugins=("$@"); else plugins=(ffmpeg qi); fi
np="${plugins[*]}"

# FFmpeg < 7.1 compatibility: upstream avplug uses a libavcodec 61.13 API the
# distro's FFmpeg 6.x lacks. Force-include a build-time shim (kept under linux/,
# no engine-tree edit — docs/PORTING-LINUX.md §5) into the ffmpeg plugin compile
# via the plugin rule's $(CFLAGS) hook. The header is inert on FFmpeg >= 7.1, so
# injecting it is harmless even for the other plugins built in the same batch.
if [[ " $np " == *" ffmpeg "* ]]; then
  export CFLAGS="${CFLAGS:-} -include $LINUX/compat/ffmpeg6-compat.h"
fi

log "building plugins: $np"
for p in "${plugins[@]}"; do rm -f "$ENGINE/release/fteplug_$p.so"; done
make -C "$ENGINE" plugins-rel \
  FTE_TARGET=SDL2 NATIVE_PLUGINS="$np" PKGCONFIG=pkg-config \
  -j"$(ncpu)"

for p in "${plugins[@]}"; do
  src="$ENGINE/release/fteplug_$p.so"
  dst="$APPDIR/usr/bin/fteplug_$p.so"
  [[ -f "$src" ]] || die "$src not built"
  install -m755 "$src" "$dst"
  # Bundle this plugin's non-allowlisted deps (libav* for ffmpeg) into usr/lib…
  bundle_so_deps "$dst" "$APPDIR/usr/lib"
  # …and point the plugin at usr/lib (it lives in usr/bin, one dir up).
  patchelf --set-rpath '$ORIGIN/../lib' "$dst" 2>/dev/null || true
  refs="$(audit_selfcontained "$dst" 2>&1 | grep -c . || true)"
  ok "fteplug_$p.so — built, bundled ($refs external refs remaining)"
done
log "plugins in $APPDIR/usr/bin"
