#!/usr/bin/env bash
# compile.sh -- (re)generate the committed ftetest fixture binaries.
#
# Produces:
#   maps/ftetest.bsp   -- from ftetest.map via ericw-tools qbsp if available,
#                         otherwise from tools/gen_bsp.py (zero-dependency).
#   progs/ftetest.mdl, progs/ftetest.spr, sound/ftetest.wav -- from
#                         tools/gen_assets.py (zero-dependency).
#   ../progs.dat        -- from src/progs.src via fteqcc (built in-tree if needed).
#
# Everything it consumes is original authorship; no id Software content is used
# or required. Safe to run in CI: the gen_bsp.py fallback means a valid map is
# always produced even with no map compiler installed.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fixture="$(cd "$here/.." && pwd)"
repo="$(cd "$fixture/../.." && pwd)"

# --- BSP ---------------------------------------------------------------------
if command -v qbsp >/dev/null 2>&1; then
	echo "[compile] qbsp found -> compiling ftetest.map"
	qbsp "$here/ftetest.map" "$here/ftetest.bsp"
	command -v vis   >/dev/null 2>&1 && vis   "$here/ftetest.bsp" || echo "[compile] no vis (novis, all-visible)"
	command -v light >/dev/null 2>&1 && light "$here/ftetest.bsp" || echo "[compile] no light (fullbright)"
else
	echo "[compile] no qbsp -> using tools/gen_bsp.py fallback"
	python3 "$fixture/tools/gen_bsp.py" "$here/ftetest.bsp"
fi

# --- second map for the changelevel lane (mapname derives from filename) -----
cp "$here/ftetest.bsp" "$here/ftetest2.bsp"

# --- model / sprite / sound assets ------------------------------------------
echo "[compile] generating mdl/spr/wav assets"
python3 "$fixture/tools/gen_assets.py" "$fixture"

# --- progs.dat ---------------------------------------------------------------
fteqcc=""
for cand in fteqcc fteqcc.db; do
	if command -v "$cand" >/dev/null 2>&1; then fteqcc="$(command -v "$cand")"; break; fi
done
if [ -z "$fteqcc" ]; then
	for cand in "$repo/engine/release/fteqcc" "$repo/engine/release/fteqcc.db"; do
		[ -x "$cand" ] && { fteqcc="$cand"; break; }
	done
fi
if [ -z "$fteqcc" ]; then
	echo "[compile] building fteqcc in-tree"
	( cd "$repo/engine" && make qcc-rel FTE_TARGET=SDL2 >/dev/null )
	for cand in "$repo/engine/release/fteqcc" "$repo/engine/release/fteqcc.db"; do
		[ -x "$cand" ] && { fteqcc="$cand"; break; }
	done
fi
[ -n "$fteqcc" ] || { echo "[compile] ERROR: no fteqcc available" >&2; exit 1; }

echo "[compile] fteqcc: $fteqcc"
( cd "$fixture/src" && "$fteqcc" progs.src )

# --- malformed fixtures (derived from the fresh good artifacts) --------------
echo "[compile] deriving malformed fixtures for graceful-failure lanes"
python3 "$fixture/tools/gen_bad.py" "$fixture"

echo "[compile] done:"
ls -l "$here/ftetest.bsp" "$fixture/progs.dat" \
      "$fixture/progs/ftetest.mdl" "$fixture/progs/ftetest.spr" "$fixture/sound/ftetest.wav" \
      "$here/badver.bsp" "$here/trunc.bsp" "$fixture/bad/badprogs.dat" "$fixture/bad/junkprogs.dat"
