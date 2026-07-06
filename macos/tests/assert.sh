#!/bin/zsh
# assert.sh — tiny test harness. Assertions record pass/fail/skip and KEEP GOING
# (no set -e), so a full run reports every problem at once. run.sh exits non-zero
# if anything failed, which is what CI keys off.

typeset -gi T_PASS=0 T_FAIL=0 T_SKIP=0
typeset -ga T_FAILED_NAMES=()

_green(){ print -P "%F{green}$*%f"; }; _red(){ print -P "%F{red}$*%f"; }; _yellow(){ print -P "%F{yellow}$*%f"; }

pass(){ (( T_PASS++ )); _green "  ✓ $1"; }
fail(){ (( T_FAIL++ )); T_FAILED_NAMES+=("$1"); _red   "  ✗ $1${2:+  — $2}"; }
skip(){ (( T_SKIP++ )); _yellow "  ~ $1  (skipped: $2)"; }

# check "<name>" <command…>  — pass iff the command exits 0
check(){ local name="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$name"; else fail "$name" "exit $?"; fi }

# contains "<name>" "<needle>" "<haystack>"
contains(){ case "$3" in *"$2"*) pass "$1";; *) fail "$1" "missing: $2";; esac }

# not_contains "<name>" "<needle>" "<haystack>"
not_contains(){ case "$3" in *"$2"*) fail "$1" "unexpected: $2";; *) pass "$1";; esac }

section(){ print -P "\n%F{cyan}▸ $*%f"; }

# --- environment discovered once ---------------------------------------------
: "${FTEQW_APP:=$HOME/Applications/FTEQW.app}"
: "${FTEQW_DATA:=$HOME/Library/Application Support/FTEQW}"
APP="$FTEQW_APP"
MACOS="$APP/Contents/MacOS"; FW="$APP/Contents/Frameworks"; RES="$APP/Contents/Resources"
ENGINE_BIN="$MACOS/fteqw-engine"
HAVE_DATA=0; [[ -f "$FTEQW_DATA/id1/pak0.pak" ]] && HAVE_DATA=1

# run_engine <seconds> <args…>  — run the bundled engine binary directly (so
# stdout is captured, unlike an `open`-launched bundle) and print its output.
run_engine(){
  local secs="$1"; shift
  local log; log="$(mktemp)"
  ( "$ENGINE_BIN" -basedir "$FTEQW_DATA" "$@" >"$log" 2>&1 & local p=$!
    sleep "$secs"; kill "$p" 2>/dev/null; wait "$p" 2>/dev/null ) >/dev/null 2>&1
  cat "$log"; rm -f "$log"
}
