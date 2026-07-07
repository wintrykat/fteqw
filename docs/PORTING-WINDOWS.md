# Porting notes — FTEQW on Windows-on-ARM (aarch64)

This document records every workaround this fork applies to build, package, and
test FTEQW natively for **Windows-on-ARM (Qualcomm Snapdragon / Copilot+ PCs,
Surface Pro X, …)**, **why** each exists, and **how to reconstruct or retire it**
as upstream FTEQW, MSYS2 libraries, or the LLVM toolchain change. It is the
troubleshooting reference the test suite (`windows/tests/`) backs up: when
something breaks, a failing test should point you at the section here.

Like the macOS port, this is deliberately a **thin** fork: the Windows-on-ARM
work modifies **zero** engine source and **zero** Makefile lines. Everything is
build procedure, packaging, and tooling in new files under `windows/` and
`docs/`, driven entirely by command-line overrides — so rebasing on upstream
stays trivial. (The only upstream source change in the whole fork is the single
`<limits.h>` line from the macOS port, which is platform-agnostic and already
present; Vulkan needs it here too. See `docs/PORTING.md` §1 and `ATTRIBUTION.md`.)

> Scope: `FTE_TARGET=win64` + overrides, native Win32 renderers (D3D11 default,
> plus Vulkan, OpenGL, D3D9), aarch64, Windows 11 ARM. Toolchain: MSYS2
> **CLANGARM64** (clang, triple `aarch64-w64-windows-gnu`).
>
> **GPU-testing caveat (critical):** neither the Parallels VM nor GitHub's
> `windows-11-arm` runners have a **real GPU** — the VM caps at DirectX 11.1 /
> OpenGL 3.3 with **no Vulkan**. So real D3D11/Vulkan-on-Adreno rendering is
> **not** validated by CI/VM; it is covered by hardware-gated Tier-2 tests and the
> manual Tier-3 checklist (`docs/HARDWARE-TESTING.md`). Until a device run is
> recorded, those axes are **"unverified", not "passing"**.

---

## 0. The build in one line

The single source of truth for the build recipe is `fte_make()` in
`windows/scripts/common.sh`. The engine is:

```sh
make -C engine m-rel FTE_TARGET=win64 \
     "CC=clang -I<CLANGARM64>/include/opus" "CXX=clang++ -I<CLANGARM64>/include/opus" \
     AR=llvm-ar RANLIB=llvm-ranlib WINDRES=llvm-windres \
     STRIP=SKIP PKGCONFIG=pkgconf TMP=<winform> TEMP=<winform> -j<N>
```

Each override is explained below.

---

## 1. Why `FTE_TARGET=win64` (not a new `win_arm64` Makefile target)

**Context.** FTE's Makefile has `win32`/`win64` (x86) and `linux_arm64`, but **no
arm64 *Windows*** target. The obvious move is a new `win_arm64` block.

**What we do instead.** We reuse `FTE_TARGET=win64` and override the toolchain on
the command line — **zero Makefile edits**. This works because:

- `win_arm64` would be a *new* code path to maintain; `win64` already selects
  exactly the native-Win32 renderer path we want (`gl_vidnt.o`, `fs_win32.o`,
  `net_ssl_winsspi.o`, and the D3D9/D3D11/GL/Vulkan objects — Makefile ~line 1510,
  gated on `findstring win`).
- The x86-specific CC override that `win64` would normally apply
  (Makefile ~line 218: reset `CC` to `x86_64-w64-mingw32-gcc`) is **skipped**
  because (a) clang's version string contains `mingw`, satisfying the guard at
  line 219, and (b) `x86_64-w64-mingw32-gcc` isn't installed anyway.
- `BITS=64` from `win64` only affects **filenames** (`fteqw64.exe`,
  `fteplug_*_x64.dll`) and directory names — **not codegen**. clang targets
  aarch64, so the emitted PE is genuinely ARM64 (`IMAGE_FILE_MACHINE_ARM64`,
  `0xAA64`). Physically, clang-targeting-aarch64 cannot emit x86.

**The one wart:** the `64`/`_x64` labels are misnomers on arm64. We strip them at
packaging time (→ `fteqw.exe`, `fteplug_<name>.dll`), the same way the macOS port
renames its binary to `fteqw-engine`.

**Test that guards it.** `20-engine.sh` and `50-package.sh` assert the shipped PE
is `IMAGE_FILE_MACHINE_ARM64`. If a future change slipped in x86 codegen (or a
real `win_arm64` target diverged), that assertion goes red.

**How to retire.** If upstream adds a first-class `win_arm64`/aarch64-windows
target, switch `FTE_TARGET` and drop the rename — but keep the 0xAA64 assertion.

---

## 2. `opus.h` not found → add the opus include to `CC`

**Symptom.** `client/snd_dma.c:390:10: fatal error: 'opus.h' file not found`.

**Cause.** `snd_dma.c` does `#include "opus.h"` (bare), and the Makefile hardcodes
`-I/usr/include/opus` (line 1029). Our Opus lives in the CLANGARM64 prefix at
`.../include/opus/opus.h`, which that path never reaches.

