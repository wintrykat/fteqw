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
- This fork's Windows-on-ARM (aarch64) work begun: 2026-07-06

## Modified upstream source files

| File | Change | Date |
|------|--------|------|
| `engine/vk/vk_init.c` | Added `#include <limits.h>` so `UINT_MAX` resolves under clang/macOS when building with `-DVKQUAKE`. One inserted line; no behavioural change. | 2026-07-05 |

That is the **only** modified upstream source file. Confirm at any time with:

```sh
git diff --stat            # should show engine/vk/vk_init.c | 1 +
```

The **Windows-on-ARM** port modifies **no** additional upstream source and **no**
Makefile lines — it is driven entirely by command-line overrides (documented in
`docs/PORTING-WINDOWS.md`). The `<limits.h>` line above is platform-agnostic and
serves Vulkan on both macOS and Windows-on-ARM.

## Files added by this fork (all GPL-2.0)

- `README.md` — this fork's readme (upstream's preserved as `README.upstream.md`)
- `docs/PORTING.md`, `docs/BUILDING.md` — macOS change/workaround docs and build guide
- `docs/PORTING-WINDOWS.md`, `docs/HARDWARE-TESTING.md`, `docs/WINDOWS-ARM-PORT.md` — Windows-on-ARM workaround docs, real-device checklist, and implementation brief
- `macos/scripts/*`, `macos/tests/*` — macOS reproducible build + test suite
- `windows/scripts/*`, `windows/tests/*`, `windows/installer/*` — Windows-on-ARM build, packaging, self-containment audit, tests, and Inno Setup installer
- `.github/*` — CI (macOS + Windows-on-ARM) and issue templates
- `ATTRIBUTION.md`, `CONTRIBUTING.md`, `.gitignore`

## No bundled game data

This repository contains no id Software game data (no `pak0.pak`, maps, etc.).
Users supply their own Quake data at runtime.

## Third-party runtime libraries

The distributed macOS `.app` bundles the following libraries, obtained via
Homebrew, each under its own license (all GPL-compatible): SDL (sdl2-compat,
SDL3), MoltenVK (Apache-2.0), FreeType (FTL/GPL), libpng, jpeg-turbo, libogg,
libvorbis, Opus, Speex, and FFmpeg (LGPL/GPL depending on build). Their source is
available from their respective projects and from Homebrew.

The Windows-on-ARM package bundles the equivalent libraries obtained via **MSYS2
CLANGARM64** (FreeType, libpng, jpeg-turbo, libogg/libvorbis, Opus, Speex, FFmpeg
and its codec dependencies, plus the LLVM C++ runtime), each under its own
GPL-compatible license; source is available from MSYS2 and the upstream projects.
No Vulkan runtime is bundled on Windows — the Adreno GPU driver provides it.
Windows system DLLs (`kernel32`, `d3d11`, `dxgi`, `vulkan-1`, …) are not
redistributed; they belong to the OS.
