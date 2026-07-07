# 30-renderers.sh — D3D11 (default) + Vulkan.
# Tier 1: static proof both renderers are compiled into the shipped binary.
# Tier 2: actual initialisation on a REAL GPU — gated on HAS_GPU (skips in the
# Parallels VM and on windows-11-arm CI, which have no real GPU and no Vulkan).
section "Renderers (D3D11 + Vulkan)"

# --- Tier 1: both renderers present in the binary ---------------------------
# grep -c (not -q) so the large nm stream is consumed (avoid SIGPIPE + pipefail).
d3d11="$(llvm-nm "$ENGINE_EXE" 2>/dev/null | grep -c ' D3D11_Draw_Init$' || true)"
vk="$(llvm-nm "$ENGINE_EXE" 2>/dev/null | grep -c ' VK_Init$' || true)"
check    "D3D11 renderer compiled in" test "$d3d11" -gt 0
check    "Vulkan renderer compiled in" test "$vk" -gt 0

# --- Tier 2: real-GPU initialisation ----------------------------------------
# We do NOT bundle a Vulkan runtime (unlike MoltenVK on macOS): on real hardware
# the Adreno driver provides the Vulkan ICD. These need a real GPU AND data.
if (( HAS_GPU && HAVE_DATA )); then
  d3dout="$(run_engine 6 +set vid_renderer d3d11 +set vid_fullscreen 0 +map start)"
  contains "D3D11 renderer initialises"  "renderer initialized" "$d3dout"
  vkout="$(run_engine 6 +set vid_renderer vk +set vid_fullscreen 0 +map start)"
  contains "Vulkan renderer initialises" "Vulkan" "$vkout"
  contains "Vulkan enumerates a physical device" "device" "$vkout"
else
  reason="$([[ $HAS_GPU == 1 ]] && echo 'needs Quake data (id1)' || echo 'needs a real GPU (set FTEQW_REAL_GPU=1 on a device)')"
  skip "D3D11 renderer initialises (real frame)" "$reason"
  skip "Vulkan renderer initialises (Adreno)"    "$reason"
fi
