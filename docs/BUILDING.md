# Building

Native Apple Silicon build of FTEQW. For *why* each step is shaped the way it is,
see [`PORTING.md`](PORTING.md). This file is the practical how-to.

## Prerequisites

- An Apple Silicon Mac, macOS 11+.
- Xcode Command Line Tools (`xcode-select --install`).
- [Homebrew](https://brew.sh/) at `/opt/homebrew` (the arm64 default).

The build needs these formulae; `build-all.sh --install` will install any that
are missing, or install them yourself:

```sh
brew install pkgconf autoconf automake libtool \
             sdl2 libpng jpeg-turbo libvorbis libogg freetype opus speex speexdsp \
             vulkan-headers vulkan-loader molten-vk vulkan-tools \
             ffmpeg dylibbundler
```

## One command

```sh
./macos/scripts/build-all.sh            # or: --install to fetch missing deps
```

Produces a self-contained `~/Applications/FTEQW.app` (engine + app + plugins).

## The scripts

Each is idempotent and sources `common.sh` for its configuration:

| Script | Does |
|--------|------|
| `common.sh` | Shared config/helpers; discovers Homebrew prefix, repo root, deps. Not run directly. |
| `build-engine.sh` | Builds the merged GL+Vulkan arm64 engine → `engine/release/fteqw-sdl2`. |
| `make-app.sh` | Assembles + self-contains + signs `FTEQW.app` (no plugins yet). |
| `build-plugins.sh [names…]` | Builds/bundles/signs the plugins (default `ffmpeg qi`) into the app. |
| `build-all.sh` | Runs the three above in order. |
| `launcher.sh` | The template installed as the app's `CFBundleExecutable`. |

Run a stage on its own, e.g. after editing a plugin:

```sh
./macos/scripts/build-plugins.sh ffmpeg
```

## Configuration (environment variables)

| Var | Default | Meaning |
|-----|---------|---------|
| `FTEQW_APP` | `~/Applications/FTEQW.app` | Where the app is assembled. |
| `FTEQW_DATA` | `~/Library/Application Support/FTEQW` | Runtime game-data dir (kept outside the app). |

```sh
FTEQW_APP=/tmp/FTEQW.app ./macos/scripts/build-all.sh   # build elsewhere
```

## Game data

The build ships no game content. Put your own under `$FTEQW_DATA` (see the README
for the layout). `id1/pak0.pak` is required for the engine to do anything useful;
the data-dependent tests key off its presence.

## Verifying a build

```sh
./macos/tests/run.sh
```

38 checks across toolchain, engine, renderers, plugins, and self-containment.
With game data present it also runs the display-dependent renderer/runtime tests;
without, those skip. A failure names the broken assumption — cross-reference
[`PORTING.md`](PORTING.md).

## Rebasing on upstream FTEQW

Because the only source change is one line in `engine/vk/vk_init.c`, pulling a
new upstream is usually clean:

```sh
git remote add upstream https://github.com/fte-team/fteqw.git   # once
git fetch upstream && git merge upstream/master
./macos/scripts/build-all.sh && ./macos/tests/run.sh
```

If the test run goes green, the port survived the update. If not, the failing
test points at the section of `PORTING.md` describing what moved.
