#!/usr/bin/env bash
# build-all.sh — one command: build engine + plugins, assemble the self-contained
# package, and produce the portable ZIP. Pass --install to auto-install missing
# MSYS2 packages first.
#
#   ./windows/scripts/build-all.sh [--install]
#
# Result: $FTEQW_PKG (default windows/dist/FTEQW), fully self-contained, plus
# windows/dist/FTEQW-<ver>-win-arm64.zip. The Inno Setup installer is a separate,
# optional step (make-installer.sh) since it needs ISCC on the machine.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

log "FTEQW — Windows-on-ARM (aarch64) build"
ensure_packages "${1:-}"
"$SCRIPT_DIR/build-engine.sh"  "${1:-}"
"$SCRIPT_DIR/build-plugins.sh"
"$SCRIPT_DIR/make-package.sh"

# --- portable ZIP (always ship this) ----------------------------------------
VER="$(cd "$REPO" && git describe --always --long --dirty 2>/dev/null || echo dev)"
DIST="$REPO/windows/dist"
ZIP="$DIST/FTEQW-$VER-win-arm64.zip"
rm -f "$ZIP"
( cd "$(dirname "$FTEQW_PKG")" && zip -q -9 -r "$ZIP" "$(basename "$FTEQW_PKG")" )
[[ -f "$ZIP" ]] || die "ZIP not produced"
ok "portable ZIP: $ZIP ($(du -h "$ZIP" | cut -f1))"

ok "complete: $FTEQW_PKG"
printf '%sPut Quake data (id1/, qw/, mods) in:%s %s\n' "$C_CYAN" "$C_0" "$FTEQW_DATA"
printf '%sOptional installer:%s windows/scripts/make-installer.sh (needs Inno Setup ISCC)\n' "$C_CYAN" "$C_0"
