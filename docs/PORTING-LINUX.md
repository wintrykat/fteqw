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

### 2.4 FreeType headers via `CPATH` (the same gap macOS papers over)
`gl_font.c` does `#include <ft2build.h>`, but the Makefile never adds FreeType's
include dir. When `-DLINK_FREETYPE` is in play (it is, via `FTE_CONFIG_EXTRA`), the
`LINK_FREETYPE` branch (`engine/Makefile` ~line 1053) **blanks** `FREETYPE_CFLAGS`
and instead expects `ft2build.h` to sit in `libs-<arch>/` — a layout produced only
by `make makelibs`, which we skip (§2.1). The distro ships those headers in a
non-default dir (`…/freetype2`) that nothing on the default search path covers, so
the compile dies with `ft2build.h: No such file or directory`.

macOS hits the identical gap and solves it by exporting `CPATH`
(`macos/scripts/common.sh:setup_build_env`). `build-engine.sh` mirrors that: it
derives the FreeType include dir from `pkg-config --cflags-only-I freetype2`
(never hardcoded) and prepends it to `CPATH`, so `#include <ft2build.h>` resolves
with **no** Makefile edit. Opus, Vulkan and SDL2 headers are already added by the
Makefile's own pkg-config calls — FreeType is the only one it drops.

**Drift.** If FreeType headers move or the package is missing, `build-engine.sh`
dies with a clear message (`FreeType headers not found via pkg-config`). The
toolchain test (`10-toolchain.sh`) asserts the dir is discoverable so a red test
points straight here; the engine build itself (`20-engine.sh`) is the end-to-end
guard — it cannot produce a binary if this breaks.

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
  the AppDir.
- **The AppImage excludelist ≠ our ALLOWLIST — mind the gap.** linuxdeploy applies
  the upstream *AppImage excludelist*, which is a **superset** of our ALLOWLIST: on
  top of the driver/ABI stack it also refuses to bundle several "assumed present"
  base libraries the engine links — `libz`, `libfreetype`, `libasound`, `libexpat`,
  `libgpg-error`. Our self-containment policy (§3) only exempts the GPU/display
  driver + glibc ABI, so those escapees must be bundled. Worse, because the engine
  directly needs `libz`/`libfreetype`, the leftover **host** `libfreetype` then
  pulls host copies of libs we *did* bundle (`libpng16`, `libbz2`, `libbrotli*`)
  right back in. `make-appdir.sh` closes this by running `bundle_so_deps` on the
  engine after linuxdeploy — copying the excluded remainder into `usr/lib/` with an
  `$ORIGIN` rpath (the same helper `build-plugins.sh` uses for the ffmpeg closure).
  Once done, the whole transitive chain resolves inside the AppDir. The
  renderer-init test (`30-renderers.sh`, lavapipe) is the guard that a bundled
  low-level lib does not shadow the host GL/Vulkan driver.
- **Not every escapee is ours to bundle — host-stack transitive deps.** Four libs
  (`libbsd`, `libmd`, `libexpat`, `libffi`) are pulled in **only** through the
  host graphics/display stack we deliberately keep host-provided (§3):
  `libbsd`/`libmd` via host `libX11`/`libXdmcp` and `libGL`; `libexpat` via Mesa's
  `libGLX_mesa`; `libffi` via host `libwayland`. No **bundled** library needs them,
  so they belong to the driver/display closure, not ours — and on any host able to
  render they are guaranteed present. They are therefore on the **ALLOWLIST**
  (which already enumerates that stack — `libXau`/`libXdmcp` were there; these are
  the members it missed), so `bundle_so_deps` skips them and the audit accepts
  them. This split is the crux: `bundle_so_deps` bundles the engine's *own*
  excluded deps (`libz`, `libfreetype`, `libasound`, `libgpg-error`); the ALLOWLIST
  covers deps reachable *only* via the host stack.
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

### 5.1 FFmpeg < 7.1 compatibility shim (no engine edit)
Upstream `plugins/avplug/avencode.c` calls `avcodec_get_supported_config(…,
AV_CODEC_CONFIG_SAMPLE_FORMAT, …)` **unconditionally** — an API added in
**libavcodec 61.13.100 (FFmpeg 7.1)**. macOS builds only because Homebrew ships
ffmpeg 7.x; our reference host, **Ubuntu 24.04, ships libavcodec 60 (FFmpeg 6.1)**,
so the plugin fails to compile (`AV_CODEC_CONFIG_SAMPLE_FORMAT undeclared`).

To keep the fork thin (the Linux port's promise is **zero** engine/plugin source
edits), we do **not** patch `avencode.c`. Instead `linux/compat/ffmpeg6-compat.h`
supplies the enum plus a faithful pre-7.1 implementation (the codec's static
`sample_fmts` list — exactly what the new call returns for that selector), and
`build-plugins.sh` force-includes it into the ffmpeg compile via the plugin rule's
`$(CFLAGS)` hook (`export CFLAGS="… -include …/ffmpeg6-compat.h"`). The header is
guarded on `LIBAVCODEC_VERSION_INT` and is **inert on FFmpeg ≥ 7.1**, so it is
safe to leave in place once distros catch up — nothing to retire. `40-plugins.sh`
(builds + loads the ffmpeg plugin) is the guard; a red line there after an FFmpeg
bump points back to this shim.

> This is the one place the Linux port needs a compatibility workaround. It lives
> entirely under `linux/` — no `engine/` or `plugins/` file changes — so the
> "zero engine source edits" invariant still holds and `ATTRIBUTION.md` needs no
> new entry (it records engine/Makefile edits; this is neither).

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

**Harness reliability (learned the hard way when the suite first ran with data +
tools present).** Three things the software-render tests depend on:
- `run_engine_video` routes its env through **`env …`**, not a shell
  assignment prefix. A `VK_ICD_FILENAMES=…` token produced by `${LVP_ICD:+…}`
  expansion is *not* honoured as an assignment (the shell tries to exec it), so the
  inline form silently exec-failed the moment a lavapipe ICD was detected.
- It **polls for the `renderer initialized` marker** (shared by the GL and VK
  lines) up to a generous cap instead of a fixed short sleep — a cold llvmpipe /
  lavapipe pipeline build in a fresh VM can take a few seconds; a warm run returns
  in ~1s.
- `FTEQW_DATA` is **exported** (assert.sh), because the packed AppImage's `AppRun`
  only adds `-basedir` when it sees that variable in its environment — the
  50-appimage run test drives the engine through `AppRun`, not directly.

---

## 8. Why the tests exist

Same philosophy as the macOS port: the value is a **fast path to detect and fix
breakage** when upstream FTEQW, a distro library, or the AppImage tooling moves.
Each moving part above has a test in `linux/tests/`; a red test names the broken
assumption and this document explains how to restore it. When you add a
workaround, add the test that guards it.
