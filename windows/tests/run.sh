#!/usr/bin/env bash
# run.sh — run the whole suite and exit non-zero if anything failed.
#   ./windows/tests/run.sh
# Honours FTEQW_APP / FTEQW_DATA / FTEQW_REAL_GPU. Tier-2 (real-GPU) and
# data-dependent tests skip automatically when their prerequisites are absent
# (e.g. in the VM and on CI).
cd "$(dirname "${BASH_SOURCE[0]}")"
source ./assert.sh

printf '%sFTEQW — Windows-on-ARM (aarch64) test suite%s\n' "$_C" "$_0"
printf '  package: %s\n' "$PKG"
printf '  data:    %s  %s\n' "$FTEQW_DATA" "$([[ $HAVE_DATA == 1 ]] && echo '(present)' || echo '(absent — data-dependent tests will skip)')"
printf '  real GPU: %s\n' "$([[ $HAS_GPU == 1 ]] && echo 'yes (Tier 2 enabled)' || echo 'no (Tier 2 hardware tests will skip)')"

for t in [0-9]*.sh; do source "./$t"; done

printf '\n%s----------------------------------------%s\n' "$_C" "$_0"
printf '  passed: %s%d%s   failed: %s%d%s   skipped: %s%d%s\n' "$_G" "$T_PASS" "$_0" "$_R" "$T_FAIL" "$_0" "$_Y" "$T_SKIP" "$_0"
if (( T_FAIL )); then
  printf '%sFAILURES:%s\n' "$_R" "$_0"; for n in "${T_FAILED_NAMES[@]}"; do printf '  - %s\n' "$n"; done
  exit 1
fi
printf '%sAll good.%s\n' "$_G" "$_0"
