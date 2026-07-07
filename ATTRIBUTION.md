# Attribution & change summary

This project is a derivative work of **FTEQW** and is distributed under the same
license, the **GNU General Public License, version 2** (see `LICENSE`). It
also derives from the original **Quake** sources, © id Software, released under
the GPL.

GPL-2.0 §2(a) requires that modified files carry prominent notice of the change
and its date, and that the terms of the whole be the GPL. This file provides
that summary; all files added by this fork are GPL-2.0.

## Provenance

- Upstream engine: FTEQW — <https://www.fteqw.org/> · <https://github.com/fte-team/fteqw>
- Forked at upstream revision: `f937b9d` (see the engine's `version` output / `git log`)
- This fork's macOS/Apple-Silicon work begun: 2026-07-05

## Modified upstream source files

| File | Change | Date |
|------|--------|------|
| `engine/vk/vk_init.c` | Added `#include <limits.h>` so `UINT_MAX` resolves under clang/macOS when building with `-DVKQUAKE`. One inserted line; no behavioural change. | 2026-07-05 |

That is the **only** modified upstream source file — for **all** platforms,
including the Linux/arm64 AppImage, which needs no engine or Makefile edit at all
(Linux is FTEQW's native `m-rel FTE_TARGET=SDL2` path; the `<limits.h>` line above
is a harmless no-op there). Confirm at any time with:

```sh
git diff --stat            # should show engine/vk/vk_init.c | 1 +
```

## Files added by this fork (all GPL-2.0)

- `README.md` — this fork's readme (upstream's preserved as `README.upstream.md`)
- `docs/PORTING.md`, `docs/BUILDING.md` — macOS change/workaround docs + build guide
- `docs/PORTING-LINUX.md`, `docs/BUILDING-LINUX.md` — Linux AppImage workaround docs + build guide
- `macos/scripts/*`, `macos/tests/*` — macOS reproducible build, packaging, and test suite
- `linux/scripts/*`, `linux/tests/*` — Linux AppImage build, packaging, and test suite
- `.github/*` — CI (macOS + Linux) and issue templates
- `ATTRIBUTION.md`, `CONTRIBUTING.md`, `.gitignore`

The Linux AppImage bundles upstream's own `dist/linux/org.fteqw.fteqw.desktop`,
`dist/linux/org.fteqw.fteqw.metainfo.xml`, and `dist/org.fteqw.fteqw.svg` (icon),
all part of the FTEQW source tree and GPL-2.0.

## No bundled game data

This repository contains no id Software game data (no `pak0.pak`, maps, etc.).
Users supply their own Quake data at runtime.

## Third-party runtime libraries

The distributed macOS `.app` bundles the following libraries, obtained via
Homebrew, each under its own license (all GPL-compatible): SDL (sdl2-compat,
SDL3), MoltenVK (Apache-2.0), FreeType (FTL/GPL), libpng, jpeg-turbo, libogg,
libvorbis, Opus, Speex, and FFmpeg (LGPL/GPL depending on build). Their source is
available from their respective projects and from Homebrew.

The distributed Linux `.AppImage` bundles the same class of libraries, obtained
from the distro package manager (Debian/Ubuntu apt): SDL2, FreeType, Opus, Speex,
FFmpeg (`libav*`) and their dependencies. libpng, jpeg-turbo, libogg and libvorbis
are linked **statically** into the engine. It deliberately does **not** bundle the
OpenGL/Vulkan/X11/Wayland/libdrm graphics stack — those come from the host GPU
driver. Their source is available from the respective projects and the distro.
