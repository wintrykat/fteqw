#!/bin/zsh
# 60-behaviour.sh — runtime BEHAVIOUR of the built engine (macOS).
#
# Everything before this file is build/link/packaging/symbol checks. This one
# actually runs the engine against the licensing-clean ftetest fixture and
# asserts it loads a map, runs QuakeC, and fails gracefully on bad content —
# via the platform-neutral tests/behaviour/behaviour-suite.sh. Needs NO id data.
section "runtime behaviour (ftetest fixture)"

# repo root: macos/tests -> repo. run.sh cd's into this dir before sourcing.
REPO="$(cd ../.. && pwd)"
SUITE="$REPO/tests/behaviour/behaviour-suite.sh"
FIXTURE="$REPO/fixtures/ftetest"

# Prefer the installed bundle's engine; fall back to the dev build tree.
BEH_ENGINE=""
if [[ -x "$ENGINE_BIN" ]]; then
  BEH_ENGINE="$ENGINE_BIN"
elif [[ -x "$REPO/engine/release/fteqw-sdl2" ]]; then
  BEH_ENGINE="$REPO/engine/release/fteqw-sdl2"
fi

if [[ ! -f "$SUITE" ]]; then
  skip "behaviour-suite present" "missing $SUITE"
elif [[ -z "$BEH_ENGINE" ]]; then
  skip "behaviour engine present" "no built engine (bundle or engine/release)"
else
  # Quiet the macOS crash-reporter GUI: the bad-map lane may (pre-fix) crash the
  # child, and we don't want popups during CI/local runs. Best-effort only.
  defaults write com.apple.CrashReporter DialogType none >/dev/null 2>&1
  out="$(/bin/sh "$SUITE" --engine "$BEH_ENGINE" --fixture "$FIXTURE" --build --timeout 12 2>/dev/null)"
  defaults write com.apple.CrashReporter DialogType developer >/dev/null 2>&1

  # Translate the suite's machine-readable lines into our pass/fail counters.
  # NB: use a here-string, not a pipe — a `| while` subshell would drop the
  # global T_PASS/T_FAIL increments.
  while IFS= read -r line; do
    case "$line" in
      BEHAVIOUR-PASS:*) pass "behaviour:${line#BEHAVIOUR-PASS: }" ;;
      BEHAVIOUR-FAIL:*) fail "behaviour:${line#BEHAVIOUR-FAIL: }" ;;
      BEHAVIOUR-SKIP:*) skip "behaviour:${line#BEHAVIOUR-SKIP: }" "see suite output" ;;
    esac
  done <<< "$out"
fi
