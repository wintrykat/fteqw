# Porting notes — FTEQW as a Linux/arm64 AppImage

This document records every workaround the Linux packaging applies on top of
upstream [FTEQW](https://www.fteqw.org/), **why** it exists, and **how to
reconstruct or retire it** when upstream FTEQW, the distro libraries, or the
AppImage tooling change. It is the troubleshooting reference the test suite
(`linux/tests/`) backs up: a failing test should point you at the section here
that explains the moving part. It mirrors the macOS `docs/PORTING.md`.

> Scope: `FTE_TARGET=SDL2`, merged OpenGL + Vulkan (`m-rel`), **aarch64**,
> packaged as a single relocatable `.AppImage`. Developed against Ubuntu on
> arm64 (Parallels VM); intended to run on any same-arch Linux with a working
> GPU driver.

**Zero engine source edits.** Unlike macOS (one line) and Windows-on-ARM (a new
Makefile target), the Linux AppImage needs **no** change to the engine or the
Makefile — Linux is FTEQW's native platform and `m-rel FTE_TARGET=SDL2` builds as
shipped. The one-line `#include <limits.h>` already in `engine/vk/vk_init.c` (the
macOS fix) is a harmless no-op here, because `UINT_MAX` arrives transitively
through other headers on glibc. `git diff` against upstream should still show
exactly that one inserted line. Everything below lives in new files under
`linux/` and `docs/`.

---

## 1. Dependencies come from the distro, not Homebrew

`linux/scripts/common.sh` lists the apt packages by role (build tools, linked
libs, the graphics **build** stack, the ffmpeg plugin, the icon rasteriser, and
the software-render test tools). `ensure_packages [--install]` verifies or
installs them. The distro package manager is the Homebrew analogue; the apt names
are Debian/Ubuntu. On another family (Fedora, Arch) only the package **names**
change — translate them and the rest of the pipeline is identical.

---

## 2. Engine build

Encoded in `linux/scripts/build-engine.sh`.

### 2.1 Do not run `make makelibs` — provide distro static libs instead
Exactly the macOS situation, for the same reason. `FTE_TARGET=SDL2` statically
links a handful of image/audio libraries from `engine/libs-<arch>/*.a`
(`engine/Makefile` line ~726: `IMAGELDFLAGS := libs-$(ARCH)/libpng.a …`). Rather
than build vendored copies with `makelibs`, we symlink the distro's static
archives (`libpng.a`, `libjpeg.a`, `libvorbisfile.a`, `libvorbis.a`, `libogg.a`,
shipped in the `-dev` packages) into that directory. `<arch>` is
`cc -dumpmachine` (`aarch64-linux-gnu`), which matches the Makefile's `$(ARCH)`.

**Drift.** If a distro stops shipping one of these `.a` files, `find_static`
fails and names the missing archive; install the `-dev`/`-static` variant, or
switch that lib to dynamic (drop its `-DLIB…_STATIC` and add it to the bundle
set). The build already links the rest dynamically and bundles them (§4).

### 2.2 `FTE_TARGET=SDL2`, `m-rel`
The SDL path (SDL2 video/audio/input) is the maintained cross-platform target;
`m-rel` defines **both** `-DGLQUAKE` and `-DVKQUAKE`, producing one binary with
OpenGL *and* Vulkan, switchable at runtime via `vid_renderer gl|vk`. The test
suite checks for the real `VK_Init`/`GLBE_Init` symbols (ELF, no leading
underscore), not the help string, so a Vulkan-stubbed `gl-rel` would fail.

### 2.3 Stripping is native
The Makefile's default `strip --strip-unneeded` is GNU syntax and works on Linux,
so — unlike macOS — we do **not** pass `STRIP=SKIP`. Stripping keeps the AppImage
small.

---

## 3. The graphics stack is the host's (never bundled)

macOS bundles MoltenVK because the OS has no Vulkan. **Linux is the opposite of
macOS and the same as the Windows-on-ARM stance:** OpenGL, the Vulkan *loader*
(`libvulkan.so.1`) and its ICDs, X11/Wayland, and libdrm are all part of the
user's **GPU driver + display stack** and must come from the host to match their
kernel and hardware. Bundling them would pin a Mesa/driver version into the
AppImage and break on other systems.

This is enforced by the **ALLOWLIST** in `common.sh`: the self-containment audit
(§4) permits exactly these library families to resolve outside the AppImage;
anything else that escapes is a packaging bug. The AppRun launcher likewise does
**not** export `LD_LIBRARY_PATH`, so a bundled `libstdc++`/`libz` can never shadow
the ones the host driver was built against (the classic AppImage rendering-break).

---

## 4. Self-contained bundling (linuxdeploy + appimagetool)

`linux/scripts/make-appdir.sh` (engine) and `build-plugins.sh` (plugins).

- **`linuxdeploy`** is the `dylibbundler` analogue: it copies the engine's linked
  dependency closure into `usr/lib/`, sets rpath to `$ORIGIN/../lib`, and lays out
  the AppDir. It honours the AppImage excludelist, so it will not bundle the
  driver/ABI libraries on the ALLOWLIST.
- **`appimagetool`** squashes the finished AppDir into `FTEQW-<cpu>.AppImage`.
- Both tools are themselves AppImages; `common.sh` fetches the `aarch64` builds on
  demand and runs them with `APPIMAGE_EXTRACT_AND_RUN=1` so **no FUSE** is needed
  in a VM or on CI.

**The plugin closure linuxdeploy can't see.** The ffmpeg plugin (`fteplug_ffmpeg.so`)
is loaded with `dlopen`, not linked by the main executable, so linuxdeploy doesn't
scan it. `bundle_so_deps` (in `common.sh`) walks the plugin's `ldd` output, copies
every non-ALLOWLIST dependency (the `libav*`/`libsw*` family and their transitive
deps) into `usr/lib/`, and rpaths them — the direct analogue of macOS co-locating
`dlopen`'d libraries by hand.

- **Audit.** `audit_selfcontained` fails the build if any dependency of the engine
  or a bundled `.so` resolves outside the AppDir and is not on the ALLOWLIST. This
  is the positive-space inverse of macOS's "no `/opt/homebrew` refs" check.
  `50-appimage.sh` re-runs it statically and then launches the packed AppImage
  (via extract-and-run) to prove it executes.

**Drift.** New/renamed **linked** deps are handled automatically by linuxdeploy.
New **`dlopen`'d** deps are the risk (a new plugin, or SDL/ffmpeg growing a runtime
`dlopen`): `bundle_so_deps` covers plugins we build; anything else shows up as a
non-ALLOWLIST escape in the audit — bundle it the same way, or, if it is genuinely
a driver/system lib, add its prefix to the ALLOWLIST with a comment.

