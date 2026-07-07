#!/usr/bin/env bash
# 60-behaviour.sh — runtime BEHAVIOUR of the built engine (Linux).
#
# Mirrors macos/tests/60-behaviour.sh: drives the platform-neutral
# tests/behaviour/behaviour-suite.sh against the licensing-clean ftetest fixture
# and folds its results into this harness's pass/fail counters. Needs NO id data.
#
# The headless dedicated lane needs no GPU/display, so this runs in CI/VM as-is.
section "runtime behaviour (ftetest fixture)"

# repo root: linux/tests -> repo. run.sh cd's into this dir before sourcing.
REPO="$(cd ../.. && pwd)"
SUITE="$REPO/tests/behaviour/behaviour-suite.sh"
FIXTURE="$REPO/fixtures/ftetest"

# Prefer an explicit ENGINE (set by run.sh), the AppDir engine, then dev build.
BEH_ENGINE=""
for cand in "${ENGINE:-}" "$APPDIR/usr/bin/fteqw-sdl2" "$REPO/engine/release/fteqw-sdl2"; do
  [[ -n "$cand" && -x "$cand" ]] && { BEH_ENGINE="$cand"; break; }
done

if [[ ! -f "$SUITE" ]]; then
  skip "behaviour-suite present" "missing $SUITE"
elif [[ -z "$BEH_ENGINE" ]]; then
  skip "behaviour engine present" "no built engine (AppDir or engine/release)"
else
  out="$(/bin/sh "$SUITE" --engine "$BEH_ENGINE" --fixture "$FIXTURE" --build --timeout 12 2>/dev/null)"
  while IFS= read -r line; do
    case "$line" in
      BEHAVIOUR-PASS:*) pass "behaviour:${line#BEHAVIOUR-PASS: }" ;;
      BEHAVIOUR-FAIL:*) fail "behaviour:${line#BEHAVIOUR-FAIL: }" ;;
      BEHAVIOUR-SKIP:*) skip "behaviour:${line#BEHAVIOUR-SKIP: }" "see suite output" ;;
    esac
  done <<< "$out"
fi
