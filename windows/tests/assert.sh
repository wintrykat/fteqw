#!/usr/bin/env bash
# assert.sh — tiny test harness. Assertions record pass/fail/skip and KEEP GOING
# (no set -e), so a full run reports every problem at once. run.sh exits non-zero
# if anything failed, which is what CI keys off.
#
# Three tiers (see docs/WINDOWS-ARM-PORT.md §5):
#   Tier 1 — always runs (build/packaging/self-containment/engine-run/D3D11 on a
#            virtual GPU). Green in the VM and on windows-11-arm CI.
#   Tier 2 — hardware-gated on a REAL GPU (real D3D11 frame, Vulkan/Adreno). Skips
#            in the VM/CI. Enable on a real device with FTEQW_REAL_GPU=1.
#   Tier 3 — manual (docs/HARDWARE-TESTING.md), not automated here.

T_PASS=0; T_FAIL=0; T_SKIP=0; T_FAILED_NAMES=()

if [[ -t 1 ]]; then _G=$'\e[32m'; _R=$'\e[31m'; _Y=$'\e[33m'; _C=$'\e[36m'; _0=$'\e[0m'
else _G=; _R=; _Y=; _C=; _0=; fi

pass(){ T_PASS=$((T_PASS+1)); printf '%s  \xe2\x9c\x93%s %s\n' "$_G" "$_0" "$1"; }
fail(){ T_FAIL=$((T_FAIL+1)); T_FAILED_NAMES+=("$1"); printf '%s  \xe2\x9c\x97%s %s%s\n' "$_R" "$_0" "$1" "${2:+  — $2}"; }
skip(){ T_SKIP=$((T_SKIP+1)); printf '%s  ~%s %s  (skipped: %s)\n' "$_Y" "$_0" "$1" "$2"; }
section(){ printf '\n%s\xe2\x96\xb8 %s%s\n' "$_C" "$*" "$_0"; }

# check "<name>" <command…>  — pass iff the command exits 0
check(){ local name="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$name"; else fail "$name" "exit $?"; fi; }
# contains "<name>" "<needle>" "<haystack>"
contains(){ case "$3" in *"$2"*) pass "$1";; *) fail "$1" "missing: $2";; esac; }
# not_contains "<name>" "<needle>" "<haystack>"
not_contains(){ case "$3" in *"$2"*) fail "$1" "unexpected: $2";; *) pass "$1";; esac; }

# --- environment discovered once ---------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
: "${FTEQW_APP:=$REPO/windows/dist/FTEQW}"
PKG="$FTEQW_APP"
: "${FTEQW_DATA:=${LOCALAPPDATA:-$HOME/AppData/Local}/FTEQW}"
case "$FTEQW_DATA" in *[\\:]*) FTEQW_DATA="$(cygpath -u "$FTEQW_DATA" 2>/dev/null || echo "$FTEQW_DATA")";; esac
ENGINE_EXE="$PKG/fteqw.exe"

# Ensure the CLANGARM64 tools (llvm-readobj/nm, ntldd, unzip) are reachable.
command -v llvm-readobj >/dev/null 2>&1 || export PATH="/c/msys64/clangarm64/bin:/c/msys64/usr/bin:$PATH"

HAVE_DATA=0; [[ -f "$FTEQW_DATA/id1/pak0.pak" ]] && HAVE_DATA=1

# HAS_GPU gates Tier 2. The Parallels VM and windows-11-arm CI have no real GPU
# (and no Vulkan at all), so default off. A device owner / self-hosted GPU runner
# sets FTEQW_REAL_GPU=1. As a hint, a driver-provided vulkan-1.dll (absent in the
# VM) suggests real hardware, but we never auto-assume — explicit opt-in only.
HAS_GPU=0; [[ "${FTEQW_REAL_GPU:-0}" == "1" ]] && HAS_GPU=1

# run_engine <seconds> <args…>  — run the packaged engine headless with -condebug
# and echo its qconsole.log. FTE writes the log into the game-data dir.
run_engine(){
  local secs="$1"; shift
  local logdir; logdir="$(mktemp -d)"
  rm -f "$FTEQW_DATA/qconsole.log" 2>/dev/null || true
  ( "$ENGINE_EXE" -basedir "$(cygpath -m "$FTEQW_DATA")" -condebug "$@" >"$logdir/out.txt" 2>&1 &
    local p=$!; for _ in $(seq 1 "$secs"); do kill -0 $p 2>/dev/null || break; sleep 1; done
    kill $p 2>/dev/null; wait $p 2>/dev/null ) >/dev/null 2>&1
  cat "$FTEQW_DATA/qconsole.log" 2>/dev/null
  rm -rf "$logdir"
}
