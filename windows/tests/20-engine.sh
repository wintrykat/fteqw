# 20-engine.sh — the engine is a native ARM64 PE and runs headless.
# Tier 1 (always runs); the map/data checks are gated on HAVE_DATA.
section "Engine (ARM64 PE + headless run)"

check    "fteqw.exe exists"        test -f "$ENGINE_EXE"
# Genuine ARM64 machine type — the core guard against an x86 regression.
contains "fteqw.exe is ARM64 (0xAA64)" "IMAGE_FILE_MACHINE_ARM64" \
         "$(llvm-readobj --file-headers "$ENGINE_EXE" 2>/dev/null)"

# Headless run: reaches filesystem/console init and writes qconsole.log. Without
# Quake data it stops at basedir determination — still proof the engine executed.
out="$(run_engine 6 -dedicated +quit)"
check    "engine writes a console log (reached fs init)" test -n "$out"
if (( HAVE_DATA )); then
  contains "engine loads registered data" "registered" "$out"
else
  contains "engine reaches basedir init (no data)" "basedir" "$out"
fi
