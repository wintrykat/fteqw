# FTEQW for Apple Silicon (native arm64)

A native **Apple Silicon (arm64)** build of the [FTEQW](https://www.fteqw.org/)
engine, packaged as a self-contained macOS `.app`, that brings **full Quake and
QuakeWorld** — single-player *and* multiplayer, with broad mod support — to
M-series Macs without Rosetta.

FTEQW is the "swiss-army knife" Quake engine: it runs both NetQuake and
QuakeWorld game code in one binary, which is what makes it the right base for
covering the whole lifespan of Quake mods (Team Fortress and its forks, Threewave
/ Thunderwalker CTF, Zerstörer, RuneQuake, Rocket/Clan Arena, and so on) in a
single native app.

> **Honest framing.** This is a *vibe-coded* port: a focused effort to get
> upstream FTEQW building, rendering (OpenGL **and** Vulkan via MoltenVK), and
> running its plugins natively on Apple Silicon — not a re-architecture of the
> engine. The engine source is changed by exactly **one line**; everything else
> is build tooling, packaging, and tests that live alongside the upstream tree.
> Because "vibe-coded" means the seams are held together by workarounds against
> moving upstream parts, the project leans hard on **automated tests** (see
> below) as the mechanism for catching and fixing breakage when FTEQW, a
> library, or macOS changes. If a test goes red, [`docs/PORTING.md`](docs/PORTING.md)
> explains the assumption it guards and how to restore it.

## Target

| | |
|---|---|
| **Architecture** | Apple Silicon / `arm64` only |
| **OS** | macOS 11 (Big Sur) or later; developed on macOS 26 (Tahoe) |
| **Renderers** | OpenGL and Vulkan (via MoltenVK), runtime-switchable |
| **Build target** | FTEQW `FTE_TARGET=SDL2`, merged (`m-rel`) GL+Vulkan binary |
| **Plugins** | `ffmpeg` (media) and `qi` (Quaddicted map database) |

Intel Macs are out of scope. The stock upstream project already covers other
platforms; this fork exists specifically for native Apple Silicon.

## Quick start

Requires [Homebrew](https://brew.sh/). From a clone of this repo:

```sh
# build engine + self-contained app + plugins (add --install to auto-install deps)
./macos/scripts/build-all.sh --install
```

That produces `~/Applications/FTEQW.app`, fully self-contained (no Homebrew
needed to *run* it). Then add your own Quake data — this repo ships **no**
copyrighted game content:

```
~/Library/Application Support/FTEQW/
├── id1/   pak0.pak, pak1.pak      # your Quake install (registered)
├── qw/                            # QuakeWorld data
└── <mod dirs>/                    # fortress, ctf, zer, arena, …
```

Launch it, or from a terminal:

```sh
open ~/Applications/FTEQW.app --args -game fortress +map start   # example
```

The launcher defaults the renderer to Vulkan; override per-session with
`+set vid_renderer gl`. See [`docs/BUILDING.md`](docs/BUILDING.md) for details
and options.

## Tests

The test suite is the point of the project — it turns "did an upstream change
break us?" into a single command:

```sh
./macos/tests/run.sh
```

It covers the toolchain, the engine binary (both renderers compiled in), actual
GL and Vulkan initialisation, plugin build/load/metadata, and full
self-containment (static `otool` audit + runtime `lsof`). Tests that need a
display and game data skip automatically in headless CI. See
[`.github/workflows/`](.github/workflows/) for the CI wiring.

## How it's built / what was changed

Everything specific to this port is documented in
**[`docs/PORTING.md`](docs/PORTING.md)** — each workaround, why it exists, and
how to reconstruct or retire it as upstream evolves. The reproducible build
lives in [`macos/scripts/`](macos/scripts/); the tests in
[`macos/tests/`](macos/tests/).

## Windows-on-ARM (aarch64)

The same engine also builds natively for **Windows-on-ARM** — Qualcomm Snapdragon
/ Copilot+ PCs, Surface Pro X, and similar real devices — as a self-contained
package. Same discipline as the macOS port: thin fork, a test for every
workaround, self-contained output, honest docs.

| | |
|---|---|
| **Architecture** | `aarch64` / arm64 only |
| **OS** | Windows 11 on ARM |
| **Toolchain** | MSYS2 **CLANGARM64** (clang, `aarch64-w64-windows-gnu`) |
| **Renderers** | **D3D11 (default)**, Vulkan, OpenGL, D3D9 — one binary, runtime-switchable |
| **Build target** | FTEQW `FTE_TARGET=win64` + overrides — **zero Makefile/engine edits** |
| **Plugins** | `ffmpeg` (media) and `qi` (Quaddicted map database) |

```sh
# in an MSYS2 CLANGARM64 shell, from a clone (add --install to auto-install deps):
./windows/scripts/build-all.sh --install
```

That produces `windows/dist/FTEQW/` (self-contained — no MSYS2 needed to *run* it)
and a portable `FTEQW-<ver>-win-arm64.zip`. An optional Inno Setup installer is
`./windows/scripts/make-installer.sh`. Add your own Quake data under
`%LOCALAPPDATA%\FTEQW\id1\…` — this repo ships **no** game content. Run the tests
with `./windows/tests/run.sh`.

The package ships **D3D11 as the default renderer** (`fte/autoexec.cfg`): the
merged binary would otherwise auto-select OpenGL, which is the weak WoA fallback
and misrenders on the Parallels virtual GPU (red/green font fringing). On a real
Adreno device you can switch to Vulkan — edit that one line to `vid_renderer vk`.

> **The GPU-testing caveat — read this.** Automated CI/VM proves build, packaging,
> self-containment, headless engine-run, and that both renderers are compiled in
> **on a virtual GPU**. It does **not** prove real rendering: neither the
> development VM nor GitHub's `windows-11-arm` runners have a **real GPU** (the VM
> caps at DirectX 11.1 / OpenGL 3.3 with **no Vulkan**). **Real D3D11 and
> Vulkan-on-Adreno rendering are verified only via hardware-gated Tier-2 tests and
> the manual Tier-3 checklist on actual devices** — until a device run is
> recorded, those axes are **"unverified", not "passing"**. Unlike macOS's bundled
> MoltenVK, **no Vulkan runtime is shipped**: on real hardware the Adreno driver
> provides it. See [`docs/PORTING-WINDOWS.md`](docs/PORTING-WINDOWS.md) and
> [`docs/HARDWARE-TESTING.md`](docs/HARDWARE-TESTING.md).

## Upstream & credits

- **Engine:** [FTEQW](https://www.fteqw.org/) — source at
  <https://github.com/fte-team/fteqw>. Original project README preserved as
  [`README.upstream.md`](README.upstream.md).
- **Quake:** © id Software; game code released under the GPL. This repo contains
  no id Software game data.
- **Libraries** (via [Homebrew](https://brew.sh/)): SDL (sdl2-compat + SDL3),
  MoltenVK, FreeType, libpng, jpeg-turbo, libogg/libvorbis, Opus, Speex,
  FFmpeg. Bundling is done with
  [dylibbundler](https://github.com/auriamg/macdylibbundler).

## License

GPL-2.0, inherited from FTEQW and the original Quake sources — see
[`LICENSE`](LICENSE). All additions in this fork (scripts, tests, docs,
packaging) are likewise GPL-2.0. See [`ATTRIBUTION.md`](ATTRIBUTION.md) for the
change summary required by the license.
