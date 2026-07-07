#!/bin/sh
# behaviour-suite.sh -- platform-neutral runtime BEHAVIOUR tests for the engine.
#
# Unlike the per-platform build/packaging tests, this actually *runs* the engine
# against the licensing-clean ftetest fixture (fixtures/ftetest) and asserts that
# the client/server does what a Quake engine should: loads a good map, runs
# QuakeC, spawns entities, honours server cvars, and fails gracefully on bad
# content. It needs NO id Software data.
#
# It is written in POSIX sh so both the zsh macOS harness and the bash Linux
# harness can drive it identically. It prints machine-readable result lines:
#   BEHAVIOUR-PASS: <name>
#   BEHAVIOUR-FAIL: <name> -- <detail>
#   BEHAVIOUR-SKIP: <name> -- <reason>
# and exits non-zero if any check failed. Each platform's 60-behaviour.sh parses
# those lines back into its own pass/fail counters.
#
# Usage: behaviour-suite.sh --engine <binary> --fixture <dir> [--build] [--timeout N]
#
# SPDX-License-Identifier: GPL-2.0-or-later
set -u

ENGINE=""; FIXTURE=""; BUILD=0; TMO=10
while [ $# -gt 0 ]; do
	case "$1" in
		--engine)  ENGINE="$2"; shift 2 ;;
		--fixture) FIXTURE="$2"; shift 2 ;;
		--build)   BUILD=1; shift ;;
		--timeout) TMO="$2"; shift 2 ;;
		*) echo "behaviour-suite: unknown arg $1" >&2; exit 2 ;;
	esac
done

fails=0
emit_pass(){ echo "BEHAVIOUR-PASS: $1"; }
emit_fail(){ echo "BEHAVIOUR-FAIL: $1 -- ${2:-}"; fails=$((fails+1)); }
emit_skip(){ echo "BEHAVIOUR-SKIP: $1 -- ${2:-}"; }

[ -n "$ENGINE" ]  || { echo "behaviour-suite: --engine required" >&2; exit 2; }
[ -n "$FIXTURE" ] || { echo "behaviour-suite: --fixture required" >&2; exit 2; }
if [ ! -x "$ENGINE" ]; then emit_fail "engine_present" "no engine at $ENGINE"; echo "SUMMARY 0 1"; exit 1; fi

# Ensure the fixture binaries exist (regenerate if asked / missing).
if [ "$BUILD" = 1 ] || [ ! -f "$FIXTURE/progs.dat" ] || [ ! -f "$FIXTURE/maps/ftetest.bsp" ]; then
	if [ -x "$FIXTURE/maps/compile.sh" ]; then
		"$FIXTURE/maps/compile.sh" >/dev/null 2>&1 || true
	fi
fi
if [ ! -f "$FIXTURE/maps/ftetest.bsp" ] || [ ! -f "$FIXTURE/progs.dat" ]; then
	emit_fail "fixture_present" "missing ftetest.bsp or progs.dat under $FIXTURE"
	echo "SUMMARY 0 $fails"; exit 1
fi
emit_pass "fixture_present"

BASEDIR="$(cd "$FIXTURE/.." && pwd)"   # parent of the ftetest gamedir

