#!/usr/bin/env python3
# gen_bsp.py -- emit a minimal, valid Quake BSP29 hollow-room map.
#
# This is the ZERO-DEPENDENCY fallback used by maps/compile.sh when a real
# qbsp (ericw-tools) is not installed. It hand-assembles a single axis-aligned
# empty room (interior +/-256 on each axis) with:
#   - hull0 render tree (6 nodes -> 1 empty leaf, everything else solid)
#   - hull1 (player) and hull2 (large) clipnode trees, walls inset by the
#     standard Quake hull extents so player physics/collision is correct
#   - 6 interior wall faces + one 16x16 flat miptex so the loader is happy
#   - an entity lump (worldspawn + info_player_start) the QC test builds on
#
# The output is 100% original authorship (no id Software content). It exists so
# the headless behavioural test suite can spawn a real server without shipping
# copyrighted map data. `compile.sh` prefers ericw-tools when present (compiling
# the human-editable maps/ftetest.map); this generator guarantees CI always has
# a loadable map regardless of toolchain.
#
# Coordinates/format per the Unofficial Quake BSP2 spec (BSP29 == version 29).
#
# SPDX-License-Identifier: GPL-2.0-or-later

import struct, sys

BSPVERSION = 29
NUMLUMPS   = 15
(L_ENTITIES, L_PLANES, L_MIPTEX, L_VERTEXES, L_VISIBILITY, L_NODES,
 L_TEXINFO, L_FACES, L_LIGHTING, L_CLIPNODES, L_LEAFS, L_MARKSURFACES,
 L_EDGES, L_SURFEDGES, L_MODELS) = range(NUMLUMPS)

CONTENTS_EMPTY = -1
CONTENTS_SOLID = -2

R = 256  # interior half-extent

# ---- planes -----------------------------------------------------------------
# Quake plane: normal[3] float, dist float, type int (0=x,1=y,2=z axial).
# Convention: leading nonzero normal component positive; front (child[0]) is the
# n.p - dist >= 0 halfspace.
planes = []
def add_plane(n, d, t):
    planes.append((n, d, t)); return len(planes) - 1

# hull0 walls (6): +x,-x,+y,-y (ceiling)+z,(floor)+z
P_XP = add_plane((1,0,0),  R, 0)  # x=+256
P_XN = add_plane((1,0,0), -R, 0)  # x=-256
P_YP = add_plane((0,1,0),  R, 1)  # y=+256
P_YN = add_plane((0,1,0), -R, 1)  # y=-256
P_ZP = add_plane((0,0,1),  R, 2)  # z=+256 ceiling
P_ZN = add_plane((0,0,1), -R, 2)  # z=-256 floor

# ---- vertices / edges / surfedges / faces (interior walls) ------------------
verts = [
    (-R,-R,-R),( R,-R,-R),( R, R,-R),(-R, R,-R),  # 0..3 floor
    (-R,-R, R),( R,-R, R),( R, R, R),(-R, R, R),  # 4..7 ceiling
]
edges = [(0,0)]      # edge 0 is the reserved dummy
surfedges = []
faces = []           # (plane_id, side, firstedge, numedges)

def add_quad(quad_verts, plane_id, side):
    first = len(surfedges)
    for i in range(4):
        a = quad_verts[i]; b = quad_verts[(i+1) % 4]
        edges.append((a, b))
        surfedges.append(len(edges) - 1)   # forward edge reference
    faces.append((plane_id, side, first, 4))

# interior normals point into the room; `side`=0 face normal == plane normal.
add_quad((0,1,2,3), P_ZN, 0)   # floor, up (+z)  == plane +z
add_quad((7,6,5,4), P_ZP, 1)   # ceiling, down   opp plane +z
add_quad((4,5,1,0), P_YN, 0)   # -y wall, +y     == plane +y
add_quad((3,2,6,7), P_YP, 1)   # +y wall, -y     opp
add_quad((0,3,7,4), P_XN, 0)   # -x wall, +x     == plane +x
add_quad((5,6,2,1), P_XP, 1)   # +x wall, -x     opp

marksurfaces = list(range(len(faces)))   # empty leaf sees all 6 faces

