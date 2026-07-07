# Hardware testing checklist — FTEQW on Windows-on-ARM (real devices)

**Why this file exists.** The automated suite (`windows/tests/`) proves everything
that a GPU-less environment *can* prove — build, packaging, self-containment,
headless engine-run, and that both renderers are compiled in — and it runs green
in the Parallels VM and on GitHub's `windows-11-arm` CI. But neither has a **real
GPU**: the VM caps at DirectX 11.1 / OpenGL 3.3 with **no Vulkan**, and the CI
runners are virtualized. So **real D3D11 rendering and all Vulkan/Adreno
behaviour cannot be validated there.**

This is the honest last mile: a short protocol for someone with a real Snapdragon
/ Copilot+ device (Surface Pro X, etc.) to run and report. Until a run here is
recorded, the Vulkan and real-hardware-rendering axes are **"unverified", not
"passing".**

Two ways to close the gap:
- **Tier 2 (automated on hardware):** run `./windows/tests/run.sh` with
  `FTEQW_REAL_GPU=1` on the device (or register a self-hosted GPU runner — see the
  `hardware-test` job in `.github/workflows/ci-windows-arm.yml`). This flips the
  gated renderer-init tests on.
- **Tier 3 (manual, below):** eyes-on smoke test for things no assertion covers.

---

## Prerequisites

- A real Windows-on-ARM device with a Qualcomm **Adreno** GPU and current drivers.
- The portable ZIP (`FTEQW-<ver>-win-arm64.zip`) from a Tier-1 build, unzipped.
- Your own Quake data in the data dir (`%LOCALAPPDATA%\FTEQW\id1\pak0.pak`, …).
  This repo ships **no** game content.

## Tier 2 — one command

```sh
# in an MSYS2 CLANGARM64 shell, from the repo root, with data in place:
FTEQW_REAL_GPU=1 ./windows/tests/run.sh
```

Expect the previously-skipped tests to now run:
- `D3D11 renderer initialises (real frame)`
- `Vulkan renderer initialises (Adreno)` + `Vulkan enumerates a physical device`

Record pass/fail, the device model, the GPU, and the driver version.

## Tier 3 — manual smoke checklist

Run `fteqw.exe` and confirm each. Note the device/GPU/driver/OS build with results.

- [ ] **Launch** — the app starts to the menu; no missing-DLL error (proves the
      self-contained package works with no MSYS2 present).
- [ ] **D3D11 (default)** — `+set vid_renderer d3d11`; a map renders.
      `+map start` shows the start map; movement/rendering are correct.
- [ ] **Vulkan** — `+set vid_renderer vk`; confirm the console reports the
      **Adreno** driver and a physical device, and a map renders.
- [ ] **Renderer switch** — change `vid_renderer` d3d11 ↔ vk at runtime (or across
      restarts) without a crash.
- [ ] **OpenGL (best-effort)** — `+set vid_renderer gl`; note whether it works,
      is slow, or needs ANGLE. GL is a fallback, not a blocker.
- [ ] **A mod** — e.g. `-game fortress +map <a fortress map>`; loads and plays.
- [ ] **Plugins** — `+plug_load ffmpeg +plug_load qi +plug_list`; both load. Play
      a video/audio file to exercise ffmpeg if possible.
- [ ] **Audio** — sound plays (Opus/Vorbis paths).
- [ ] **Sustained play** — a few minutes of gameplay; no crash, no leak-y
      slowdown.

## Reporting

File a report (or use the breakage issue template) with: device model, SoC/GPU,
GPU driver version, Windows build, the FTEQW version string (from the console),
which checklist items passed/failed, and any console log
(`%LOCALAPPDATA%\FTEQW\qconsole.log`, captured with `-condebug`). A recorded
Tier-2/Tier-3 pass is what lets us move the Vulkan/real-GPU axes from "unverified"
to "verified" in the README.
