#!/usr/bin/env bash
# build-all.sh — one command: build engine, assemble the self-contained AppDir,
# add + bundle plugins, then pack the AppImage. Pass --install to auto-install
# missing apt packages first.
#
#   ./linux/scripts/build-all.sh [--install]
#
# Result: build/linux/FTEQW-<cpu>.AppImage, fully self-contained (runs on any
# same-arch Linux with a working GPU driver; no dev packages needed to run it).
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

log "FTEQW — Linux/$CPU AppImage build"
ensure_packages "${1:-}"
"$SCRIPT_DIR/build-engine.sh"  "${1:-}"
"$SCRIPT_DIR/make-appdir.sh"
"$SCRIPT_DIR/build-plugins.sh"
"$SCRIPT_DIR/build-appimage.sh"
ok "complete: $APPIMAGE"
printf '%sPut Quake data (id1/, qw/, mods) in:%s %s\n' "$(_c 6)" "$(_r)" "$FTEQW_DATA"