# ---- hull0 node tree --------------------------------------------------------
# child encoding: >=0 node index; <0 -> leaf index = -(child)-1.
# leaf 0 = shared solid, leaf 1 = the room interior (empty).
SOLID = -1        # -(0)-1 == leaf 0
EMPTY = -2        # -(1)-1 == leaf 1
# nodes: (plane, child_front, child_back)
nodes = [
    (P_XP, SOLID, 1),   # x>256 solid, else ->
    (P_XN, 2, SOLID),   # x<-256 solid, else ->
    (P_YP, SOLID, 3),
    (P_YN, 4, SOLID),
    (P_ZP, SOLID, 5),
    (P_ZN, EMPTY, SOLID),  # inside -> empty leaf, below floor solid
]

# ---- clipnodes (hull1 player, hull2 large) ----------------------------------
# In clipnodes, negative children are contents values directly.
def hull_planes(inset_x, inset_z_floor, inset_z_ceil):
    xp = add_plane((1,0,0),  R-inset_x, 0)
    xn = add_plane((1,0,0), -(R-inset_x), 0)
    yp = add_plane((0,1,0),  R-inset_x, 1)
    yn = add_plane((0,1,0), -(R-inset_x), 1)
    zp = add_plane((0,0,1),  R-inset_z_ceil, 2)
    zn = add_plane((0,0,1), -(R-inset_z_floor), 2)
    return xp, xn, yp, yn, zp, zn

clipnodes = []
def add_hull(base, pl):
    xp, xn, yp, yn, zp, zn = pl
    b = base
    clipnodes.extend([
        (xp, CONTENTS_SOLID, b+1),
        (xn, b+2, CONTENTS_SOLID),
        (yp, CONTENTS_SOLID, b+3),
        (yn, b+4, CONTENTS_SOLID),
        (zp, CONTENTS_SOLID, b+5),
        (zn, CONTENTS_EMPTY, CONTENTS_SOLID),
    ])

# hull1 player mins(-16,-16,-24) maxs(16,16,32): inset x=16, floor=24, ceil=32
add_hull(0, hull_planes(16, 24, 32))
# hull2 large  mins(-32,-32,-24) maxs(32,32,64): inset x=32, floor=24, ceil=64
add_hull(6, hull_planes(32, 24, 64))
HULL1_HEAD, HULL2_HEAD = 0, 6

# ---- leafs ------------------------------------------------------------------
# leaf: contents i32, visofs i32, mins[3] i16, maxs[3] i16, firstms u16, numms u16, ambient[4] u8
leafs = [
    (CONTENTS_SOLID, -1, (0,0,0), (0,0,0), 0, 0),                 # leaf 0 solid
    (CONTENTS_EMPTY, -1, (-R,-R,-R), (R,R,R), 0, len(marksurfaces)),  # leaf 1 room
]

# ---- texinfo + miptex -------------------------------------------------------
# one texinfo: s=(1,0,0), t=(0,1,0), miptex 0
texinfos = [((1,0,0,0),(0,1,0,0), 0, 0)]

