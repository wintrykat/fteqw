# 40-plugins.sh — ffmpeg + qi plugins are native ARM64 DLLs carrying FTE metadata.
# Tier 1 (static). Actual load via the engine is gated on HAVE_DATA.
section "Plugins (ffmpeg + qi)"

for p in ffmpeg qi; do
  dll="$PKG/fteplug_$p.dll"
  check    "fteplug_$p.dll present"  test -f "$dll"
  [[ -f "$dll" ]] || continue
  contains "fteplug_$p.dll is ARM64" "IMAGE_FILE_MACHINE_ARM64" \
           "$(llvm-readobj --file-headers "$dll" 2>/dev/null)"
  # Metadata is a deflated trailing zip; the manifest must read back.
  contains "fteplug_$p.dll carries FTE metadata" "package fteplug_$p" \
           "$(unzip -p "$dll" 2>/dev/null)"
done

# Runtime load through the engine (needs data so the engine gets far enough).
if (( HAVE_DATA )); then
  out="$(run_engine 6 -dedicated +plug_load ffmpeg +plug_load qi +plug_list +quit)"
  contains "engine loads ffmpeg plugin" "ffmpeg" "$out"
  contains "engine loads qi plugin"     "qi"     "$out"
else
  skip "engine loads ffmpeg plugin" "needs Quake data (id1)"
  skip "engine loads qi plugin"     "needs Quake data (id1)"
fi
