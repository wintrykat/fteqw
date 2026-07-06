#!/bin/zsh
# build-all.sh — one command: build engine, assemble the self-contained app,
# then build + bundle the plugins. Pass --install to auto-install missing
# Homebrew formulae first.
#
#   ./macos/scripts/build-all.sh [--install]
#
# Result: $FTEQW_APP (default ~/Applications/FTEQW.app), fully self-contained.
source "${0:A:h}/common.sh"

log "FTEQW — Apple Silicon build"
ensure_formulae "${1:-}"
"${0:A:h}/build-engine.sh"  "${1:-}"
"${0:A:h}/make-app.sh"
"${0:A:h}/build-plugins.sh"
ok "complete: $FTEQW_APP"
print -P "%F{cyan}Put Quake data (id1/, qw/, mods) in:%f $FTEQW_DATA"
