#!/usr/bin/env bash
# 60-behaviour.sh — runtime BEHAVIOUR of the built engine (Windows-on-ARM).
#
# Mirrors macos/tests/60-behaviour.sh and linux/tests/60-behaviour.sh: drives the
# platform-neutral tests/behaviour/behaviour-suite.sh against the licensing-clean
# ftetest fixture and folds its results into this harness's pass/fail counters.
# Needs NO id data.
#
# This is Tier 1: a headless dedicated server — no GPU, renderer, window, or input
# — so it asserts the same platform-identical engine behaviour (map/QuakeC load,
# precache, cvars, graceful bad-content/bad-mod, changelevel, console/cvar) that
# macOS and Linux assert, and runs in the Parallels VM and on windows-11-arm CI.
section "runtime behaviour (ftetest fixture)"

# repo root: windows/tests -> repo. run.sh cd's into this dir before sourcing.
REPO="$(cd ../.. && pwd)"
SUITE="$REPO/tests/behaviour/behaviour-suite.sh"
FIXTURE="$REPO/fixtures/ftetest"

# Prefer the packaged engine (fteqw.exe); fall back to the dev build tree
# (build-engine.sh emits engine/release/fteqw64.exe).
BEH_ENGINE=""
for cand in "$ENGINE_EXE" "$REPO/engine/release/fteqw64.exe"; do
  [[ -n "$cand" && -f "$cand" ]] && { BEH_ENGINE="$cand"; break; }
done

if [[ ! -f "$SUITE" ]]; then
  skip "behaviour-suite present" "missing $SUITE"
elif [[ -z "$BEH_ENGINE" ]]; then
  skip "behaviour engine present" "no engine (package or engine/release/fteqw64.exe)"
else
  # The committed fixture binaries are used as-is (no --build): regenerating them
  # needs python3 + fteqcc, which the Windows test host is not assumed to have.
  # The suite reads console output via -condebug's qconsole.log (a Windows GUI
  # .exe writes little to a redirected stdout) and cygpath-converts paths itself.
  # WER dialogs are not suppressed here: the shipped engine carries the SV_Init
  # crash fix, so the bad-map/bad-mod lanes diagnose rather than crash.
  out="$(/bin/sh "$SUITE" --engine "$BEH_ENGINE" --fixture "$FIXTURE" --timeout 15 2>/dev/null)"
  while IFS= read -r line; do
    case "$line" in
      BEHAVIOUR-PASS:*) pass "behaviour:${line#BEHAVIOUR-PASS: }" ;;
      BEHAVIOUR-FAIL:*) fail "behaviour:${line#BEHAVIOUR-FAIL: }" ;;
      BEHAVIOUR-SKIP:*) skip "behaviour:${line#BEHAVIOUR-SKIP: }" "see suite output" ;;
    esac
  done <<< "$out"
fi
