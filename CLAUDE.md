# CLAUDE.md — project guide for Claude Code

## What this repo is
A thin, native **arm64** fork of [FTEQW](https://github.com/fte-team/fteqw) that
packages the engine per-platform. **macOS/Apple Silicon is done and shipping**
(see `macos/`, `docs/PORTING.md`). **Linux/arm64 (AppImage) is a first-class
target** (see `linux/`, `docs/PORTING-LINUX.md`) — scaffolded, pending
verification in an arm64 Ubuntu VM. **Windows-on-ARM is the other in-flight
task** — the full implementation brief is `docs/WINDOWS-ARM-PORT.md`.

Everything is **GPL-2.0** (inherited from FTEQW / Quake). Engine edits are kept
to the minimum — **two** so far: `engine/vk/vk_init.c` (build fix) and
`engine/server/sv_main.c` (dedicated-startup crash fix the behavioural tests
found). Both are recorded in `ATTRIBUTION.md` and being sent upstream; keep the
count as low as possible.

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

Reproduce this structure and discipline under `windows/`. The `linux/` layer
already mirrors it (`linux/scripts/*`, `linux/tests/*`, `docs/PORTING-LINUX.md`).

## Environment
- **macOS:** Homebrew (`/opt/homebrew`), clang, `FTE_TARGET=SDL2`, merged
  `m-rel` (GL+Vulkan), Vulkan via **bundled MoltenVK**. Arch triple:
  `clang -dumpmachine` = `arm64-apple-darwin*`.
- **Linux/arm64:** distro apt (Homebrew analog), `FTE_TARGET=SDL2`, merged
  `m-rel`. Triple `aarch64-linux-gnu`. Packaged as a self-contained `.AppImage`
  via **linuxdeploy + appimagetool** (the `dylibbundler` analog). Vulkan/OpenGL
  come from the **host GPU driver** — do NOT bundle the GL/Vulkan/X11/Wayland
  stack (same stance as Windows). **Zero** engine/Makefile edits needed.
- **Windows-on-ARM:** MSYS2 **`CLANGARM64`** (pacman) is the recommended
  toolchain (Homebrew analog); triple `aarch64-w64-mingw32`. Default renderer
  **D3D11**; **Vulkan** for real Adreno hardware and is provided by the GPU
  **driver** (do NOT bundle a Vulkan runtime — there is no MoltenVK equivalent to
  ship). Install Git for Windows so the Bash tool works.

## Linux/arm64 AppImage: start here
Scaffolded under `linux/`; read `docs/PORTING-LINUX.md` first. Verify in an
**arm64 Ubuntu VM in Parallels** (setup steps in `docs/BUILDING-LINUX.md`) —
`./linux/scripts/build-all.sh --install` then `./linux/tests/run.sh`. Nothing has
been run yet on a real Linux host, so treat every "it builds/passes" claim as
**unverified** until the VM (or the `ubuntu-24.04-arm` CI job) is green. The one
Linux-specific edge over macOS/Windows: Mesa's **software rasterisers** (llvmpipe
GL / lavapipe Vulkan) let the Vulkan loader + renderer-init tests actually run
headless in the VM/CI — real-GPU rendering still stays Tier 2/manual.

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

## Runtime behavioural test tier (Phase 1 landed; more pending)
The build/packaging tests prove the client *builds and boots*; this tier proves
it *behaves*. It drives the engine headless against an original, licensing-clean
fixture and asserts real behaviour — **no id data**, so unlike the old
`HAVE_DATA`-gated checks it actually runs in CI.

**Landed & verified** (8/8 against the freshly-built engine; wired into both
`macos/tests/run.sh` and `linux/tests/run.sh` via auto-discovery):
- `fixtures/ftetest/` — original **GPL/CC0** test gamedir (own `LICENSE`, no id
  content): `tools/gen_bsp.py` (zero-dependency BSP29 generator) + human-editable
  `maps/ftetest.map`; `tools/gen_assets.py` (original `.mdl`/`.spr`/`.wav` under
  `progs/` and `sound/`); self-reporting QuakeC in `src/` (autocompiled, or via
  the in-tree `fteqcc` built with `make qcc-rel`); malformed
  `maps/{badver,trunc}.bsp` for graceful-failure tests; `maps/compile.sh`
  (ericw-tools `qbsp` if present else `gen_bsp.py`; `gen_assets.py`; `fteqcc`).
