# Porting notes — FTEQW on Apple Silicon (arm64)

This document records every change and workaround this fork applies on top of
upstream [FTEQW](https://www.fteqw.org/), **why** it exists, and **how to
reconstruct or retire it** when upstream FTEQW, Homebrew libraries, or macOS
change. It is the troubleshooting reference the test suite (`macos/tests/`) is
designed to back up: when something breaks, a failing test should point you at
the section here that explains the moving part.

The actual patch to upstream **source** is a single line (see §1). Everything
else is build procedure, packaging, and tooling that lives in new files
(`macos/`, `docs/`) and does not modify the engine tree — deliberately, to keep
rebasing on upstream trivial.

> Scope: `FTE_TARGET=SDL2`, OpenGL + Vulkan (via MoltenVK), arm64, macOS 11+.
> Verified on macOS 26 (Tahoe), Apple M-series, Homebrew `/opt/homebrew`.

---

## 1. Source change: `<limits.h>` in `engine/vk/vk_init.c`

**Symptom.** With `-DVKQUAKE`, `vk_init.c` fails to compile on clang/macOS:
`use of undeclared identifier 'UINT_MAX'`.

**Cause.** `UINT_MAX` comes from `<limits.h>`. On Linux it arrives transitively
through other headers; the Apple SDK's header graph doesn't pull it in, and
clang is strict.

**Fix.** Add `#include <limits.h>` at the top of the `#ifdef VKQUAKE` block.

**Reconstruction / drift.** If a future upstream already includes `<limits.h>`
(or stops using `UINT_MAX`), this patch becomes a harmless no-op and can be
dropped. If the Vulkan build starts failing on a *different* missing macro,
it's the same class of problem — add the header the symbol belongs to. This is
the only file that differs from upstream; `git diff` should always show exactly
one inserted line.

---

## 2. Engine build

All of this is encoded in `macos/scripts/build-engine.sh`; the notes explain the
individual decisions.

### 2.1 Do not run `make makelibs` — provide Homebrew static libs instead
**Problem.** `make makelibs` builds vendored copies of libpng/jpeg/vorbis/etc.
Its bundled `config.sub` predates Apple Silicon and rejects
`arm64-apple-darwin*` (upstream issue #281), so the whole build stalls there.

**Fix.** Skip `makelibs` entirely. The `FTE_TARGET=SDL2` link line expects
`libs-<arch>/{libpng,libjpeg,libvorbisfile,libvorbis,libogg}.a`; we satisfy that
by symlinking Homebrew's **native arm64** static archives into that directory.
`<arch>` is the compiler target triple (`clang -dumpmachine`, e.g.
`arm64-apple-darwin25.5.0`), which matches the Makefile's `$(ARCH)`.

**Drift.** If Homebrew stops shipping a `.a` for one of these (they occasionally
ship dylib-only), the symlink target vanishes and the link fails with a missing
`libX.a`. Options: install a `+static` variant, build that one lib, or switch
FTE to `dlopen` it at runtime (drop the `-DLIB…_STATIC` define). If upstream
ever fixes `makelibs` for arm64, this whole dance can be replaced by the stock
`make makelibs`.

### 2.2 `FTE_TARGET=SDL2`
The SDL path (SDL video/audio/input) is the maintained cross-platform target.
The Makefile's legacy `macosx` target uses bit-rotted Cocoa/NSOpenGL code and
PowerPC-era cross-compile assumptions — do not use it.

### 2.3 `m-rel` — the merged renderer binary
`m-rel` defines **both** `-DGLQUAKE` and `-DVKQUAKE`, producing one binary with
OpenGL *and* Vulkan, switchable at runtime via `vid_renderer gl|vk`. `gl-rel`
alone stubs out Vulkan behind `#ifdef VKQUAKE` (the binary will contain the
`vid_renderer` help text listing "vk" but `_VK_Init` will be absent — the test
`20-engine.sh` checks for the real symbol, not the help string).

### 2.4 `STRIP=SKIP`
The Makefile's default `STRIP=strip STRIPFLAGS=--strip-unneeded` is GNU syntax;
Apple's `strip` rejects `--strip-unneeded`. `STRIP=SKIP` is upstream's own
escape hatch: it links straight to the final binary and skips the strip step.

### 2.5 `CPATH` for FreeType / Opus / Vulkan headers
The SDL2 target's compile flags don't add FreeType, Opus, or Vulkan include
dirs. Rather than override `BASE_INCLUDES` (which is recursive `=` and would
wipe the engine's own `-I` paths), we prepend them via the compiler's `CPATH`
environment variable — additive, non-invasive.

---

## 3. Vulkan via MoltenVK

macOS has no native Vulkan; MoltenVK translates Vulkan → Metal. FTE's SDL2 path
creates the surface through `SDL_Vulkan_*` and loads the Vulkan library SDL
points it at.

**Key decision: load MoltenVK directly, not through the Vulkan loader.** The
launcher sets `SDL_VULKAN_LIBRARY=<bundle>/libMoltenVK.dylib`. If you instead let
SDL load the full Vulkan **loader** (`libvulkan.dylib`), MoltenVK is a
*portability* driver and the loader (1.3+) will not enumerate it unless the app
requests `VK_KHR_portability_enumeration` and passes the enumerate-portability
bit at instance creation. Pointing SDL straight at MoltenVK sidesteps that
entirely: the engine talks to MoltenVK's `vkGetInstanceProcAddr` directly.

**Drift.** If a future FTE requests portability enumeration itself, the loader
path becomes viable and you could drop the direct-MoltenVK override. If MoltenVK
stops exposing the device (Metal/OS change), `vulkaninfo` is the first probe —
the toolchain test runs it. If SDL3/sdl2-compat changes how
`SDL_VULKAN_LIBRARY` is honoured, the Vulkan renderer test (`30-renderers.sh`)
catches it: look for `Vulkan Driver Name: MoltenVK` in the engine log.

---

## 4. Self-contained bundling

Goal: `FTEQW.app` runs on any Apple Silicon Mac with **no Homebrew**. Encoded in
`macos/scripts/make-app.sh` (engine) and `build-plugins.sh` (plugins).

- **`dylibbundler`** copies the *linked* dependency closure into
  `Contents/Frameworks/`, rewrites install names to `@executable_path/../Frameworks`
  (engine) or `@loader_path/../Frameworks` (plugins), and re-signs. It follows
  `otool -L`, so it catches transitive deps (e.g. `libpng16` via FreeType).

- **Two libraries `dylibbundler` cannot see, because they're `dlopen`'d, not
  linked:**
  - **SDL3.** Homebrew's `sdl2` is the **sdl2-compat** shim, which `dlopen`s
    `libSDL3.dylib` via `@loader_path`. We copy `libSDL3.dylib` into
    `Frameworks/` *next to* the shim so that path resolves. (Verify with
    `otool -l …/libSDL2-2.0.0.dylib | grep -A2 LC_RPATH` and its `libSDL3`
    strings.)
  - **MoltenVK.** `dlopen`'d through the launcher's `SDL_VULKAN_LIBRARY`. Copied
    into `Frameworks/` and pointed at from the launcher.

- **Audit.** After bundling, *no* Mach-O in the app may reference `/opt/homebrew`
  or `/usr/local`. `make-app.sh` fails the build if any do; `50-bundle.sh` checks
  it statically (`otool -L`) and at runtime (`lsof` shows 0 Homebrew dylibs).

**Drift.** New/renamed transitive deps are handled automatically by
`dylibbundler`. New **`dlopen`'d** deps are the risk: if a future SDL/MoltenVK or
a new plugin `dlopen`s something by leaf name, `dylibbundler` won't catch it and
the runtime `lsof` test will show it loading from Homebrew (or the app will fail
on a machine without Homebrew). Fix: co-locate that dylib in `Frameworks/` the
same way we do for SDL3/MoltenVK.

---

## 5. Case-insensitive filesystem: launcher vs engine naming

The default macOS volume is **case-insensitive**, so `FTEQW` (the launcher /
`CFBundleExecutable`) and `fteqw` would be the *same file*. The engine binary is
therefore named **`fteqw-engine`** — distinct beyond case. If you rename either,
keep them differing by more than case, or the launcher will overwrite/rerun
itself in a loop.

---

## 6. Plugins (ffmpeg, qi)

Encoded in `macos/scripts/build-plugins.sh`.

### 6.1 `AV_BASE` (ffmpeg include/lib discovery)
The plugin Makefile defaults `AV_BASE=/usr/include/ffmpeg/` on non-Linux, which
doesn't exist on macOS. We set `AV_BASE=` (empty) and provide Homebrew ffmpeg's
paths via `CPATH` / `LIBRARY_PATH` instead.

### 6.2 Apple-incompatible plugin link flags
`PLUG_CFLAGS`/`PLUG_LDFLAGS` default to GNU-isms clang/Apple `ld` reject:
`-static-libgcc`, `-Bsymbolic`, `-Wl,--no-undefined`, `-Wl,-R`. We override with
`-fPIC -fvisibility=hidden` and, critically, `-Wl,-undefined,dynamic_lookup` —
the macOS way to let a plugin resolve engine symbols at load time.

### 6.3 `EMBEDMETA` ordering (the subtle one)
FTE's `EMBEDMETA` appends a **zip metadata blob after the Mach-O** (a polyglot
the plugin manager reads for titles/descriptions). That trailing data makes
`install_name_tool` *and* `codesign` refuse the file ("`__LINKEDIT` segment does
not cover the end of the file"). So order matters:

1. Build the plugin **without** metadata (`EMBEDMETA=`) → clean Mach-O.
2. `dylibbundler` / `install_name_tool` to fix deps (needs a clean Mach-O).
3. `codesign` (ad-hoc) → sets the signature's *code-limit* at the Mach-O's end.
4. **Append** the metadata → it lands **beyond** the code-limit, so the signature
   stays valid for the code, `dyld` still loads the plugin, and FTE can read the
   description.

`build-plugins.sh` reproduces FTE's exact `EMBEDMETA` zip format (see the
`embed_meta` function; mirror of the `EMBEDMETA` define in `plugins/Makefile`).
`codesign -v --strict` will *report failure* on the finished plugin — that is
expected and harmless (trailing data); the plugin loads because non-hardened
`dlopen` validates only up to the code-limit. The plugin test asserts the
functional truth: it *loads* and its metadata is *readable*.

**Drift.** If upstream changes the `EMBEDMETA` format, update `embed_meta` to
match (or diff a stock-built plugin's trailing zip). If it stops appending
metadata, steps 1 and 4 collapse and you can sign normally.

---

## 7. Launcher (`Contents/MacOS/FTEQW`)

`macos/scripts/launcher.sh`. Machine-independent (all paths resolved at
runtime). It: defaults `-basedir` to `~/Library/Application Support/FTEQW`;
points `SDL_VULKAN_LIBRARY` at the bundled MoltenVK; defaults the renderer to
Vulkan; and auto-loads the ffmpeg + qi plugins. **Every default backs off if the
user supplies the corresponding argument** (explicit `-basedir`, a `vid_renderer`
choice, or a pre-set `SDL_VULKAN_LIBRARY`) — so it never fights an override.

Note: because the launcher injects `+set vid_renderer vk` on a plain launch,
changing the renderer in-menu does not persist across launches. To make GL the
permanent default, launch with `+set vid_renderer gl` or edit the launcher.

---

## 8. Why the tests exist

This is a vibe-coded port: the value isn't a frozen binary, it's a **fast path
to detect and fix breakage** when upstream FTEQW, a Homebrew library, MoltenVK,
or macOS moves. Each moving part above has a corresponding test in
`macos/tests/`. A red test names the broken assumption; this document explains
the assumption and how to restore it. Keep them in sync: when you add a
workaround, add the test that guards it.
