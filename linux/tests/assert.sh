#!/usr/bin/env bash
# assert.sh — tiny test harness. Assertions record pass/fail/skip and KEEP GOING
# (no set -e), so a full run reports every problem at once. run.sh exits non-zero
# if anything failed, which is what CI keys off. Linux port of macos/tests/assert.sh.

T_PASS=0; T_FAIL=0; T_SKIP=0; T_FAILED_NAMES=()

if [[ -t 1 ]]; then _c(){ tput setaf "$1" 2>/dev/null||true; }; _r(){ tput sgr0 2>/dev/null||true; }
else _c(){ :; }; _r(){ :; }; fi
_green(){ printf '%s%s%s\n' "$(_c 2)" "$*" "$(_r)"; }
_red(){   printf '%s%s%s\n' "$(_c 1)" "$*" "$(_r)"; }
_yellow(){ printf '%s%s%s\n' "$(_c 3)" "$*" "$(_r)"; }

pass(){ ((T_PASS++)); _green "  ✓ $1"; }
fail(){ ((T_FAIL++)); T_FAILED_NAMES+=("$1"); _red "  ✗ $1${2:+  — $2}"; }
skip(){ ((T_SKIP++)); _yellow "  ~ $1  (skipped: $2)"; }

# check "<name>" <command…>  — pass iff the command exits 0
check(){ local name="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$name"; else fail "$name" "exit $?"; fi; }
# contains "<name>" "<needle>" "<haystack>"
contains(){ case "$3" in *"$2"*) pass "$1";; *) fail "$1" "missing: $2";; esac; }
# not_contains "<name>" "<needle>" "<haystack>"
not_contains(){ case "$3" in *"$2"*) fail "$1" "unexpected: $2";; *) pass "$1";; esac; }
section(){ printf '\n%s▸ %s%s\n' "$(_c 6)" "$*" "$(_r)"; }

# --- environment discovered once ---------------------------------------------
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
CPU="$(uname -m)"
: "${BUILD_DIR:=$REPO/build/linux}"
: "${APPDIR:=$BUILD_DIR/FTEQW.AppDir}"
: "${APPIMAGE:=$BUILD_DIR/FTEQW-$CPU.AppImage}"
: "${FTEQW_DATA:=${XDG_DATA_HOME:-$HOME/.local/share}/fteqw}"
# Export it: the packed AppImage's AppRun only injects -basedir when it sees
# FTEQW_DATA in its environment (that is the documented user contract). The
# 50-appimage run test relies on that, so a bare assignment would leave the
# AppImage unable to find the data dir.
export FTEQW_DATA
ENGINE_BIN="$APPDIR/usr/bin/fteqw-engine"

HAVE_DATA=0; [[ -f "$FTEQW_DATA/id1/pak0.pak" ]] && HAVE_DATA=1

# --- self-containment allowlist + audit (kept in sync with scripts/common.sh) -
# Deliberately duplicated rather than sourced: common.sh runs `set -euo pipefail`,
# which must NOT leak into the no-errexit test shell.
ALLOWLIST=(
  ld-linux libc.so libm.so libdl.so libpthread librt.so libresolv libutil
  libgcc_s libstdc++
  libGL libGLX libGLdispatch libOpenGL libEGL libGLU
  libexpat
  libvulkan
  libX11 libxcb libXext libXi libXrandr libXrender libXfixes libXcursor
  libXinerama libXss libXxf86vm libXau libXdmcp libXdamage libXt libSM libICE
  libbsd libmd
  libwayland libxkbcommon libdecor libdrm libgbm libudev
  libffi
)
is_allowlisted(){ local base="$1" p; for p in "${ALLOWLIST[@]}"; do [[ "$base" == "$p"* ]] && return 0; done; return 1; }
resolved_deps(){ ldd "$1" 2>/dev/null | awk '/=>/ && $3 ~ /^\// {print $1"\t"$3} !/=>/ && $1 ~ /^\// {n=$1; sub(/.*\//,"",n); print n"\t"$1}'; }
# audit_selfcontained <elf …>  — echo any dep resolving outside the AppDir that is
# not on the host allowlist; empty output + return 0 means fully self-contained.
audit_selfcontained(){
  local bad=() elf base path
  for elf in "$@"; do
    [[ -f "$elf" ]] || continue
    while IFS=$'\t' read -r base path; do
      [[ -z "$base" ]] && continue
      case "$path" in "$APPDIR"/*) continue ;; esac
      is_allowlisted "$base" && continue
      bad+=("$base ($path)")
    done < <(resolved_deps "$elf")
  done
  ((${#bad[@]})) && { printf '%s\n' "${bad[@]}" | sort -u; return 1; }
  return 0
}

# Software-render capability (lets GL/Vulkan init run with no real GPU).
HAVE_XVFB=0; command -v xvfb-run >/dev/null 2>&1 && HAVE_XVFB=1
# Match both spellings: some distros arch-suffix it (lvp_icd.x86_64.json), Ubuntu
# 24.04/arm64 ships it plain (lvp_icd.json) — so glob lvp_icd*.json, not lvp_icd.*.json.
LVP_ICD="$(ls /usr/share/vulkan/icd.d/lvp_icd*.json 2>/dev/null | head -1 || true)"

# run_engine <seconds> <args…>  — run the engine binary directly (so stdout is
# captured), headless, with -basedir pointed at the data dir.
run_engine(){
  local secs="$1"; shift
  local log; log="$(mktemp)"
  ( "$ENGINE_BIN" -basedir "$FTEQW_DATA" "$@" >"$log" 2>&1 & local p=$!
    sleep "$secs"; kill "$p" 2>/dev/null; wait "$p" 2>/dev/null ) >/dev/null 2>&1
  cat "$log"; rm -f "$log"
}

# run_engine_video <max-seconds> <args…>  — like run_engine but under a virtual X
# display with the Mesa software rasterisers forced on (llvmpipe GL / lavapipe
# Vulkan), so a windowed renderer can initialise on a GPU-less runner.
#
# <max-seconds> is an UPPER BOUND, not a fixed wait: we poll for the "renderer
# initialized" marker (shared by both the GL "OpenGL renderer initialized" and
# the VK "Vulkan-SDL renderer initialized" lines) and stop the instant it appears
# — so a warm run returns in ~1s while a cold software-raster init (first llvmpipe
# / lavapipe pipeline build in a fresh VM can take several seconds) still gets the
# headroom it needs. A fixed short sleep here was the classic flake.
run_engine_video(){
  local secs="$1"; shift
  local log; log="$(mktemp)"
  # Route the software-render env through `env`: a VK_ICD_FILENAMES=… token that
  # comes from ${LVP_ICD:+…} expansion is NOT honoured as a shell assignment prefix
  # (bash would try to exec it as the command), but IS a valid argument to `env`.
  # The old inline-assignment form silently exec-failed once LVP_ICD was non-empty.
  ( xvfb-run -a env LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe \
    ${LVP_ICD:+VK_ICD_FILENAMES="$LVP_ICD"} \
    "$ENGINE_BIN" -basedir "$FTEQW_DATA" +set vid_fullscreen 0 "$@" \
      >"$log" 2>&1 & local p=$!
    local i=0 max=$(( secs * 4 ))
    while (( i++ < max )); do
      grep -q "renderer initialized" "$log" 2>/dev/null && break
      kill -0 "$p" 2>/dev/null || break     # engine exited on its own
      sleep 0.25
    done
    kill "$p" 2>/dev/null; wait "$p" 2>/dev/null ) >/dev/null 2>&1
  cat "$log"; rm -f "$log"
}
