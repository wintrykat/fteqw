# Windows-on-ARM (arm64) port — implementation brief

Companion to the completed macOS/Apple-Silicon port. Target: **a general
Windows-on-ARM release for real devices** (Qualcomm Snapdragon / Copilot+ PCs,
Surface Pro X, etc.) — *not* VM-only. This brief is written to be executed by
**Claude Code running inside the Windows 11 ARM VM** (see `CLAUDE.md`), because
the discovery phase is iterative and needs a native shell in the guest.

It mirrors the macOS work (`docs/PORTING.md`, `macos/scripts/`, `macos/tests/`)
in a parallel `windows/` tree, with the same discipline: keep the fork thin,
**every workaround gets a test**, self-contained packaging, honest docs.

---

## 0. The fidelity problem (read first)

Neither the Parallels VM nor GitHub's `windows-11-arm` runners have a **real
GPU**: Parallels caps the guest at **DirectX 11.1 / OpenGL 3.3, no Vulkan**, and
the CI runners are virtualized. So graphics on **real** Snapdragon/Adreno
hardware — especially **Vulkan** and any Adreno-specific behaviour — **cannot be
validated here**. We handle this honestly with three test tiers (§5), not by
pretending the VM covers it. Set expectations accordingly in `README`/docs.

---

## 0.5 Environment recon (host-side `prlctl`, verified)

Checked from the Mac host before handoff:
- Guest is **native arm64 Windows 11** (build 26200); **Git for Windows** is
  installed; internet works.
