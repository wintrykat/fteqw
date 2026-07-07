# Upstream bug report: dedicated server SIGSEGVs on a bad `+map` at startup

**Status:** prepared for submission to <https://github.com/fte-team/fteqw>
**Found by:** the fork's behavioural test suite (`tests/behaviour/`, fixture `fixtures/ftetest/`)
**Fixed locally in:** `engine/server/sv_main.c` (`SV_Init`) — see `ATTRIBUTION.md`

## Summary

Launching a **dedicated** server with a corrupt, wrong-version, or otherwise
unloadable map on the command line, e.g.

```sh
fteqw -dedicated +map somebadmap
```

crashes with `SIGSEGV` during startup instead of printing the load error and
dropping to the console. (`fteqw +map somebadmap` in a listen/client build is
unaffected — the client path installs its recovery point first.)

## Environment

Reproduced on macOS 26.5 / Apple Silicon (arm64), engine built from upstream
`f937b9d` as `m-rel FTE_TARGET=SDL2`. The defect is platform-neutral (it is in
shared server code), not macOS-specific.

## Reproduction

1. Create any file `maps/badver.bsp` in a gamedir that is not a valid BSP the
   loader accepts (e.g. a valid BSP with the version dword changed, or a
   truncated file).
2. `fteqw -dedicated -basedir <dir> +game <mod> +map badver`
3. The engine prints
   `Host_EndGame: Mod_NumForName: maps/badver.bsp not found or couldn't load`
   and then **crashes** (exit code 139, SIGSEGV) rather than returning to the
   console.

## Backtrace (symbolicated)

```
0   _longjmp + 72                    <- jumps through an uninitialised jmp_buf
1   ??? (garbage address)
2   Mod_ModelLoaded + 420            <- MLS_FAILED -> Host_EndGame -> longjmp(host_abort)
3   COM_DoWork
4   COM_WorkerPartialSync
5   Mod_LoadModel
6   SV_SpawnServer
7   SV_Map_f
8   Cmd_ExecuteString
9   Cbuf_ExecuteLevel
10  Cbuf_Execute                     <- flushed from inside Cmd_StuffCmds()
11  SV_Init
12  main
```

The crashing thread's `x0` is `&host_abort`; the values loaded from it are
stack garbage, confirming `host_abort` was never `setjmp`'d on this path.

## Root cause

On the dedicated path, `main()` calls `SV_Init()` (e.g.
`engine/client/sys_sdl.c`), and `SV_Init()` runs the startup command buffer:

- `Cmd_StuffCmds()` (`engine/common/cmd.c`) appends the command-line `+map …`
  and then calls `Cbuf_Execute()` **immediately**, so the map loads right there;
- a failed model load calls `Host_EndGame()` (`engine/gl/gl_model.c` →
  `engine/client/cl_main.c`), which `longjmp(host_abort, 1)`.

But `host_abort` is only `setjmp`'d by the **client** startup/frame paths
(`Host_Init`, `Host_Frame` in `engine/client/cl_main.c`). On the dedicated
startup path no `setjmp(host_abort)` has run yet, so the `longjmp` jumps through
an uninitialised buffer → SIGSEGV.

## Fix

Establish the recovery point in `SV_Init` **before** any startup command can
execute (right after `host_initialized = true;`, before `FS_ChangeGame()` /
`Cmd_StuffCmds()`):

```c
{
    extern jmp_buf host_abort;
    if (setjmp (host_abort))
    {
        Con_Printf (CON_ERROR "Startup command aborted; server idle at console.\n");
        return;
    }
}
```

With this, a bad startup `+map` prints its diagnostic and the dedicated server
idles at the console (recoverable) instead of crashing. The normal good-map path
is unchanged.

## Note / possible follow-up

This guards the **startup** command buffer. The dedicated frame loop
(`SV_Frame`) does not appear to establish its own `setjmp(host_abort)` the way
the client `Host_Frame` does, so a `Host_Error`/`Host_EndGame` raised at
**runtime** on a dedicated server (e.g. `changelevel` to a bad map from rcon)
may hit the same class of problem. Worth confirming upstream; a `setjmp` around
the dedicated `SV_Frame` loop would cover it. The fork's behavioural suite
currently exercises only the startup path.
```
