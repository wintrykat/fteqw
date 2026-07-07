#!/usr/bin/env bash
# build-appimage.sh — pack the finished FTEQW.AppDir into a single, portable
# FTEQW-<cpu>.AppImage with appimagetool. Requires make-appdir.sh (and normally
# build-plugins.sh) to have run first.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

[[ -x "$APPDIR/AppRun" ]] || die "no AppDir at $APPDIR — run make-appdir.sh first"

VER="$(cd "$REPO" && git describe --always --long --dirty 2>/dev/null || echo dev)"
export VERSION="$VER"      # appimagetool embeds this in the filename/metadata

log "packing $APPIMAGE ($VER)"
APPIMAGETOOL="$(ensure_tool appimagetool "$APPIMAGETOOL_URL")"
# --no-appstream keeps us off a network validator; our metainfo is upstream's.
"$APPIMAGETOOL" --no-appstream "$APPDIR" "$APPIMAGE" >/dev/null
chmod +x "$APPIMAGE"

[[ -f "$APPIMAGE" ]] || die "appimagetool produced no output at $APPIMAGE"
ok "AppImage built: $APPIMAGE ($(du -h "$APPIMAGE" | cut -f1))"
