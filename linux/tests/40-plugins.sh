# 40-plugins.sh — the ffmpeg (media) and qi (Quaddicted) plugins.
section "Plugins (ffmpeg + qi)"

for p in ffmpeg qi; do
  so="$APPDIR/usr/bin/fteplug_$p.so"
  check    "fteplug_$p.so exists"           test -f "$so"
  contains "fteplug_$p.so is aarch64 ELF"   "aarch64" "$(file -b "$so" 2>/dev/null)"
  # self-contained: no dependency resolves outside the AppDir except host/driver libs
  if refs="$(audit_selfcontained "$so" 2>&1)" && [[ -z "$refs" ]]; then
    pass "fteplug_$p.so is self-contained (deps bundled or host driver/ABI)"
  else
    fail "fteplug_$p.so is self-contained" "external: $(printf '%s' "$refs" | tr '\n' ' ')"
  fi
  # FTE plugin-manager metadata survived (readable as a trailing zip)
  meta="$(unzip -p "$so" - 2>/dev/null || true)"
  contains "fteplug_$p.so carries embedded metadata" "title" "$meta"
done

# Dynamic load inside the engine (needs data so the engine reaches +plug_load).
if ((HAVE_DATA)); then
  out="$(run_engine 5 -dedicated +plug_load ffmpeg +plug_load qi +plug_list +quit)"
  contains "ffmpeg plugin loads" "fteplug_ffmpeg" "$out"
  contains "qi plugin loads"     "fteplug_qi"     "$out"
else
  skip "plugins load in-engine" "needs Quake data (id1) for the engine to reach plug_load"
fi
