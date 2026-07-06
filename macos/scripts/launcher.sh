#!/bin/sh
# FTEQW.app launcher (installed as Contents/MacOS/FTEQW, the CFBundleExecutable).
# Everything is resolved at runtime, so this file is machine-independent.
#  - Game data defaults to ~/Library/Application Support/FTEQW unless -basedir given.
#  - Vulkan via the bundled MoltenVK; default renderer unless one is chosen
#    (+set vid_renderer …, -gl, -vk, -sw).
#  - Auto-loads the bundled ffmpeg (media) and qi (Quaddicted) plugins.
# Explicit arguments always win over these defaults.
HERE="$(cd "$(dirname "$0")" && pwd)"
FW="$HERE/../Frameworks"
DATA="$HOME/Library/Application Support/FTEQW"
mkdir -p "$DATA"

# Point SDL straight at the bundled MoltenVK (bypasses the loader's
# portability-enumeration requirement). Only if the user hasn't overridden it.
[ -f "$FW/libMoltenVK.dylib" ] && \
  { : "${SDL_VULKAN_LIBRARY:=$FW/libMoltenVK.dylib}"; export SDL_VULKAN_LIBRARY; }

want_basedir=1; want_renderer=1
case " $* " in *" -basedir "*) want_basedir=0 ;; esac
case " $* " in *" vid_renderer "*|*" -gl "*|*" -vk "*|*" -sw "*) want_renderer=0 ;; esac

set -- +plug_load ffmpeg +plug_load qi "$@"
[ "$want_renderer" = 1 ] && set -- +set vid_renderer vk "$@"
[ "$want_basedir"  = 1 ] && set -- -basedir "$DATA" "$@"

exec "$HERE/fteqw-engine" "$@"
