# 30-renderers.sh — OpenGL and Vulkan/MoltenVK.
# Static checks always run. Actual renderer *initialisation* needs a display and
# Quake data, so those are gated on HAVE_DATA (they run locally, skip in headless CI).
section "Renderers (GL + Vulkan/MoltenVK)"

check    "bundled MoltenVK present"        test -f "$FW/libMoltenVK.dylib"
contains "bundled MoltenVK is arm64"       "arm64" "$(file -b "$FW/libMoltenVK.dylib" 2>/dev/null)"

if (( HAVE_DATA )); then
  # GL init on the universal id1 map 'start'
  glout="$(run_engine 5 +set vid_renderer gl +set vid_fullscreen 0 +map start)"
  contains "OpenGL renderer initialises"   "renderer initialized" "$glout"
  # Vulkan init through the BUNDLED MoltenVK (as the launcher wires it)
  vkout="$(SDL_VULKAN_LIBRARY="$FW/libMoltenVK.dylib" run_engine 5 +set vid_renderer vk +set vid_fullscreen 0 +map start)"
  contains "Vulkan renderer initialises"   "Vulkan-SDL renderer initialized" "$vkout"
  contains "Vulkan uses MoltenVK"          "MoltenVK" "$vkout"
  contains "Vulkan sees an Apple GPU"      "Apple"    "$vkout"
else
  skip "OpenGL renderer initialises"       "needs a display + Quake data (id1)"
  skip "Vulkan renderer initialises"       "needs a display + Quake data (id1)"
fi
