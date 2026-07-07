# Building (Linux / arm64 AppImage)

Native arm64 (aarch64) build of FTEQW, packaged as a self-contained `.AppImage`.
For *why* each step is shaped the way it is, see
[`PORTING-LINUX.md`](PORTING-LINUX.md). This file is the practical how-to.

## Prerequisites

- An **aarch64** Linux with a working GPU driver. Developed on Ubuntu in a
  Parallels VM on Apple Silicon (see [Setting up the VM](#setting-up-a-parallels-ubuntu-vm)).
- A C toolchain and the dev libraries below. `build-all.sh --install` will fetch
  any that are missing (via `apt`), or install them yourself:

```sh
sudo apt-get install -y --no-install-recommends \
  build-essential clang pkg-config git patchelf file \
  libsdl2-dev libpng-dev libjpeg-dev libvorbis-dev libogg-dev \
  libfreetype-dev libopus-dev libspeex-dev libspeexdsp-dev zlib1g-dev \
  libgl1-mesa-dev libvulkan-dev \
  libavformat-dev libavcodec-dev libavutil-dev libswscale-dev libswresample-dev \
  librsvg2-bin
```

`linuxdeploy` and `appimagetool` are downloaded automatically on first build
(cached under `build/linux/tools/`) and run without FUSE.

## One command

```sh
./linux/scripts/build-all.sh            # or: --install to fetch missing deps
```

Produces `build/linux/FTEQW-aarch64.AppImage` — engine + plugins, self-contained
(no dev packages needed to *run* it, only a GPU driver).

## The scripts

Each sources `common.sh` for its configuration:

| Script | Does |
|--------|------|
| `common.sh` | Shared config/helpers; derives arch, repo root, deps, the self-containment allowlist. Not run directly. |
| `build-engine.sh` | Builds the merged GL+Vulkan aarch64 engine → `engine/release/fteqw-sdl2`. |
| `make-appdir.sh` | Assembles + self-contains the `FTEQW.AppDir` (engine, AppRun, desktop, icon) via linuxdeploy. |
| `build-plugins.sh [names…]` | Builds/bundles the plugins (default `ffmpeg qi`) into the AppDir. |
| `build-appimage.sh` | Packs the AppDir into `FTEQW-<cpu>.AppImage` with appimagetool. |
| `build-all.sh` | Runs the four above in order. |
| `AppRun` | The template installed as the AppImage entrypoint. |

Run a stage on its own, e.g. after editing a plugin:

```sh
./linux/scripts/build-plugins.sh ffmpeg
./linux/scripts/build-appimage.sh
```

## Configuration (environment variables)

| Var | Default | Meaning |
|-----|---------|---------|
| `BUILD_DIR` | `build/linux` | Where the AppDir, AppImage, and tool cache go. |
| `APPDIR` | `$BUILD_DIR/FTEQW.AppDir` | The assembled AppDir. |
| `APPIMAGE` | `$BUILD_DIR/FTEQW-<cpu>.AppImage` | The packed AppImage. |
| `FTEQW_DATA` | `$XDG_DATA_HOME/fteqw` | Runtime game-data dir (kept outside the AppImage). |
| `CC` | `cc` | Compiler (also determines the arch triple). |

## Game data

The build ships no game content. Put your own under `$FTEQW_DATA`:

```
~/.local/share/fteqw/
├── id1/   pak0.pak, pak1.pak      # your Quake install (registered)
├── qw/                            # QuakeWorld data
└── <mod dirs>/                    # fortress, ctf, zer, arena, …
```

`id1/pak0.pak` is required for the engine to do anything useful; the
data-dependent tests key off its presence.

## Running it

```sh
./build/linux/FTEQW-aarch64.AppImage                       # launches the engine
./build/linux/FTEQW-aarch64.AppImage +set vid_renderer vk  # Vulkan (needs a driver ICD)
FTEQW_DATA=/games/quake ./build/linux/FTEQW-aarch64.AppImage -game fortress +map start
```

If the AppImage complains it needs FUSE, either install `libfuse2`, or run it
with `--appimage-extract-and-run` / `APPIMAGE_EXTRACT_AND_RUN=1`.

## Verifying a build

```sh
./linux/tests/run.sh
```

Covers toolchain, the engine binary (both renderers compiled in), the Vulkan
loader via software lavapipe, plugin build/load/metadata, and full
self-containment (static `ldd` audit + launching the packed AppImage). With game
data present it also runs the headless GL/Vulkan renderer-init tests (Xvfb +
software rasterisers); without data or a display, those skip. A failure names the
broken assumption — cross-reference [`PORTING-LINUX.md`](PORTING-LINUX.md).

## Setting up a Parallels Ubuntu VM

On an Apple Silicon Mac, Parallels runs an **arm64** Linux guest — the right arch
for this port.

1. **Get an arm64 Ubuntu image.** In Parallels: *File → New… → Install Windows or
   another OS*, and point it at the **Ubuntu Server/Desktop for ARM** ISO
   (`ubuntu-24.04-desktop-arm64.iso` or the daily arm64 image). Parallels also
   offers "Download Ubuntu" — that download is arm64 on Apple Silicon.
2. **Give it room:** ≥ 4 CPUs, ≥ 4 GB RAM, ≥ 20 GB disk (the engine + toolchain
   are modest; headroom keeps compiles quick).
3. **Install Parallels Tools** (Devices menu) so you get a usable GL desktop —
   the guest gets a virtual GPU (OpenGL, no Vulkan/real-GPU; that's expected, see
   the tier notes in `PORTING-LINUX.md`).
4. **In the guest:**
   ```sh
   sudo apt-get update
   sudo apt-get install -y git
   git clone <this-repo-url> fteqw && cd fteqw
   ./linux/scripts/build-all.sh --install     # installs deps, builds the AppImage
   ./linux/tests/run.sh                        # verify
   ```
5. For the software-render and headless tests, also install the test tools:
   ```sh
   sudo apt-get install -y xvfb mesa-utils libgl1-mesa-dri mesa-vulkan-drivers vulkan-tools
   ```
6. To exercise real rendering, drop a `pak0.pak` into `~/.local/share/fteqw/id1/`
   and re-run the tests — the GL/Vulkan init checks will light up (via the virtual
   GPU / software rasterisers).

Sharing the repo from the Mac into the guest also works (Parallels shared
folders), but a native clone avoids case-insensitive-FS and file-watching
surprises.