- `tests/behaviour/behaviour-suite.sh` — POSIX runner (both harnesses drive it):
  boots `-dedicated` on the fixture, asserts server spawn + QuakeC self-report
  (map id, `sv_accelerate`/`sv_maxspeed` read + write-roundtrip, entity spawn,
  `find`, lightstyle, **model/sprite/sound precache + ambient/makestatic**,
  extensions) + graceful **bad-map and bad-mod** handling (corrupt `.bsp` and
  corrupt `sv_progs` both diagnose and drop out, never crash/hang) + **server-side
  changelevel** (switches `ftetest`→`ftetest2`, re-runs worldspawn with the new
  `mapname`) + **console/cvar conformance** (`set`, alias define+invoke, unknown
  command diagnosed not crashed). Malformed fixtures (`maps/{badver,trunc}.bsp`,
  `bad/{badprogs,junkprogs}.dat`) derive from the good artifacts via
  `tools/gen_bad.py`; `maps/ftetest2.bsp` is a filename-distinct copy. Emits
  `BEHAVIOUR-{PASS,FAIL,SKIP}` lines the wrappers fold into pass/fail counts. It
  reads console output via `-condebug`'s `qconsole.log` (a Windows GUI `.exe`
  writes little to a redirected stdout) and cygpath-converts paths on Windows —
  no-op on macOS/Linux — so the one runner works on all three targets.
- `macos/tests/60-behaviour.sh`, `linux/tests/60-behaviour.sh`,
  `windows/tests/60-behaviour.sh` — thin wrappers; all three test sets now mirror
  each other `10`→`60`. The Windows wrapper uses the packaged `fteqw.exe` (dev
  fallback `engine/release/fteqw64.exe`) and the committed fixtures (no
  python/fteqcc needed); Windows CI already runs `windows/tests/run.sh`.
- `docs/PORTING-TESTING.md` — the design/"why + how to reconstruct" writeup.

This tier already **found & fixed a real engine crash**: dedicated
`+map <badmap>` SIGSEGV'd (longjmp through an unset `host_abort`); fix in
`engine/server/sv_main.c`, upstream report in
`docs/upstream/dedicated-startup-badmap-crash.md`.

**Scope principle (firm):** only build behavioural tests that can be validated on
**each** of the three targets and assert **platform-identical** behaviour —
independent of renderer, GPU, or input focus (i.e. headless dedicated /
QuakeC robustness & conformance). If a test can't be uniformly validated across
all three, **document it as a future goal and desist**. Client-driven / UX /
input / renderer tests are acceptably deferred **indefinitely**.

**Next steps — headless, platform-identical only (not started):**
- LibreQuake historical-mod / total-conversion **load** matrix (server-side load
  only; GPL+CC0, fetched on demand, **never committed**).

**Deferred (documented, not built — see `docs/PORTING-TESTING.md`):** the
client-driven lane (acceleration *obeyed*, impulses, skins, weapon-switch — needs
window focus, only deterministic under Linux/`xvfb`; prototype recipe recorded)
and the golden-image UI tier (renderer-dependent).

**Gotchas discovered:**
- `make m-rel` incremental builds can miss edits under the OneDrive path (stale
  `.o` despite newer source). If a change "doesn't take", `rm` the object (e.g.
  `engine/release/m_sdl2/sv_main.o`) or clean-rebuild.
- `60-behaviour.sh` tests whatever engine it finds and prefers the *installed*
  app bundle, which may be stale vs `engine/release/` — rebuild+reinstall before
  trusting a local run (CI rebuilds first, so it's current there).

## House rules
- Scripts: `set -euo pipefail`; watch the `pipefail` + `grep -q` SIGPIPE trap on
  large producers (`nm`, `dumpbin`) — use `grep -c … || true`.
- No machine-specific hardcoded paths; derive from the package-manager prefix and
  the repo location; honor `FTEQW_APP` / `FTEQW_DATA` (and Windows equivalents).
- After finishing a unit of work, run the tests and report what's verified vs
  what still needs real hardware.
- **Spelling — match upstream FTE's British English** for anything new (prose,
  comments, docs, identifiers, output tokens): `behaviour`, `initialise`,
  `colour`, `recognise`, `optimise`, `grey`, etc. (Census of `engine/`: British
  wins on every uncontaminated signal; the console output is British too, e.g.
  `Unrecognised model format`.) Leave id/GPL-inherited American identifiers
  untouched — `SV_Init`, `color`, `center`, `license` are fixed API/legal terms,
  not style choices. Don't introduce spelling variance.
