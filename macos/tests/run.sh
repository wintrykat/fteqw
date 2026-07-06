#!/bin/zsh
# run.sh — run the whole suite and exit non-zero if anything failed.
#   ./macos/tests/run.sh
# Honours FTEQW_APP / FTEQW_DATA. Tests that need a display + Quake data skip
# automatically when data is absent (e.g. in CI).
cd "${0:A:h}"
source ./assert.sh

print -P "%F{cyan}FTEQW — Apple Silicon test suite%f"
print    "  app:  $APP"
print    "  data: $FTEQW_DATA  $([[ $HAVE_DATA == 1 ]] && echo '(present)' || echo '(absent — data-dependent tests will skip)')"

for t in [0-9]*.sh; do source "./$t"; done

print -P "\n%F{cyan}────────────────────────────────────────%f"
print -P "  passed: %F{green}$T_PASS%f   failed: %F{red}$T_FAIL%f   skipped: %F{yellow}$T_SKIP%f"
if (( T_FAIL )); then
  print -P "%F{red}FAILURES:%f"; for n in $T_FAILED_NAMES; do print "  - $n"; done
  exit 1
fi
print -P "%F{green}All good.%f"
