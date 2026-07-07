#!/usr/bin/env python3
# gen_bad.py -- derive the malformed fixtures used by the graceful-failure lanes
# from the freshly-built good artifacts, so they never go stale:
#   maps/badver.bsp    good BSP with the version dword corrupted
#   maps/trunc.bsp     good BSP truncated mid-lump
#   bad/badprogs.dat   good progs with the version dword corrupted + truncated
#   bad/junkprogs.dat  non-progs garbage
#
# All derived from our own original content; no id Software data involved.
# SPDX-License-Identifier: GPL-2.0-or-later

import os, struct, sys

def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    bsp = os.path.join(root, "maps", "ftetest.bsp")
    dat = os.path.join(root, "progs.dat")
    os.makedirs(os.path.join(root, "bad"), exist_ok=True)

    good_bsp = open(bsp, "rb").read()
    open(os.path.join(root, "maps", "badver.bsp"), "wb").write(
        struct.pack("<i", 99) + good_bsp[4:])
    open(os.path.join(root, "maps", "trunc.bsp"), "wb").write(good_bsp[:200])

    good_dat = open(dat, "rb").read()
    open(os.path.join(root, "bad", "badprogs.dat"), "wb").write(
        struct.pack("<i", 99) + good_dat[4:200])
    open(os.path.join(root, "bad", "junkprogs.dat"), "wb").write(
        b"NOTAPROGS" + bytes(64))

    print("wrote maps/{badver,trunc}.bsp, bad/{badprogs,junkprogs}.dat")

if __name__ == "__main__":
    main()
