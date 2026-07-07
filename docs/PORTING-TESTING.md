# PORTING-TESTING.md — the runtime behavioural test tier

This is the "why + how to reconstruct" for the behavioural test tier, mirroring
`PORTING.md` (macOS) and `PORTING-LINUX.md`. Read it before touching
`tests/behaviour/`, `fixtures/ftetest/`, or the per-platform `60-behaviour.sh`.

## Why this tier exists

The per-platform suites (`macos/tests`, `linux/tests`) prove the client
**builds, links, packages, is self-contained, and boots**. They do not prove it
**behaves** — that it loads a map, runs QuakeC, precaches content, honours
server cvars, or fails gracefully on bad input. Worse, the few runtime checks
that existed were gated on `HAVE_DATA` (a real id `pak0.pak`), so in CI — where
we (correctly) ship no id data — they *skipped*. The behaviour was untested.

This tier closes that gap with an **original, licensing-clean fixture** the
engine can actually run, headless, in CI, with **no id Software content**.

## The licensing-clean fixture (`fixtures/ftetest/`)

Everything the engine needs to spawn a server and run gamecode, authored from
scratch (own `LICENSE`, GPL-2.0-or-later / CC0):

| Path | What | How it's produced |
|------|------|-------------------|
| `maps/ftetest.map` | human-editable room source | hand-written |
| `maps/ftetest.bsp` | the loadable map | `maps/compile.sh`: ericw-tools `qbsp` if installed, else `tools/gen_bsp.py` (a zero-dependency BSP29 writer: hollow room, hull0 render tree + hull1/hull2 clipnodes) |
| `maps/{badver,trunc}.bsp` | malformed maps | wrong-version / truncated copies, for graceful-failure tests |
| `progs/ftetest.mdl` | 1-triangle alias model | `tools/gen_assets.py` (IDPO v6) |
| `progs/ftetest.spr` | 1-frame sprite | `tools/gen_assets.py` (IDSP v1) |
| `sound/ftetest.wav` | 0.1s tone | `tools/gen_assets.py` (RIFF/PCM) |
| `src/*.qc` + `progs.dat` | self-reporting gamecode | `fteqcc` (in-tree, `make qcc-rel`) — the engine can also autocompile it |

Committed **binaries** (`.bsp`, `.dat`, `.mdl`, `.spr`, `.wav`) are regenerable
at any time with `fixtures/ftetest/maps/compile.sh`, which prefers real tools and
falls back to the bundled generators so **CI always has valid content with no
toolchain installed**.

### Why generators instead of only committing binaries

The `.map` is the human source of record, but a real `qbsp` isn't always present
(macOS has no Homebrew formula; CI runners vary). `gen_bsp.py` / `gen_assets.py`
guarantee a byte-reproducible, dependency-free fallback — and, as a bonus, the
QuakeC path exercises the in-tree `fteqcc` itself.

## The self-reporting gamecode (`src/test.qc`)

`worldspawn` runs a battery of capability checks and `bprint`s one line each:

```
FTETEST <name>: PASS
FTETEST <name>: FAIL <detail>
```

`StartFrame` then `localcmd("quit\n")` so the run always terminates. Current
checks (all server-side, no connected client needed): console/`bprint` dispatch,
map identity, `sv_accelerate`/`sv_maxspeed` read + write round-trip, entity spawn
+ geometry, `find`, `lightstyle`, **model + sprite precache** (server loads the
`.mdl`/`.spr` and assigns a `modelindex`), **sound precache**, **ambient sound**,
`makestatic`, and an extension query. The map's entity lump also spawns
`info_player_start` (entity-lump parsing).

## The runner (`tests/behaviour/behaviour-suite.sh`)

POSIX `sh` (so the zsh macOS harness and bash Linux harness drive it identically).
Two lanes:

- **Lane A — good map:** boots `-dedicated +map ftetest`, asserts `Server
  spawned`, the `FTETEST BEGIN/END` markers, that every `FTETEST` line is `PASS`
  (zero `FAIL`), a clean exit (RC 0), and no crash.
- **Lane B — bad maps:** boots `+map {badver,trunc}` and asserts each **fails
  gracefully** — a diagnostic message, no hang, and (critically) **no signal
  death**: a SIGSEGV shows up as `RC >= 128`, which a log scan alone would miss.
- **Lane C — bad mods:** boots `+set sv_progs bad/<corrupt.dat> +map ftetest` for
  each malformed progs and asserts the same graceful-failure guarantee — a bad
  mod must diagnose (`wrong version` / `Failed to load`) and drop out, never
  crash or hang. Also guards the `SV_Init` startup-longjmp path for progs loads.
- **Lane D — changelevel:** boots `+set ftetest_chain 1 +map ftetest`; the QC
  loads `ftetest`, issues `changelevel ftetest2`, then quits. Asserts **both**
  worldspawns ran (`worldmap: ftetest` and `worldmap: ftetest2`) — i.e. the
  server actually switched map and re-ran gamecode with the new `mapname`, with
  no crash/hang. Server-side only (the client-follows-the-server half needs a
  connected player and is deferred). `maps/ftetest2.bsp` is a filename-distinct
  copy (mapname derives from the filename), made by `compile.sh`.
