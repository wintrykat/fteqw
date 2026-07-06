# 40-plugins.sh — the ffmpeg (media) and qi (Quaddicted) plugins.
section "Plugins (ffmpeg + qi)"

for p in ffmpeg qi; do
  so="$RES/fteplug_$p.so"
  check    "fteplug_$p.so exists"                 test -f "$so"
  contains "fteplug_$p.so is arm64"               "arm64" "$(file -b "$so" 2>/dev/null)"
  # self-contained: no Homebrew/usr-local install names
  refs="$(otool -L "$so" 2>/dev/null | tail -n +2 | grep -c '/opt/homebrew\|/usr/local' || true)"
  contains "fteplug_$p.so has no external deps"   "0" "$refs"
  # FTE plugin-manager metadata survived (readable as a trailing zip)
  meta="$(unzip -p "$so" - 2>/dev/null)"
  contains "fteplug_$p.so carries embedded metadata" "title" "$meta"
done

# Dynamic load inside the engine (needs data so the engine reaches +plug_load).
if (( HAVE_DATA )); then
  out="$(run_engine 5 -dedicated +plug_load ffmpeg +plug_load qi +plug_list +quit)"
  contains "ffmpeg plugin loads" "fteplug_ffmpeg.so"  "$(print -r -- "$out" | sed -n '/Loaded plugins/,/Scanning/p')"
  contains "qi plugin loads"     "fteplug_qi.so"      "$(print -r -- "$out" | sed -n '/Loaded plugins/,/Scanning/p')"
else
  skip "plugins load in-engine" "needs Quake data (id1) for the engine to reach plug_load"
fi
