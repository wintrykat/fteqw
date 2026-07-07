# 20-engine.sh — the engine binary itself.
section "Engine binary"

check    "engine binary exists"   test -f "$ENGINE_BIN"
contains "engine is aarch64 ELF"  "aarch64" "$(file -b "$ENGINE_BIN" 2>/dev/null)"

# Both renderers genuinely compiled in (not stubbed by #ifdef VKQUAKE / GLQUAKE).
# The shipped binary is stripped, so match strip-proof renderer marker strings:
# "Vulkan-SDL" is emitted only under -DVKQUAKE; "OpenGL" is the GL renderer name.
# (nm symbols, if the binary happens to be unstripped, are folded in too.)
marks="$(nm "$ENGINE_BIN" 2>/dev/null; LC_ALL=C grep -a -o -E 'Vulkan-SDL|OpenGL' "$ENGINE_BIN" 2>/dev/null || true)"
contains "OpenGL renderer present" "OpenGL"     "$marks"
contains "Vulkan renderer present" "Vulkan-SDL" "$marks"

# Engine actually runs. With data it plays the registered paks; without, it still
# starts and reaches filesystem/basedir init (proves the binary loads and runs).
out="$(run_engine 4 -dedicated +quit)"
if ((HAVE_DATA)); then
  contains "engine loads registered Quake data" "registered version" "$out"
else
  contains "engine starts (reaches basedir resolution)" "basedir" "$out"
fi
