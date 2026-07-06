# Contributing

This is a small, focused Apple-Silicon port of FTEQW. The guiding principle:
**keep the port thin and test-guarded** so it survives upstream churn.

## Principles

1. **Minimise source changes.** The engine tree should differ from upstream by
   as little as possible (currently one line). Prefer build-time overrides,
   packaging, and new files under `macos/` over editing `engine/`. Every source
   edit you *do* make must be recorded in [`ATTRIBUTION.md`](ATTRIBUTION.md) (the
   GPL requires it) and explained in [`docs/PORTING.md`](docs/PORTING.md).
2. **Every workaround gets a test.** If you add or change a workaround, add or
   update the test in `macos/tests/` that would go red if it breaks. A workaround
   with no test is a future silent failure.
3. **Document the *why*.** `PORTING.md` should let someone reconstruct a
   workaround from scratch when the upstream part it works around changes.
4. **No game data, ever.** Never commit id Software content.

## Workflow

```sh
# make your change …
./macos/scripts/build-all.sh     # must succeed
./macos/tests/run.sh             # must pass (locally, with game data present,
                                 # the display/runtime tests run too)
```

Before opening a PR: both commands green, `git diff --stat` reviewed (watch for
unintended `engine/` changes), `ATTRIBUTION.md` / `PORTING.md` updated if
relevant.

## Rebasing on upstream FTEQW

See [`docs/BUILDING.md`](docs/BUILDING.md#rebasing-on-upstream-fteqw). In short:
merge `upstream/master`, run `build-all.sh` then `run.sh`. Green means the port
survived; red points (via the failing test's name) at the `PORTING.md` section
describing what moved.

## Script conventions

- `zsh`, `set -euo pipefail`, source `common.sh` for config/helpers.
- No machine-specific paths — derive from `$BREW` (`brew --prefix`) and the repo
  location. Honour `FTEQW_APP` / `FTEQW_DATA`.
- Watch the `pipefail` + `grep -q` trap: `grep -q` exits early and can `SIGPIPE`
  a large producer (`nm`, `make -p`), tripping `pipefail` even on success. Use
  `grep -c … || true` on big streams.

## Scope

Apple Silicon (`arm64`) only. Intel and other platforms are upstream's domain.
