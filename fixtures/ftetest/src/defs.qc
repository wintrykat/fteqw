// defs.qc -- system ABI + builtin declarations for the ftetest fixture progs.
//
// 100% original authorship. The global/field NAMES and ORDERING below are the
// Quake progs<->engine ABI (a functional interface, not creative content); the
// canonical reference is FTE's own GPL reimplementation in quakec/basemod/defs.qc.
// Builtin numbers are the standard NetQuake set. Nothing here is id content.
//
// SPDX-License-Identifier: GPL-2.0-or-later

#define TRUE  1
#define FALSE 0

// ---- system globals (order matters up to end_sys_globals) -------------------
entity  self;
entity  other;
entity  world;
float   time;
float   frametime;
float   force_retouch;
string  mapname;
float   deathmatch;
float   coop;
float   teamplay;
float   serverflags;
float   total_secrets;
float   total_monsters;
float   found_secrets;
float   killed_monsters;
float   parm1, parm2, parm3, parm4, parm5, parm6, parm7, parm8;
float   parm9, parm10, parm11, parm12, parm13, parm14, parm15, parm16;
vector  v_forward, v_up, v_right;
float   trace_allsolid;
float   trace_startsolid;
float   trace_fraction;
vector  trace_endpos;
vector  trace_plane_normal;
float   trace_plane_dist;
entity  trace_ent;
float   trace_inopen;
float   trace_inwater;
entity  msg_entity;

void()  main;
void()  StartFrame;
void()  PlayerPreThink;
void()  PlayerPostThink;
void()  ClientKill;
void()  ClientConnect;
void()  PutClientInServer;
void()  ClientDisconnect;
void()  SetNewParms;
void()  SetChangeParms;

void end_sys_globals;

// ---- entity fields (order matters up to end_sys_fields) ---------------------
.float      modelindex;
.vector     absmin, absmax;
.float      ltime;
.float      movetype;
.float      solid;
.vector     origin;
.vector     oldorigin;
.vector     velocity;
.vector     angles;
.vector     avelocity;
.vector     punchangle;
.string     classname;
.string     model;
.float      frame;
.float      skin;
.float      effects;
.vector     mins, maxs;
.vector     size;
.void()     touch;
.void()     use;
.void()     think;
.void()     blocked;
.float      nextthink;
.entity     groundentity;
.float      health;
.float      frags;
.float      weapon;
.string     weaponmodel;
.float      weaponframe;
.float      currentammo;
.float      ammo_shells, ammo_nails, ammo_rockets, ammo_cells;
.float      items;
.float      takedamage;
.entity     chain;
.float      deadflag;
.vector     view_ofs;
.float      button0, button1, button2;
.float      impulse;
.float      fixangle;
.vector     v_angle;
.float      idealpitch;
.string     netname;
.entity     enemy;
.float      flags;
.float      colormap;
.float      team;
.float      max_health;
.float      teleport_time;
.float      armortype;
.float      armorvalue;
.float      waterlevel;
.float      watertype;
.float      ideal_yaw;
.float      yaw_speed;
.entity     aiment;
.entity     goalentity;
.float      spawnflags;
.string     target;
.string     targetname;
.float      dmg_take;
.float      dmg_save;
.entity     dmg_inflictor;
.entity     owner;
.vector     movedir;
.string     message;
.float      sounds;
.string     noise, noise1, noise2, noise3;

void end_sys_fields;

// ---- builtins (standard NetQuake numbers) -----------------------------------
void(vector ang)                    makevectors     = #1;
void(entity e, vector o)            setorigin       = #2;
void(entity e, string m)            setmodel        = #3;
void(entity e, vector min, vector max) setsize      = #4;
float()                             random          = #7;
void(entity e, float chan, string samp, float vol, float atten) sound = #8;
void(string s)                      error           = #10;
entity()                            spawn           = #14;
void(entity e)                      remove          = #15;
entity(entity start, .string fld, string match) find = #18;
void(string s)                      precache_sound  = #19;
void(string s)                      precache_model  = #20;
void(entity client, string s)       stuffcmd        = #21;
void(string s)                      bprint          = #23;
void(string s)                      dprint          = #25;
string(float f)                     ftos            = #26;
string(vector v)                    vtos            = #27;
float(string cv)                    cvar            = #45;
void(string s)                      localcmd        = #46;
entity(entity e)                    nextent         = #47;
void(string var, string val)        cvar_set        = #72;
void(vector pos, string samp, float vol, float atten) ambientsound = #74;
void(entity e)                      makestatic      = #69;
void(string s)                      changelevel     = #70;
void(string s)                      precache_file   = #68;
void(float style, string val)       lightstyle      = #35;
float(string s)                     checkextension  = #99;
