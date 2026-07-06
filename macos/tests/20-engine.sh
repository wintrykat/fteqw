# 20-engine.sh — the engine binary itself.
section "Engine binary"

check "engine binary exists"            test -f "$ENGINE_BIN"
contains "engine is arm64"              "arm64" "$(file -b "$ENGINE_BIN" 2>/dev/null)"
check "engine has a valid code signature" codesign -v --strict "$ENGINE_BIN"

# Both renderers genuinely compiled in (not stubbed by #ifdef VKQUAKE / GLQUAKE).
syms="$(nm "$ENGINE_BIN" 2>/dev/null)"
contains "OpenGL renderer present (_GLBE_Init)" "_GLBE_Init" "$syms"
contains "Vulkan renderer present (_VK_Init)" "_VK_Init" "$syms"

# Engine actually runs. With data it plays the registered paks; without, it still
# starts and reaches filesystem init (proves the binary loads and executes).
out="$(run_engine 4 -dedicated +quit)"
if (( HAVE_DATA )); then
  contains "engine loads registered Quake data" "registered version" "$out"
else
  contains "engine starts (reaches basedir resolution)" "basedir" "$out"
fi
