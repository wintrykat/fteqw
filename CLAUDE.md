# CLAUDE.md — project guide for Claude Code

## What this repo is
A thin, native **arm64** fork of [FTEQW](https://github.com/fte-team/fteqw) that
packages the engine per-platform. **macOS/Apple Silicon is done and shipping**
(see `macos/`, `docs/PORTING.md`). **Windows-on-ARM is the current task** — the
full implementation brief is `docs/WINDOWS-ARM-PORT.md`; read it first.

Everything is **GPL-2.0** (inherited from FTEQW / Quake). The engine source is
changed by exactly **one line** (`engine/vk/vk_init.c`); keep it that way.

## Non-negotiable conventions (both platforms)
1. **Keep the fork thin.** Prefer build-time overrides / new files under the
   platform dir (`macos/`, `windows/`) over editing `engine/`. Any engine or
   Makefile edit MUST be recorded in `ATTRIBUTION.md` (GPL §2a) and explained in
   the relevant `docs/PORTING*.md`.
2. **Every workaround gets a test.** No undocumented, untested workaround — it
   will silently rot. Add/adjust the test that would go red if it breaks.
3. **Self-contained output.** The shipped artifact must run with no dependency on
   the build package manager (Homebrew / MSYS2). Prove it with a
   static + runtime dependency audit in the tests.
4. **No game data, ever.** Never commit id Software content (`pak0.pak`, maps…).
5. **Honest docs.** Say plainly what is and isn't verified — especially GPU
   coverage on Windows-on-ARM (see below).
6. **Before calling anything done:** the platform's `build-all` and `tests/run`
   must both pass.

## Mirror the macOS precedent
The macOS layer is the template for the Windows layer:
- `macos/scripts/{common,build-engine,make-app,build-plugins,build-all}.sh` +
  `launcher.sh`
- `macos/tests/{assert,run,10-toolchain,20-engine,30-renderers,40-plugins,50-bundle}.sh`
- `docs/PORTING.md` (the "why + how to reconstruct" for each workaround)

Reproduce this structure and discipline under `windows/`.

## Environment
- **macOS:** Homebrew (`/opt/homebrew`), clang, `FTE_TARGET=SDL2`, merged
  `m-rel` (GL+Vulkan), Vulkan via **bundled MoltenVK**. Arch triple:
  `clang -dumpmachine` = `arm64-apple-darwin*`.
- **Windows-on-ARM:** MSYS2 **`CLANGARM64`** (pacman) is the recommended
  toolchain (Homebrew analog); triple `aarch64-w64-mingw32`. Default renderer
  **D3D11**; **Vulkan** for real Adreno hardware and is provided by the GPU
  **driver** (do NOT bundle a Vulkan runtime — there is no MoltenVK equivalent to
  ship). Install Git for Windows so the Bash tool works.

## Windows-on-ARM: start here
A host-side recon is recorded in `docs/WINDOWS-ARM-PORT.md` §0.5. Key points:
guest is arm64 Win11 + Git + internet; **add a `win_arm64` Makefile target**
(none exists — mirror `win64` with `aarch64-w64-mingw32`) as the first workaround;
a detached MSYS2 install may be in progress — check `C:\msys2probe.log` and
`C:\msys64\clangarm64\bin\clang.exe -dumpmachine` before reinstalling; and run the
build in a **native in-guest shell**, never via host `prlctl exec` (it hangs under
load).

## Windows-on-ARM: the GPU-testing caveat (critical)
Target is **real devices**, but neither the Parallels VM (caps at DirectX 11.1 /
OpenGL 3.3, **no Vulkan**) nor GitHub `windows-11-arm` runners have a **real
GPU**. So:
- **Tier 1** (build, packaging, self-containment, engine-run, D3D11 on a virtual
  GPU) → automate; must be green in the VM and on CI.
- **Tier 2** (real D3D11/Vulkan on Adreno) → write the tests but **gate them on a
  real GPU**; they skip in the VM/CI.
- **Tier 3** → a manual `docs/HARDWARE-TESTING.md` checklist for a device owner.
Never imply the VM validates Vulkan or real-hardware rendering. Details in
`docs/WINDOWS-ARM-PORT.md` §5.

## House rules
- Scripts: `set -euo pipefail`; watch the `pipefail` + `grep -q` SIGPIPE trap on
  large producers (`nm`, `dumpbin`) — use `grep -c … || true`.
- No machine-specific hardcoded paths; derive from the package-manager prefix and
  the repo location; honor `FTEQW_APP` / `FTEQW_DATA` (and Windows equivalents).
- After finishing a unit of work, run the tests and report what's verified vs
  what still needs real hardware.
