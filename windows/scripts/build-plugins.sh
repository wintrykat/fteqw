#!/usr/bin/env bash
# build-plugins.sh — build FTEQW native plugins for Windows-on-ARM (aarch64) as
# DLLs with embedded FTE metadata. Output: engine/release/fteplug_<name>_x64.dll
#
# Unlike macOS there is NO ordering headache: PE loaders ignore trailing data and
# there is no signature to invalidate, so the Makefile's own EMBEDMETA trailing-zip
# step works unchanged — build the DLL, metadata is appended, done.
#
# Two extra overrides beyond the engine build (see docs/PORTING-WINDOWS.md):
#   * AV_BASE=       — else the ffmpeg plugin DOWNLOADS prebuilt x86_64 zeranoe
#                      ffmpeg-4.0 from archive.org (wrong arch, ancient). Empty
#                      makes it link our CLANGARM64 (arm64) ffmpeg via -lavcodec…
#   * PLUG_LDFLAGS=  — the win64 default is "-Wl,--support-old-code -static-libgcc";
#                      lld rejects --support-old-code. We need none of it.
#
# Usage:  build-plugins.sh [plugin ...]        (default: ffmpeg qi)
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

if (( $# )) && [[ "$1" != "--install" ]]; then plugins="$*"; else plugins="ffmpeg qi"; fi

log "building plugins: $plugins"
# Clean so EMBEDMETA re-appends to a fresh DLL (appending twice would nest zips).
for p in $plugins; do rm -f "$ENGINE/release/fteplug_${p}_x64.dll"; done

fte_make plugins-rel FTE_TARGET=win64 NATIVE_PLUGINS="$plugins" AV_BASE= PLUG_LDFLAGS=

for p in $plugins; do
  dll="$ENGINE/release/fteplug_${p}_x64.dll"
  [[ -f "$dll" ]] || die "$dll not built"
  machine="$(llvm-readobj --file-headers "$dll" 2>/dev/null | grep -o 'IMAGE_FILE_MACHINE_ARM64' | head -1)"
  [[ "$machine" == "IMAGE_FILE_MACHINE_ARM64" ]] || die "$dll is not ARM64"
  # Metadata is a deflated trailing zip; confirm the manifest reads back.
  unzip -p "$dll" 2>/dev/null | grep -q "package fteplug_$p" \
    || die "$dll is missing its embedded FTE metadata"
  ok "fteplug_${p}_x64.dll — ARM64 DLL, metadata embedded"
done
