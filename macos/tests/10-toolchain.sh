# 10-toolchain.sh — the build/runtime environment this port assumes.
# These guard against upstream/Homebrew/macOS drift that would silently break builds.
section "Toolchain & environment"

contains "host is Apple Silicon (arm64)" "arm64" "$(uname -m)"
check    "clang present"        command -v clang
check    "Homebrew present"     command -v brew
check    "dylibbundler present (for self-contained bundling)" command -v dylibbundler

BREW="$(brew --prefix 2>/dev/null || echo /opt/homebrew)"
check    "MoltenVK installed"   test -f "$BREW/lib/libMoltenVK.dylib"
check    "SDL3 installed (sdl2-compat target)" test -f "$BREW/opt/sdl3/lib/libSDL3.0.dylib"
check    "ffmpeg headers installed (plugin)"   test -f "$BREW/opt/ffmpeg/include/libavformat/avformat.h"

# Vulkan stack reachable at all (headless-friendly proxy for GPU access).
if command -v vulkaninfo >/dev/null 2>&1; then
  vi="$(VK_ICD_FILENAMES="$BREW/etc/vulkan/icd.d/MoltenVK_icd.json" vulkaninfo 2>/dev/null)"
  contains "Vulkan enumerates a GPU via MoltenVK" "driverName" "$vi"
else
  skip "Vulkan GPU enumeration" "vulkaninfo (vulkan-tools) not installed"
fi