**Fix.** Append `-I<CLANGARM64>/include/opus` (Windows-form path) to `CC`/`CXX`.
The Makefile already splits `CC` into compiler + flags (`$(firstword $(CC))` /
`$(wordlist 2,99,$(CC))`), so a multi-word `CC` is idiomatic. We tried `CPATH`
first — it fails because native clang won't accept MSYS `/c/…` paths and `:` in
`CPATH` collides with drive letters.

**How to retire.** If upstream stops hardcoding `-I/usr/include/opus` (or MSYS2
moves `opus.h` to the include root), drop the `-I`.

---

## 3. `windres` "Unable to create temp file" → pass `TMP`/`TEMP` as make vars

**Symptom.** On a clean build, `resources.o` fails: `Unable to create temp file:
No such file or directory` (Makefile:1991, `llvm-windres` on `winquake.rc`).

**Cause.** MSYS `/bin/sh` (make's recipe shell) **drops inherited `TMP`/`TEMP`** —
inside a recipe they are empty. `llvm-windres` shells out to clang to preprocess
the `.rc`, and with no temp dir the temp-file creation fails with ENOENT. It is
**not** a parallel-build race and **not** a missing output dir (both were ruled
out); a plain `export TMP=…` does **not** survive into the recipe.

**Fix.** Pass `TMP=<winform>` and `TEMP=<winform>` as **command-line make
variables** (those *are* injected into every recipe's environment). The path is
derived from the environment's `TEMP` via `cygpath -m` — no hardcoding.

**How to retire.** If MSYS2's `sh`/make stops stripping `TMP`/`TEMP`, or
`llvm-windres` gains an in-memory preprocessor, this override becomes a no-op and
can be removed.

---

## 4. Toolchain variable mapping

Plain overrides, no surprises: `AR=llvm-ar`, `RANLIB=llvm-ranlib`,
`WINDRES=llvm-windres`, `PKGCONFIG=pkgconf` (the arch-prefixed
`aarch64-…-pkg-config` the Makefile guesses does not exist), and `STRIP=SKIP` —
the upstream escape hatch, which also keeps symbols for the Tier-1
renderer-presence checks (`llvm-nm` for `D3D11_Draw_Init` / `VK_Init`).

---

## 5. Plugins: `--support-old-code` and the ffmpeg download

Two extra overrides for `plugins-rel` (see `windows/scripts/build-plugins.sh`):

- **`PLUG_LDFLAGS=`** — the `win64` default is
  `-Wl,--support-old-code -static-libgcc` (plugins/Makefile line 14). `lld`
  rejects `--support-old-code` (`unknown argument`). Plugins are `-shared` DLLs
  that export via `plugin.def` and resolve engine symbols through the plugin API
  at load, so they need none of it — empty is correct.
- **`AV_BASE=`** — for any `win` target the plugin Makefile sets `AV_BASE` to a
  download dir and **fetches prebuilt x86_64 zeranoe ffmpeg-4.0 from archive.org**
  (wrong architecture, ancient). Blanking it makes the ffmpeg plugin link our
  CLANGARM64 (arm64) ffmpeg via `-lavcodec -lavformat -lavutil -lswscale`
  (plugins/Makefile line 157). Same fix the macOS port uses.

**Metadata.** FTE's `EMBEDMETA` trailing-zip step works **unchanged** on PE
(loaders ignore trailing data; no signature to invalidate) — so, unlike macOS,
there is no build-order dance. The manifest is deflated; read it back with
`unzip -p <dll>` (the `40-plugins.sh` test does exactly this).

---

## 6. Self-contained packaging

Windows resolves DLLs next to the `.exe` first, so packaging is just: copy the
non-system DLL closure beside `fteqw.exe`. `make-package.sh`:

1. Renames `fteqw64.exe` → `fteqw.exe`, `fteplug_*_x64.dll` → `fteplug_*.dll`.
2. Unions the recursive closure (`ntldd -R`) of the exe **and every plugin** —
   the ffmpeg plugin drags in the whole codec chain (avcodec/avformat/avutil/
   swscale + dav1d, aom, gnutls, …), ~100 DLLs, which is why the ZIP is ~45 MB.
   Only deps resolving under `C:\msys64` are copied; OS DLLs (`kernel32`,
   `d3d11`, `dxgi`, `vulkan-1`, …) stay unbundled.
3. **Audits** self-containment: re-resolves every PE's closure with the MSYS2 bin
   dirs removed from `PATH` and `cwd` = the package. Zero dependencies may resolve
   under `msys64`. This is the Windows analog of the macOS `otool`/`lsof` audit
   and is asserted by `50-package.sh`.

We deliberately **do not bundle a Vulkan runtime** (no MoltenVK equivalent to
ship): on real hardware the Adreno driver provides `vulkan-1.dll`. It is simply
absent in the VM — expected.

---

## 7. Installer & signing

`make-installer.sh` + `windows/installer/fteqw.iss` build a native-arm64 Inno
Setup installer (skipped gracefully if `ISCC` isn't installed). The portable ZIP
from `build-all.sh` is the always-ship artifact. Installers are **unsigned** —
fine for testing, but unsigned installers trip **SmartScreen**; sign with an
EV/OV Authenticode cert for real distribution. Not a blocker.