- **Getting the repo into the guest:** use `git clone` after pushing. The
  Parallels `\\Mac\` share exposes only selected home subfolders, not the repo's
  full path, so don't rely on it.
- **Install in-guest:** Node 22+, MSYS2 + the `CLANGARM64` group, and Claude Code.
  (`winget` was not visible in the `prlctl exec` context.)
- **Build in the guest, not via host `prlctl exec`.** Heavy guest load (the MSYS2
  install alone did it) starves the Parallels Tools agent and makes host `exec`
  calls hang indefinitely. `prlctl` is fine for light checks only — the actual
  build/test must run in a native in-guest shell (this is why Claude Code in the
  guest is the path, not host automation).
- A detached MSYS2 install was kicked off during recon; before redoing it, check
  `C:\msys2probe.log` and `C:\msys64\clangarm64\bin\clang.exe -dumpmachine`
  (expected: `aarch64-w64-mingw32`).

---

## 1. Renderers

Real WoA devices expose **D3D11, D3D12, and Vulkan** (Adreno driver). FTE has
D3D9, D3D11, GL, and Vulkan backends. Strategy:

- **Default: D3D11.** Universal on WoA (works in the VM *and* on real hardware),
  the analog of MoltenVK-being-the-Mac-default. FTE `vid_renderer d3d11`.
- **Ship Vulkan too** for real Adreno hardware. Unlike macOS, **do not bundle a
  Vulkan runtime** — on Windows the Vulkan ICD is provided by the GPU driver.
  Vulkan simply won't be present in the VM; that's expected.
- **OpenGL:** WoA's native GL is weak. Treat GL as best-effort/fallback; it may
  need ANGLE (GL-over-D3D) to be useful on real hardware. Decide during
  discovery; do not let GL block the D3D11 default.
- No D3D12 backend exists in FTE and none is needed (D3D11 suffices).

---

## 2. Toolchain

Two viable native-arm64 Windows toolchains:

- **MSYS2 `CLANGARM64`** *(recommended)* — pacman-managed native arm64 clang +
  libraries. It is the closest analog to our Homebrew-on-Mac approach and lets us
  reuse FTE's `make` build. Packages: `mingw-w64-clang-aarch64-{clang,SDL2,
  libpng,libjpeg-turbo,libogg,libvorbis,freetype,opus,speex,ffmpeg,dylibbundler?}`.
  The compiler targets `aarch64-w64-mingw32`.
- **MSVC ARM64** (VS 2022/2026 Build Tools, ARM64 target) — better Windows SDK /
  D3D11 integration and FTE has an MSVC project (`engine/README.MSVC`), but
  dependencies are manual (no package manager). Keep as a fallback if the
  D3D11/Vulkan headers or the ARM64 target fight the mingw path.

**Confirmed by recon:** FTE's Makefile `win` targets assume x86/x64 mingw triples
(`i686-/x86_64-w64-mingw32`); it has `linux_arm64` but **no arm64 *Windows*
target**. So the first concrete workaround is a new **`win_arm64`** block mirroring
the `win64` block with the `aarch64-w64-mingw32` toolchain (MSYS2 CLANGARM64's
`clang --target=aarch64-w64-mingw32`), or extending the `msvc*` path to ARM64.
Drive the native `CLANGARM64` clang with the right flags where possible,
analogous to the macOS `FTE_TARGET=SDL2` + command-line overrides we used. Prefer
command-line/Make-variable overrides over editing the Makefile; if a source or
Makefile edit is unavoidable, record it in `ATTRIBUTION.md` and `PORTING.md`.

The one upstream source change from the macOS port (`<limits.h>` in
`vk_init.c`) is platform-agnostic and already present — Vulkan will need it here
too.

---

## 3. Self-contained packaging (easier than macOS)

Windows resolves DLLs next to the `.exe` first, so **no `install_name_tool` /
rpath surgery and no code-signing-vs-trailing-data conflict**. Steps:

1. Build `fteqw.exe` (+ `fteplug_ffmpeg.dll`, `fteplug_qi.dll`).
2. Enumerate the DLL closure — `ntldd -R fteqw.exe` (MSYS2) or `dumpbin
   /dependents`. Copy every **non-system** DLL next to the exe (SDL2, and its
   SDL3 backend if MSYS2 ships sdl2-compat; libpng, freetype, ffmpeg
   `avcodec/avformat/avutil/swscale`, opus, speex, etc.). System DLLs
   (`kernel32`, `d3d11`, `dxgi`, `vulkan-1` …) stay unbundled — they're the OS's.
3. Plugin metadata: FTE's `EMBEDMETA` trailing-zip trick works unchanged on PE
   (loaders ignore trailing data), and there's **no signature to invalidate**, so
   the macOS ordering headache disappears — build the plugin, copy deps, done.

**Installer options** (produce at least the first):
- **Portable ZIP** — the self-contained folder. Minimal, always ship this.
- **Inno Setup** (`.iss` → signed `.exe` installer) — recommended installable.
- **MSIX** — Store-style signed package; more ceremony (manifest + signing).

**Signing:** Authenticode is the Windows analog of the Mac ad-hoc signature but
matters more — unsigned installers trip **SmartScreen**. Unsigned is fine for
testing; for real distribution, an EV/OV code-signing cert is needed. Flag this;
don't block on it.

---

## 4. `windows/` layout (mirror of `macos/`)

```
windows/
  scripts/
    common.ps1  (or common.sh for MSYS2 bash)   # shared config/deps
    build-engine.{ps1,sh}                        # native arm64 fteqw.exe
    make-package.{ps1,sh}                        # self-contained folder + DLL closure
    build-plugins.{ps1,sh}                       # ffmpeg + qi DLLs
    make-installer.{ps1,sh}                      # Inno Setup / MSIX
    build-all.{ps1,sh}
  tests/
    run.{ps1,sh}  assert.{ps1,sh}  10-…  20-…  30-…  40-…  50-…
  installer/
    fteqw.iss                                    # Inno Setup script