---

## 5. Plugins are simpler than on macOS

`linux/scripts/build-plugins.sh`. Linux is FTE's native plugin platform:

- The default `PLUG_CFLAGS`/`PLUG_LDFLAGS` work as-is — none of the macOS
  `-undefined,dynamic_lookup` / dropped-GNU-flag handling.
- There is **no codesigning**, so upstream's default `EMBEDMETA` (a trailing-zip
  the plugin manager reads for titles/descriptions) is left **on** and needs no
  reordering. The plugin ships with metadata already embedded; `40-plugins.sh`
  reads it back with `unzip -p`.

Plugins are installed into `usr/bin/` alongside `fteqw-engine` so FTE finds them
by name, with their rpath pointed one level up at the bundled `usr/lib/`.

---

## 6. AppRun launcher

`linux/scripts/AppRun` (installed as `<AppDir>/AppRun`, the AppImage entrypoint).
Machine-independent — every path resolves at runtime. It auto-loads the ffmpeg +
qi plugins (backing off if the user is already driving `plug_load`, or passes
`-noplugins`), and honours `FTEQW_DATA` (→ `-basedir`) and the engine's own
`FTEHOME`/XDG data dir. It deliberately does **not** force a renderer (the engine
defaults to OpenGL; choose Vulkan per-run with `+set vid_renderer vk`) and does
**not** set `LD_LIBRARY_PATH` (see §3).

---

## 7. GPU-testing tiers (honest coverage)

Neither a headless CI runner nor a Parallels VM has a **real** GPU. But Linux — 
unlike macOS/Windows — ships **software rasterisers**, which lets us verify more
than the other ports can without hardware:

- **Tier 1 — always automated (green in the VM and on CI):** build, both renderers
  compiled in, engine runs headless, plugin build/bundle/metadata, and full static
  + runtime self-containment (`audit_selfcontained` + launching the AppImage).
- **Tier 1.5 — automated *because Linux has software renderers*:** the Vulkan
  **loader + ICD** path is exercised for real via **lavapipe** (`vulkaninfo`
  enumerates a software device — `30-renderers.sh`). With Quake data present, full
  OpenGL/Vulkan **renderer init** runs headless under **Xvfb + llvmpipe/lavapipe**.
- **Tier 2 — real Adreno/AMD/Intel/NVIDIA GPU:** actual hardware rendering and
  performance. The tests are written but gated on data + a display; on a real
  machine with game data they run, otherwise they skip. Never implied by a VM/CI
  pass.

`30-renderers.sh` keeps engine renderer-init gated on `HAVE_DATA` (as macOS does)
because the engine needs a gamedir to reach video bring-up; the data-independent
confidence comes from the lavapipe loader check and the AppImage run test. If a
future engine reaches video without game data, promote the software-render init
tests to run unconditionally.

---

## 8. Why the tests exist

Same philosophy as the macOS port: the value is a **fast path to detect and fix
breakage** when upstream FTEQW, a distro library, or the AppImage tooling moves.
Each moving part above has a test in `linux/tests/`; a red test names the broken
assumption and this document explains how to restore it. When you add a
workaround, add the test that guards it.
