#!/usr/bin/env python3
# gen_assets.py -- emit trivial, valid, ORIGINAL Quake assets for the fixture:
#   progs/ftetest.mdl   a 1-triangle alias model (IDPO v6)
#   progs/ftetest.spr   a 1-frame 4x4 sprite     (IDSP v1)
#   sound/ftetest.wav   a 0.1s 11025Hz mono tone (RIFF/PCM)
#
# These let the behavioural test exercise the server-side model/sprite/sound
# precache paths (precache_model actually loads the model on the server) without
# shipping any id Software content. 100% original authorship.
#
# Formats per the Unofficial Quake specs (modelgen.h / spritegn.h) and RIFF/WAVE.
# SPDX-License-Identifier: GPL-2.0-or-later

import os, struct, sys, math

# --- alias model (.mdl, IDPO v6) --------------------------------------------
def build_mdl():
    # byte-packed vertices decode as real = v*scale + origin; pick a 32u cube.
    origin = (-16.0, -16.0, -16.0)
    scale  = (32.0/255.0, 32.0/255.0, 32.0/255.0)

    def to_byte(real, o, s):
        return max(0, min(255, int(round((real - o) / s))))

    # one upright triangle around the origin
    real_verts = [(0, 0, 16), (-16, 0, -16), (16, 0, -16)]
    tv = []  # trivertx: (bx,by,bz,normalindex)
    for (x, y, z) in real_verts:
        tv.append((to_byte(x, origin[0], scale[0]),
                   to_byte(y, origin[1], scale[1]),
                   to_byte(z, origin[2], scale[2]), 0))

    skinw, skinh = 2, 2
    numskins, numverts, numtris, numframes = 1, 3, 1, 1

    hdr = struct.pack(
        "<4s i 3f 3f f 3f i i i i i i i i f",
        b"IDPO", 6,
        scale[0], scale[1], scale[2],
        origin[0], origin[1], origin[2],
        64.0,                       # boundingradius
        0.0, 0.0, 0.0,              # eyeposition
        numskins, skinw, skinh,
        numverts, numtris, numframes,
        0,                          # synctype
        0,                          # flags
        16.0)                       # size

    body = b""
    # skins: type(0=single) + skinw*skinh index bytes
    body += struct.pack("<i", 0) + bytes([4]) * (skinw * skinh)
    # stverts: onseam, s, t
    st = [(0, 0, 0), (0, skinw - 1, 0), (0, 0, skinh - 1)]
    for onseam, s, t in st:
        body += struct.pack("<iii", onseam, s, t)
    # triangles: facesfront, vertindex[3]
    body += struct.pack("<i iii", 1, 0, 1, 2)
    # frames: type(0=single), bboxmin, bboxmax, name[16], verts[numverts]
    body += struct.pack("<i", 0)
    body += bytes([0, 128, 0, 0])          # bboxmin trivertx
    body += bytes([255, 128, 255, 0])      # bboxmax trivertx
    body += b"frame0".ljust(16, b"\0")
    for (bx, by, bz, n) in tv:
        body += bytes([bx, by, bz, n])
    return hdr + body

# --- sprite (.spr, IDSP v1) --------------------------------------------------
def build_spr():
    w, h, numframes = 4, 4, 1
    hdr = struct.pack(
        "<4s i i f i i i f i",
        b"IDSP", 1,
        3,          # type: VP_PARALLEL (faces viewer)
        8.0,        # boundingradius
        w, h,       # maxwidth, maxheight
        numframes,
        0.0,        # beamlength
        0)          # synctype
    body = b""
    # frame: type(0=single); origin[2], width, height; w*h index bytes
    body += struct.pack("<i", 0)
    body += struct.pack("<ii", -(w // 2), h // 2)   # origin
    body += struct.pack("<ii", w, h)
    body += bytes([4]) * (w * h)
    return hdr + body

# --- sound (.wav, RIFF/PCM 16-bit mono) --------------------------------------
def build_wav():
    rate, bits, chans = 11025, 16, 1
    dur = 0.1
    nsamp = int(rate * dur)
    samples = b"".join(
        struct.pack("<h", int(8000 * math.sin(2 * math.pi * 440 * i / rate)))
        for i in range(nsamp))
    byte_rate = rate * chans * bits // 8
    block_align = chans * bits // 8
    fmt = struct.pack("<4sIHHIIHH", b"fmt ", 16, 1, chans, rate,
                      byte_rate, block_align, bits)
    data = struct.pack("<4sI", b"data", len(samples)) + samples
    riff = struct.pack("<4sI4s", b"RIFF", 4 + len(fmt) + len(data), b"WAVE")
    return riff + fmt + data

def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    outputs = {
        os.path.join(root, "progs", "ftetest.mdl"): build_mdl(),
        os.path.join(root, "progs", "ftetest.spr"): build_spr(),
        os.path.join(root, "sound", "ftetest.wav"): build_wav(),
    }
    for path, data in outputs.items():
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(data)
        print(f"wrote {path}: {len(data)} bytes")

if __name__ == "__main__":
    main()