```

Pick PowerShell **or** MSYS2 bash and be consistent. MSYS2 bash lets the test
logic port almost verbatim from `macos/tests/` (swap `otool`→`ntldd`/`dumpbin`,
`nm`→`llvm-nm`, `lsof`→`listdlls`/Process API, `codesign`→`signtool`).

---

## 5. Testing strategy — three tiers (this is the heart of the real-device target)

Because the VM/CI have no real GPU, "same testing assurance" is achieved by
being explicit about *what each environment can prove* and giving the
GPU-dependent parts a real path to closure.

### Tier 1 — Automated, runs in VM **and** on `windows-11-arm` CI
Equal assurance to the macOS suite for everything non-GPU. Deterministic.
- `fteqw.exe` PE machine type is **ARM64 (`0xAA64`)** — `dumpbin /headers` /
  `llvm-readobj --file-headers`.
- Both renderers **compiled in** — presence of D3D11 and Vulkan backend symbols
  (`llvm-nm`, or a runtime `vid_renderer`/`plug_list`-style probe if the PE is
  stripped).
- Engine **runs** headless: `fteqw.exe -dedicated +quit` reaches filesystem init
  (with data: "registered version").
- Plugins **build, load, carry metadata** (`+plug_load ffmpeg qi +plug_list`).
- **Self-contained**: DLL-closure audit — every non-system dependency resolves
  *inside* the package dir; nothing loads from MSYS2/`C:\msys64` or elsewhere
  (static `ntldd -R` + runtime loaded-module check).

### Tier 2 — Automated but **hardware-gated** (skips in VM/CI)
Same skip pattern as the macOS renderer tests, but the gate is a **real GPU**.
Runs on a real Snapdragon device or a self-hosted runner with a GPU; the VM's
virtual GPU is explicitly **not** sufficient for the Vulkan checks.
- **D3D11** init + one rendered frame on a real device.
- **Vulkan** init: driver name is the **Adreno** driver, a physical device is
  enumerated, `Vulkan-SDL renderer initialized`.
- A real map render (`+map start`) under each renderer.

### Tier 3 — Manual smoke checklist (device owner)
The honest last mile when no hardware CI exists. A short documented protocol a
person with a Surface/Snapdragon runs and reports via the breakage issue
template: launch, switch D3D11 ↔ Vulkan, load a map, play a mod (e.g. `fortress`
+ a map), confirm ffmpeg/qi load. Put this in `docs/HARDWARE-TESTING.md`.

> **State this plainly in `README`:** automated CI/VM proves build, packaging,
> self-containment, engine-run, and the D3D11 path on a virtual GPU. **Vulkan
> and real-hardware rendering are verified via Tier 2/3 on actual devices**, and
> until a device run is recorded, those axes are "unverified", not "passing".

---

## 6. CI

- **Tier 1** on GitHub `windows-11-arm` (public repo, free). Add a
  `.github/workflows/ci-windows-arm.yml` mirroring the macOS workflow: install
  MSYS2 (`msys2/setup-msys2` action, `CLANGARM64`), `build-all`, `run` tests,
  upload the ZIP artifact. Note: the arm64 runner image is occasionally rough
  (arch-detection quirks have been reported) and has **no GPU** — Tier 2 tests
  self-skip there.
- **Tier 2** needs real hardware: a **self-hosted runner** on a Snapdragon device
  (labelled, e.g., `[self-hosted, windows, arm64, gpu]`), or run manually. Wire
  the job but expect it to sit idle until such a runner exists.

---

## 7. Docs & license (same posture as the macOS port)

- Extend `README.md` with a Windows-on-ARM section (target devices, renderers,
  the honest GPU-testing caveat, quick start).
- Add a `docs/PORTING.md` Windows section (or `docs/PORTING-WINDOWS.md`) recording
  each Windows workaround with why/reconstruction notes.
- Update `ATTRIBUTION.md` if any new upstream source/Makefile files are modified
  (aim for zero, as on macOS).
- `docs/HARDWARE-TESTING.md` for the Tier 3 checklist.
- Everything GPL-2.0, same as the rest of the fork.

---

## 8. Suggested execution order (for the in-guest agent)

1. **Toolchain up:** install MSYS2 + `CLANGARM64` group + the library packages;
   confirm `clang -dumpmachine` → `aarch64-w64-mingw32`.
2. **Engine builds:** get `fteqw.exe` to link natively arm64 with **D3D11**;
   then add Vulkan and GL. Record every workaround as you go.
3. **Runs:** `fteqw.exe -dedicated +quit` clean; then D3D11 window on the VM's
   virtual GPU with real Quake data.
4. **Plugins:** ffmpeg + qi DLLs, loaded and metadata-carrying.
5. **Package:** DLL-closure into a self-contained folder; portable ZIP; then
   Inno Setup installer.
6. **Tests:** port `macos/tests/` to `windows/tests/` as the three tiers; make
   Tier 1 green in the VM and on `windows-11-arm` CI.
7. **Docs:** README section, PORTING notes, HARDWARE-TESTING checklist,
   ATTRIBUTION if needed.

Keep the discipline: thin fork, a test for every workaround, self-contained
output, and honest documentation of what is and isn't verified.
