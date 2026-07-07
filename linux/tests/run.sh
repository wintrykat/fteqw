#!/usr/bin/env bash
# run.sh — run the whole suite and exit non-zero if anything failed.
#   ./linux/tests/run.sh
# Honours BUILD_DIR / APPDIR / APPIMAGE / FTEQW_DATA. Tests that need a display +
# Quake data skip automatically when absent; software-render tests run headless
# (llvmpipe/lavapipe) when Xvfb + Mesa are present.
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./assert.sh

printf '%sFTEQW — Linux/%s AppImage test suite%s\n' "$(_c 6)" "$CPU" "$(_r)"
printf '  appdir:   %s\n' "$APPDIR"
printf '  appimage: %s\n' "$APPIMAGE"
printf '  data:     %s  %s\n' "$FTEQW_DATA" \
  "$( ((HAVE_DATA)) && echo '(present)' || echo '(absent — data-dependent tests will skip)')"

for t in [0-9]*.sh; do source "./$t"; done

printf '\n%s────────────────────────────────────────%s\n' "$(_c 6)" "$(_r)"
printf '  passed: %s%d%s   failed: %s%d%s   skipped: %s%d%s\n' \
  "$(_c 2)" "$T_PASS" "$(_r)" "$(_c 1)" "$T_FAIL" "$(_r)" "$(_c 3)" "$T_SKIP" "$(_r)"
if ((T_FAIL)); then
  _red "FAILURES:"; for n in "${T_FAILED_NAMES[@]}"; do printf '  - %s\n' "$n"; done
  exit 1
fi
_green "All good."