def build_miptex():
    name = b"ftetest\0\0\0\0\0\0\0\0\0"  # 16 bytes
    w = h = 16
    pixels = bytes([4]) * (w*h + (w//2)*(h//2) + (w//4)*(h//4) + (w//8)*(h//8))
    # miptex struct: name[16], width u32, height u32, offsets[4] u32, then pixels
    hdr_size = 16 + 4 + 4 + 16
    o1 = hdr_size
    o2 = o1 + w*h
    o3 = o2 + (w//2)*(h//2)
    o4 = o3 + (w//4)*(h//4)
    mip = name + struct.pack("<II", w, h) + struct.pack("<4I", o1,o2,o3,o4) + pixels
    # miptex lump: nummiptex i32, dataofs[nummiptex] i32, then miptex blobs
    numtex = 1
    lump_hdr = 4 + 4*numtex
    lump = struct.pack("<i", numtex) + struct.pack("<i", lump_hdr) + mip
    return lump

# ---- entities ---------------------------------------------------------------
entities = (
    '{\n'
    '"classname" "worldspawn"\n'
    '"message" "ftetest"\n'
    '"wad" ""\n'
    '}\n'
    '{\n'
    '"classname" "info_player_start"\n'
    '"origin" "0 0 -216"\n'
    '"angle" "0"\n'
    '}\n'
).encode('ascii') + b'\0'

# ---- models -----------------------------------------------------------------
# model: mins[3] f, maxs[3] f, origin[3] f, headnode[4] i32, visleafs i32, firstface i32, numfaces i32
models = [(
    (-R,-R,-R), (R,R,R), (0,0,0),
    (0, HULL1_HEAD, HULL2_HEAD, 0),
    1, 0, len(faces),
)]

# ---- serialise --------------------------------------------------------------
def pack_planes():
    b = b''
    for n, d, t in planes:
        b += struct.pack("<4fi", n[0], n[1], n[2], d, t)
    return b

def pack_vertexes():
    return b''.join(struct.pack("<3f", *v) for v in verts)

def pack_edges():
    return b''.join(struct.pack("<2H", a, b) for a, b in edges)

def pack_surfedges():
    return b''.join(struct.pack("<i", s) for s in surfedges)

def pack_faces():
    b = b''
    for plane_id, side, firstedge, numedges in faces:
        styles = bytes([0,255,255,255])  # one lightstyle, rest unused
        b += struct.pack("<HHiHH", plane_id, side, firstedge, numedges, 0)
        b += styles + struct.pack("<i", -1)  # lightofs -1 (fullbright)
    return b

def pack_texinfo():
    b = b''
    for s, t, miptex, flags in texinfos:
        b += struct.pack("<8f", *s, *t) + struct.pack("<ii", miptex, flags)
    return b

def pack_nodes():
    b = b''
    for plane, cf, cb in nodes:
        b += struct.pack("<i", plane)
        b += struct.pack("<hh", cf, cb)
        b += struct.pack("<3h", -R,-R,-R) + struct.pack("<3h", R,R,R)
        b += struct.pack("<HH", 0, 0)  # firstface, numfaces (faces via leaf)
    return b

def pack_clipnodes():
    return b''.join(struct.pack("<ihh", pl, cf, cb) for pl, cf, cb in clipnodes)

def pack_leafs():
    b = b''
    for contents, visofs, mins, maxs, firstms, numms in leafs:
        b += struct.pack("<ii", contents, visofs)
        b += struct.pack("<3h", *mins) + struct.pack("<3h", *maxs)
        b += struct.pack("<HH", firstms, numms)
        b += bytes([0,0,0,0])
    return b

def pack_marksurfaces():
    return b''.join(struct.pack("<H", m) for m in marksurfaces)

def pack_models():
    b = b''
    for mins, maxs, origin, head, visleafs, firstface, numfaces in models:
        b += struct.pack("<3f", *mins) + struct.pack("<3f", *maxs) + struct.pack("<3f", *origin)
        b += struct.pack("<4i", *head)
        b += struct.pack("<iii", visleafs, firstface, numfaces)
    return b

def build():
    lumps = [b''] * NUMLUMPS
    lumps[L_ENTITIES]     = entities
    lumps[L_PLANES]       = pack_planes()
    lumps[L_MIPTEX]       = build_miptex()
    lumps[L_VERTEXES]     = pack_vertexes()
    lumps[L_VISIBILITY]   = b''
    lumps[L_NODES]        = pack_nodes()
    lumps[L_TEXINFO]      = pack_texinfo()
    lumps[L_FACES]        = pack_faces()
    lumps[L_LIGHTING]     = b''
    lumps[L_CLIPNODES]    = pack_clipnodes()
    lumps[L_LEAFS]        = pack_leafs()
    lumps[L_MARKSURFACES] = pack_marksurfaces()
    lumps[L_EDGES]        = pack_edges()
    lumps[L_SURFEDGES]    = pack_surfedges()
    lumps[L_MODELS]       = pack_models()

    header_size = 4 + NUMLUMPS * 8
    body = b''
    offsets = []
    cursor = header_size
    for lump in lumps:
        # 4-byte align each lump
        pad = (-cursor) % 4
        if pad:
            body += b'\0' * pad; cursor += pad
        offsets.append((cursor, len(lump)))
        body += lump; cursor += len(lump)

    header = struct.pack("<i", BSPVERSION)
    for ofs, length in offsets:
        header += struct.pack("<ii", ofs, length)
    return header + body

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "ftetest.bsp"
    data = build()
    with open(out, "wb") as f:
        f.write(data)
    print(f"wrote {out}: {len(data)} bytes, "
          f"{len(planes)} planes, {len(nodes)} nodes, "
          f"{len(clipnodes)} clipnodes, {len(faces)} faces, {len(leafs)} leafs")
