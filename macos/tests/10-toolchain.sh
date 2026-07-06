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

# Vulkan GPU enumeration through MoltenVK — REAL-GPU-GATED (Tier 2).
# Enumerating a physical device requires a usable Metal GPU, which headless CI
# runners may not provide: the macos-14 GitHub runner enumerates nothing, while
# macos-15 does. So this PASSES when a GPU shows up and SKIPS when none does — it
# must never hard-fail CI on the mere absence of a GPU. (The deterministic,
# always-on toolchain anchor is the "MoltenVK installed" check above.)
# Assert on `deviceName` — VkPhysicalDeviceProperties, core Vulkan 1.0, present
# whenever a device enumerates — not `driverName`, which needs
# VK_KHR_driver_properties (Vulkan 1.2) and is absent on older MoltenVK.
if command -v vulkaninfo >/dev/null 2>&1; then
  vi="$(VK_ICD_FILENAMES="$BREW/etc/vulkan/icd.d/MoltenVK_icd.json" vulkaninfo 2>/dev/null)"
  case "$vi" in
    *deviceName*) pass "Vulkan enumerates a GPU via MoltenVK" ;;
    *)            skip "Vulkan enumerates a GPU via MoltenVK" \
                       "no GPU enumerated (headless runner / no usable Metal device)" ;;
  esac
else
  skip "Vulkan GPU enumeration" "vulkaninfo (vulkan-tools) not installed"
fi
