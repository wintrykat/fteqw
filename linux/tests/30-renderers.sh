# 30-renderers.sh — OpenGL and Vulkan.
# On Linux the graphics stack is the HOST's (GPU driver): we do not bundle
# libGL/libvulkan. The big difference from macOS/Windows is that Mesa ships
# SOFTWARE rasterisers — llvmpipe (GL) and lavapipe (Vulkan) — so we can actually
# exercise the Vulkan loader and (with data) real renderer init on a GPU-less
# runner. Real-hardware GPU rendering stays Tier 2 / manual (HARDWARE-TESTING).
section "Renderers (OpenGL + Vulkan)"

# (1) Vulkan loader + ICD sanity — data-independent, runs in CI via lavapipe.
# Mirrors macOS's vulkaninfo/MoltenVK check, but here it PASSES in headless CI
# because the software ICD always enumerates a device.
if command -v vulkaninfo >/dev/null 2>&1 && [[ -n "$LVP_ICD" ]]; then
  vi="$(VK_ICD_FILENAMES="$LVP_ICD" vulkaninfo 2>/dev/null || true)"
  case "$vi" in
    *deviceName*) pass "Vulkan loader enumerates a device (software lavapipe)" ;;
    *)            skip "Vulkan loader enumerates a device" "lavapipe present but enumerated nothing" ;;
  esac
else
  skip "Vulkan loader enumerates a device" "vulkaninfo / lavapipe not installed"
fi

# (2) Engine renderer init. Needs the engine to reach video bring-up, which needs
# game data (id1) — so gate on HAVE_DATA, exactly like the macOS suite. When data
# is present we run under Xvfb + software rasterisers so it works with no GPU.
if ((HAVE_DATA)) && ((HAVE_XVFB)); then
  glout="$(run_engine_video 20 +set vid_renderer gl +map start)"
  contains "OpenGL renderer initialises (llvmpipe)" "renderer initialized" "$glout"
  if [[ -n "$LVP_ICD" ]]; then
    vkout="$(run_engine_video 20 +set vid_renderer vk +map start)"
    contains "Vulkan renderer initialises (lavapipe)" "Vulkan-SDL renderer initialized" "$vkout"
  else
    skip "Vulkan renderer initialises (lavapipe)" "no software Vulkan ICD"
  fi
else
  skip "OpenGL renderer initialises" "needs Quake data (id1) + Xvfb"
  skip "Vulkan renderer initialises" "needs Quake data (id1) + Xvfb"
fi