# On Windows/MSYS2 the native engine .exe needs Windows-style paths for filesystem
# args; cygpath converts them. On macOS/Linux cygpath is absent, so paths pass
# through unchanged.
to_native(){ if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
BASEDIR_ARG="$(to_native "$BASEDIR")"

# run_headless <secs> <logfile> <extra engine args...>
# Runs the dedicated server with the fixture; kills it after <secs> if it hangs.
# Sets HUNG=1 if it had to be killed, RC to the exit code otherwise.
#
# Console output is captured via -condebug into qconsole.log under FTEHOME and
# folded into <logfile>. We read qconsole.log rather than stdout because the
# Windows engine is a GUI-subsystem .exe that AllocConsole()s in dedicated mode
# and writes little to a redirected stdout; qconsole.log works identically on
# every platform (FTEHOME is honoured cross-platform, engine/common/fs.c).
run_headless(){
	secs="$1"; log="$2"; shift 2
	home="$(mktemp -d 2>/dev/null || echo /tmp/ftebeh.$$)"
	mkdir -p "$home"
	HUNG=0; RC=0
	FTEHOME="$(to_native "$home")" "$ENGINE" -dedicated -condebug \
		-basedir "$BASEDIR_ARG" +game ftetest "$@" >"$log" 2>&1 &
	p=$!
	i=0
	while kill -0 "$p" 2>/dev/null; do
		i=$((i+1)); [ "$i" -ge "$secs" ] && { kill -9 "$p" 2>/dev/null; HUNG=1; break; }
		sleep 1
	done
	wait "$p" 2>/dev/null; RC=$?
	[ -f "$home/qconsole.log" ] && cat "$home/qconsole.log" >> "$log" 2>/dev/null
	rm -rf "$home"
}

log_has(){ grep -aq "$1" "$2" 2>/dev/null; }
log_count(){ grep -ac "$1" "$2" 2>/dev/null || echo 0; }

# ---------------------------------------------------------------------------
# Lane A: good map loads, QuakeC runs, all self-report checks pass.
# ---------------------------------------------------------------------------
GLOG="$(mktemp)"
run_headless "$TMO" "$GLOG" +map ftetest +wait +wait +quit

if [ "$HUNG" = 1 ]; then
	emit_fail "goodmap_terminates" "engine had to be killed after ${TMO}s"
else
	emit_pass "goodmap_terminates"
fi
if log_has "Server spawned" "$GLOG"; then emit_pass "goodmap_server_spawned"
else emit_fail "goodmap_server_spawned" "no 'Server spawned' (see log)"; fi

if log_has "FTETEST BEGIN" "$GLOG" && log_has "FTETEST END" "$GLOG"; then
	emit_pass "quakec_ran"
else
	emit_fail "quakec_ran" "missing FTETEST BEGIN/END markers"
fi

# every self-reported capability check must be PASS, none FAIL
if log_has "FTETEST .*: FAIL" "$GLOG"; then
	det="$(grep -a 'FTETEST .*: FAIL' "$GLOG" | tr '\n' ';')"
	emit_fail "quakec_self_report" "$det"
else
	npass="$(grep -ac 'FTETEST .*: PASS' "$GLOG")"
	if [ "${npass:-0}" -ge 9 ]; then emit_pass "quakec_self_report"
	else emit_fail "quakec_self_report" "only $npass PASS lines"; fi
fi

# no crash: clean run must exit 0 (a signal death shows up as RC>=128, and a
# SIGSEGV never writes a marker to the engine's own log, so we key off RC).
if [ "$HUNG" = 0 ] && [ "$RC" -ge 128 ]; then
	emit_fail "goodmap_no_crash" "engine died from signal (rc=$RC)"
elif grep -aqiE 'segmentation|sigsegv|sigabrt|assertion failed|fatal' "$GLOG"; then
	emit_fail "goodmap_no_crash" "crash marker in log"
else
	emit_pass "goodmap_no_crash"
fi

# ---------------------------------------------------------------------------
# Lane B: bad maps fail gracefully (clear error, no hang, no crash).
# ---------------------------------------------------------------------------
for bad in badver trunc; do
	if [ ! -f "$FIXTURE/maps/$bad.bsp" ]; then
		emit_skip "badmap_$bad" "fixture maps/$bad.bsp absent"
		continue
	fi
	BLOG="$(mktemp)"
	run_headless "$TMO" "$BLOG" +map "$bad" +quit
	graceful=1; why=""
	if [ "$HUNG" = 1 ]; then graceful=0; why="hung on bad map"; fi
	# a SIGSEGV/SIGABRT death shows up as RC>=128 (not from our kill, since HUNG=0)
	if [ "$HUNG" = 0 ] && [ "$RC" -ge 128 ]; then
		graceful=0; why="${why:+$why; }engine crashed (rc=$RC, signal $((RC-128)))"
	fi
	if grep -aqiE 'segmentation|sigsegv|sigabrt|assertion failed' "$BLOG"; then
		graceful=0; why="${why:+$why; }crash marker in log"
	fi
	if ! grep -aqiE "couldn't load|not found or couldn|unrecognised|corrupt|bad version" "$BLOG"; then
		graceful=0; why="${why:+$why; }no diagnostic error message"
	fi
	if [ "$graceful" = 1 ]; then emit_pass "badmap_$bad"; else emit_fail "badmap_$bad" "$why"; fi
	rm -f "$BLOG"
done

# ---------------------------------------------------------------------------
# Lane C: corrupt server gamecode (bad mods) fails gracefully — a bad progs must
# diagnose and drop out, never crash or hang. Same platform-identical robustness
# guarantee as the bad-map lane; also guards the SV_Init startup longjmp path.
# ---------------------------------------------------------------------------
if [ -d "$FIXTURE/bad" ]; then
	for bp in "$FIXTURE"/bad/*.dat; do
		[ -e "$bp" ] || continue
		name="$(basename "$bp")"
		MLOG="$(mktemp)"
		run_headless "$TMO" "$MLOG" +set sv_progs "bad/$name" +map ftetest +quit
		graceful=1; why=""
		if [ "$HUNG" = 1 ]; then graceful=0; why="hung on bad mod"; fi
		if [ "$HUNG" = 0 ] && [ "$RC" -ge 128 ]; then
			graceful=0; why="${why:+$why; }engine crashed (rc=$RC, signal $((RC-128)))"
		fi
		if grep -aqiE 'segmentation|sigsegv|sigabrt|assertion failed' "$MLOG"; then
			graceful=0; why="${why:+$why; }crash marker in log"
		fi
		if ! grep -aqiE "wrong version|failed to load|couldn't load|not found" "$MLOG"; then
			graceful=0; why="${why:+$why; }no diagnostic error message"
		fi
		if [ "$graceful" = 1 ]; then emit_pass "badmod_$name"; else emit_fail "badmod_$name" "$why"; fi
		rm -f "$MLOG"
	done
fi

# ---------------------------------------------------------------------------
# Lane D: server-side changelevel — the server switches map and re-runs
# worldspawn with the new mapname. Platform-identical (no client/renderer).
# The QC (ftetest_chain=1) loads ftetest, then changelevels to ftetest2, then
# quits; we assert both worldspawns ran (i.e. the map actually changed).
# ---------------------------------------------------------------------------
if [ -f "$FIXTURE/maps/ftetest2.bsp" ]; then
	DLOG="$(mktemp)"
	run_headless "$TMO" "$DLOG" +set ftetest_chain 1 +map ftetest
	ok=1; why=""
	if [ "$HUNG" = 1 ]; then ok=0; why="hung (map switch never completed)"; fi
	if [ "$HUNG" = 0 ] && [ "$RC" -ge 128 ]; then ok=0; why="${why:+$why; }crashed (rc=$RC)"; fi
	# map1 line ends in "ftetest" (not a digit); map2 line ends in "ftetest2".
	grep -aqE "worldmap: ftetest([^0-9]|$)" "$DLOG" || { ok=0; why="${why:+$why; }map1 worldspawn missing"; }
	grep -aqE "worldmap: ftetest2"          "$DLOG" || { ok=0; why="${why:+$why; }map2 worldspawn missing (no switch)"; }
	if [ "$ok" = 1 ]; then emit_pass "changelevel"; else emit_fail "changelevel" "$why"; fi
	rm -f "$DLOG"
else
	emit_skip "changelevel" "fixture maps/ftetest2.bsp absent"
fi

# ---------------------------------------------------------------------------
# Lane E: console command + cvar conformance. Before the map spawns, the console
# sets a cvar (`set`), defines + invokes an alias, and issues an unknown command.
# The QC reads the cvar/alias effects back; we assert the unknown command was
# diagnosed (not crashed). Platform-identical (no client/renderer).
# ---------------------------------------------------------------------------
ELOG="$(mktemp)"
run_headless "$TMO" "$ELOG" \
	+set ftetest_console 1 +set ftetest_cvar 42 \
	+alias ftesetter "set ftetest_alias 7" +ftesetter \
	+badcmd_unknown_xyz +map ftetest +wait +wait +quit
ok=1; why=""
if [ "$HUNG" = 1 ]; then ok=0; why="hung"; fi
if [ "$HUNG" = 0 ] && [ "$RC" -ge 128 ]; then ok=0; why="${why:+$why; }crashed (rc=$RC)"; fi
grep -aq "FTETEST cvar_from_console: PASS" "$ELOG" || { ok=0; why="${why:+$why; }set/cvar readback failed"; }
grep -aq "FTETEST alias_executed: PASS"    "$ELOG" || { ok=0; why="${why:+$why; }alias define/exec failed"; }
grep -aqi 'unknown command "badcmd_unknown_xyz"' "$ELOG" || { ok=0; why="${why:+$why; }unknown-command not diagnosed"; }
if grep -aqE "FTETEST .*: FAIL" "$ELOG"; then ok=0; why="${why:+$why; }a self-report FAIL"; fi
if [ "$ok" = 1 ]; then emit_pass "console_conformance"; else emit_fail "console_conformance" "$why"; fi
rm -f "$ELOG"

rm -f "$GLOG"
echo "SUMMARY fails=$fails"
[ "$fails" -eq 0 ]
