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
| `engine/server/sv_main.c` | Establish a `setjmp(host_abort)` recovery point in `SV_Init` before the dedicated startup command buffer runs. Without it, a bad/missing `+map` on the command line (`Mod_LoadModel` → `Host_EndGame` → `longjmp`) longjmps through an **uninitialised** `jmp_buf` and SIGSEGVs at startup instead of printing the error. Robustness fix; the normal good-map path is unchanged. Found by the behavioural test suite (`tests/behaviour/`, fixture `fixtures/ftetest/`); reported upstream (`docs/upstream/dedicated-startup-badmap-crash.md`). | 2026-07-07 |

These are the **only** modified upstream source files. The `vk_init.c` line is a
build fix; the `sv_main.c` block is a crash fix the fork's new behavioural tests
surfaced and now guard — it is being submitted upstream, and the fork edit can be
dropped once upstream carries the fix. Neither affects the Linux/arm64 AppImage
build (Linux is FTEQW's native `m-rel FTE_TARGET=SDL2` path); the `sv_main.c` fix
is platform-neutral and benefits every dedicated build. Confirm the full set of
engine edits at any time with:

```sh
git diff --stat engine/    # engine/vk/vk_init.c | 1 + ; engine/server/sv_main.c | 18 +
```

Each engine edit is guarded by a test that goes red if it regresses (house rule:
*every workaround gets a test*) — `macos/tests` / `linux/tests` for the build fix,
`tests/behaviour` for the crash fix.

## Files added by this fork (all GPL-2.0)

- `README.md` — this fork's readme (upstream's preserved as `README.upstream.md`)
- `docs/PORTING.md`, `docs/BUILDING.md` — macOS change/workaround docs + build guide
- `docs/PORTING-LINUX.md`, `docs/BUILDING-LINUX.md` — Linux AppImage workaround docs + build guide
- `macos/scripts/*`, `macos/tests/*` — macOS reproducible build, packaging, and test suite
- `linux/scripts/*`, `linux/tests/*` — Linux AppImage build, packaging, and test suite
- `tests/behaviour/*` — platform-neutral runtime **behavioural** test suite (drives the
  engine headless and asserts it loads maps, runs QuakeC, and fails gracefully)
- `fixtures/ftetest/*` — original, licensing-clean test gamedir (map, QuakeC, generator);
  contains **no** id Software data (see `fixtures/ftetest/LICENSE`)
- `docs/upstream/*` — bug reports prepared for submission to upstream FTEQW
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