- **Lane E — console/cvar conformance:** before the map spawns, the console does
  `set ftetest_cvar 42`, defines and invokes an alias whose body sets another
  cvar, and issues an unknown command. The QC reads the cvar/alias effects back
  (proving the `set`/alias dispatch path), and the lane asserts the unknown
  command was diagnosed (`Unknown command "…"`) rather than crashing.

The malformed fixtures (`maps/{badver,trunc}.bsp`, `bad/{badprogs,junkprogs}.dat`)
are derived from the fresh good artifacts by `tools/gen_bad.py` (run from
`compile.sh`), so they never go stale.

It prints machine-readable `BEHAVIOUR-{PASS,FAIL,SKIP}` lines and exits non-zero
on any failure. The per-platform `60-behaviour.sh` wrappers translate those lines
into each harness's `pass`/`fail` counters (auto-discovered by `run.sh`).

## Scope principle (what we build vs. defer)

**Only build behavioural tests that can be validated on each of the three target
platforms and that assert platform-identical engine behaviour — independent of
renderer, GPU, or input focus.** These are the headless, dedicated-server /
QuakeC robustness & conformance tests. If a test cannot be uniformly validated
across all three targets, **document it as a future goal and desist** — it is
acceptable that client-driven / UX / input / renderer tests are deferred
indefinitely. (See `CLAUDE.md`; the fork's point is that the same engine behaves
the same everywhere, so the tests proving that must run uniformly.)

- **Tier 1 — headless dedicated (this tier, all platforms, every CI run):**
  server-authoritative behaviour + QuakeC self-report + graceful bad-content /
  bad-mod handling. No GPU, no display. **This is the focus.**
- **Deferred — client-driven (Tier 1.5):** behaviours needing a connected player
  (acceleration *obeyed*, impulses, skins, weapon-model-on-switch). Prototyped
  and **proven viable** (see below), but only deterministic where the client
  window holds input focus — reliable under Linux/`xvfb`, flaky on a
  terminal-launched macOS window. Not uniformly validatable → **not built.**
- **Deferred — golden-image UI:** menu/console/font. Renderer-dependent →
  **not built.**
- **Tier 2/3 — real hardware/manual:** unchanged; see the GPU-testing caveat in
  `PORTING.md` / `WINDOWS-ARM-PORT.md`.

### Deferred client-driven lane — the proven recipe (for when a Linux host/CI is available)

A prototype confirmed the mechanism, so it can be built later without rediscovery:

- Launch **non-dedicated** (listen server + local player) with `+map ftetest`;
  the local player auto-connects and the **server QC** (`PutClientInServer`,
  `PlayerPostThink`) observes it — report via the `-condebug` log, no CSQC needed.
- Two gates found: (1) single-player **auto-pauses while the console is open**,
  zeroing all input — run non-pausing (`+set deathmatch 1`); (2) input is only
  gathered while the window has **focus** (`vid.activeapp`, `cl_input.c`) — a
  terminal-launched macOS window backgrounds and loses focus after a few frames,
  so input dies; Linux/`xvfb` holds focus.
- With those, driving `+forward` produced a clean, correct server-side
  acceleration ramp (velocity climbing toward `sv_maxspeed`) sampled in
  `PlayerPostThink` — i.e. "acceleration obeyed" is directly assertable there.
- Still to resolve when building: a two-player-entity artifact and `impulse` /
  `button0` delivery (gated on `!cl.paused`). Target env: **Linux + `xvfb`**,
  skip on macOS and where `xvfb` is absent.

## Case study: this tier found a real engine crash

The first bad-map check SIGSEGV'd. Root cause: on the **dedicated** startup path
`SV_Init` runs the command-line `+map` (via `Cmd_StuffCmds → Cbuf_Execute`)
*before* any `setjmp(host_abort)` recovery point exists, so a failed model load
(`Host_EndGame → longjmp`) jumps through an **uninitialised** `jmp_buf`. Fixed by
establishing the recovery point first (`engine/server/sv_main.c`); recorded in
`ATTRIBUTION.md`, reported in `docs/upstream/dedicated-startup-badmap-crash.md`.
The bad-map lane is the regression guard.

## How to run / reconstruct

```sh
# regenerate the fixture binaries (safe, no external deps required)
fixtures/ftetest/maps/compile.sh

# run just the behavioural suite against a built engine
sh tests/behaviour/behaviour-suite.sh \
   --engine engine/release/fteqw-sdl2 --fixture fixtures/ftetest --build

# or via a platform harness (folds into its pass/fail counts)
macos/tests/run.sh        # sources macos/tests/60-behaviour.sh
linux/tests/run.sh        # sources linux/tests/60-behaviour.sh
```

Gotchas (also in `CLAUDE.md`): `make m-rel` incremental builds can miss edits
under the OneDrive path — `rm` the stale `.o` if a change "doesn't take"; and
`60-behaviour.sh` prefers the *installed* app bundle, which may be stale versus
`engine/release/` — rebuild+reinstall before trusting a local run.

## Next steps

Per the scope principle, keep extending **headless, platform-identical**
robustness/conformance lanes (things that must behave the same on all three
targets and can be validated on each):

- `windows/tests/60-behaviour.sh` stub once `windows/` exists (mirror this).
- LibreQuake historical-mod / total-conversion **load** matrix (server-side load
  only; GPL+CC0, fetched on demand, never committed) — the load is
  platform-identical; anything needing a client stays deferred.

**Deferred (documented, not built):** the client-driven lane and golden-image UI
tier — see the scope principle above.
