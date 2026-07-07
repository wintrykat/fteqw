// test.qc -- self-reporting server QuakeC for the ftetest fixture.
//
// Runs on a headless dedicated server. Each capability check bprints a line of
// the form "FTETEST <name>: PASS" or "FTETEST <name>: FAIL <detail>", which the
// behavioural test runner greps out of qconsole.log. worldspawn drives the
// checks that need no connected client; StartFrame ends the run deterministically.
//
// 100% original authorship, no id Software content.
// SPDX-License-Identifier: GPL-2.0-or-later

float reported;   // guard so the worldspawn report runs once
float switched;   // changelevel lane: guard so the map switch is issued once

void(string name, float ok, string detail) check =
{
	bprint("FTETEST ");
	bprint(name);
	if (ok)
		bprint(": PASS\n");
	else
	{
		bprint(": FAIL ");
		bprint(detail);
		bprint("\n");
	}
};

// required prog functions (stubs -- no client connects in the headless lane).
// A client-driven lane (acceleration obeyed, impulses, skins, weapon switch) was
// prototyped and proven viable but needs window focus, so it is deterministic
// only under Linux/xvfb and is DEFERRED (see docs/PORTING-TESTING.md).
void() main = {};
void() PlayerPreThink = {};
void() PlayerPostThink = {};
void() ClientKill = {};
void() ClientConnect = {};
void() PutClientInServer = {};
void() ClientDisconnect = {};
void() SetNewParms = {};
void() SetChangeParms = {};

void() StartFrame =
{
	// Give the server one full frame to settle, then act deterministically so
	// the headless run always terminates even without +quit in the buffer.
	if (!reported)
		return;

	// changelevel lane (ftetest_chain=1): on the first map, switch to ftetest2;
	// on the second map, quit. Keyed on mapname so it is robust to whether
	// changelevel resets progs globals. Without the cvar, quit after one map.
	if (cvar("ftetest_chain"))
	{
		if (mapname == "ftetest" && !switched)
		{
			switched = TRUE;
			localcmd("changelevel ftetest2\n");
		}
		else if (mapname == "ftetest2")
			localcmd("quit\n");
		return;
	}

	localcmd("quit\n");
};

// map entities (spawned by the server from the BSP entity lump)
void() info_player_start = {};

void() worldspawn =
{
	local entity e, e2, e3;
	local float a, b;

	bprint("FTETEST BEGIN\n");

	// --- console / builtin dispatch -----------------------------------------
	check("builtin_bprint", TRUE, "");   // reaching here proves bprint works

	// --- map identity (basis for changelevel correctness checks) ------------
	// distinct per-map line so the changelevel lane can confirm the switch
	bprint("FTETEST worldmap: ");
	bprint(mapname);
	bprint("\n");
	check("map_name", mapname == "ftetest" || mapname == "ftetest2", mapname);

	// --- server-imposed movement cvars exist and are readable ---------------
	a = cvar("sv_accelerate");
	b = cvar("sv_maxspeed");
	check("cvar_read_accel", a > 0, ftos(a));
	check("cvar_read_maxspeed", b > 0, ftos(b));

	// --- cvar write round-trip (server can impose values) -------------------
	cvar_set("sv_maxspeed", "123");
	check("cvar_write_roundtrip", cvar("sv_maxspeed") == 123, ftos(cvar("sv_maxspeed")));
	cvar_set("sv_maxspeed", ftos(b));   // restore

	// --- entity spawn + geometry --------------------------------------------
	e = spawn();
	setorigin(e, '0 0 -200');
	setsize(e, '-16 -16 -24', '16 16 32');
	e.classname = "ftetest_probe";
	check("entity_spawn", e != world, "");
	check("entity_setsize", e.size_x == 32, vtos(e.size));

	// --- find() over the entity list ----------------------------------------
	check("entity_find", find(world, classname, "ftetest_probe") == e, "");

	// --- static entity + lightstyle builtins execute ------------------------
	lightstyle(0, "m");
	check("lightstyle", TRUE, "");

	// --- asset precache: model / sprite / sound / ambient -------------------
	// precache_model actually loads the model on the server (assigns modelindex),
	// so these exercise the .mdl and .spr loaders, not just name registration.
	precache_model("progs/ftetest.mdl");
	precache_model("progs/ftetest.spr");
	precache_sound("sound/ftetest.wav");

	e2 = spawn();
	setorigin(e2, '0 0 -200');
	setmodel(e2, "progs/ftetest.mdl");
	check("precache_model_mdl", e2.modelindex > 0, ftos(e2.modelindex));

	e3 = spawn();
	setorigin(e3, '32 0 -200');
	setmodel(e3, "progs/ftetest.spr");
	check("precache_model_spr", e3.modelindex > 0, ftos(e3.modelindex));
	makestatic(e3);                          // exercise makestatic on a sprite
	check("makestatic", TRUE, "");

	check("precache_sound", TRUE, "");       // reached => precache_sound didn't error

	// area-based ambient sound (baseline static sound at a point in the room)
	ambientsound('0 0 -200', "sound/ftetest.wav", 1, 1);
	check("ambientsound", TRUE, "");

	// --- engine extension query ---------------------------------------------
	check("checkextension", checkextension("PRINTF") >= 0, "");

	// --- console / cvar conformance (only in that lane) ---------------------
	// The lane launches with `+set ftetest_console 1`, a `set` of ftetest_cvar,
	// and an alias whose body sets ftetest_alias -- all via the console before
	// the map spawns. Reading them back here proves the console set/alias path.
	if (cvar("ftetest_console"))
	{
		check("cvar_from_console", cvar("ftetest_cvar") == 42, ftos(cvar("ftetest_cvar")));
		check("alias_executed", cvar("ftetest_alias") == 7, ftos(cvar("ftetest_alias")));
	}

	reported = TRUE;
	bprint("FTETEST END\n");
};
