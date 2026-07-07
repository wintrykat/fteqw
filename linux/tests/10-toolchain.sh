# 10-toolchain.sh — the build/runtime environment this port assumes.
# Guards against distro / upstream drift that would silently break builds.
section "Toolchain & environment"

contains "host is arm64 (aarch64)" "aarch64" "$(uname -m)"
check    "a C compiler is present"          command -v cc
check    "pkg-config present"               command -v pkg-config
check    "patchelf present (dep bundling)"  command -v patchelf

ARCH="$(cc -dumpmachine 2>/dev/null || true)"
# Static archives FTE_TARGET=SDL2 links from libs-<arch>/*.a (build-engine.sh).
for a in libpng.a libjpeg.a libvorbisfile.a libvorbis.a libogg.a; do
  if ls "/usr/lib/$ARCH/$a" "/usr/lib/$a" >/dev/null 2>&1 || \
     ls "/usr/lib/$ARCH/${a%.a}"*.a >/dev/null 2>&1; then
    pass "static lib available: $a"
  else
    fail "static lib available: $a" "install the matching -dev package"
  fi
done

check "SDL2 dev present"      pkg-config --exists sdl2
check "freetype dev present"  pkg-config --exists freetype2
check "Vulkan loader dev present" pkg-config --exists vulkan
check "ffmpeg (libavformat) dev present" pkg-config --exists libavformat

# Software rasterisers — the Linux edge that lets renderers init with no GPU.
# Informational: their presence upgrades some Tier-2 checks to run headlessly.
if ((HAVE_XVFB)); then pass "Xvfb present (headless renderer tests can run)"
else skip "Xvfb present" "install xvfb to run headless GL/Vulkan init tests"; fi
if [[ -n "$LVP_ICD" ]]; then pass "lavapipe Vulkan ICD present ($LVP_ICD)"
else skip "lavapipe Vulkan ICD present" "install mesa-vulkan-drivers for software Vulkan"; fi
