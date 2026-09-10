#!/usr/bin/env python3
"""Export the rectilinear prototype enclosure as dependency-free binary STL files."""

from pathlib import Path
import struct

OUT = Path(__file__).resolve().parent / "stl"


def body_voxels():
    filled = set()
    for x in range(100):
        for y in range(72):
            for z in range(28):
                shell = x < 3 or x >= 97 or y < 3 or y >= 69 or z < 3
                screen_cut = 13 <= x < 87 and 11 <= y < 61 and z < 4
                cable_cut = x >= 96 and 27 <= y < 45 and 10 <= z < 20
                vent_cut = (y < 4 or y >= 68) and 12 <= z < 20 and any(a <= x < a + 5 for a in range(12, 83, 10))
                if shell and not screen_cut and not cable_cut and not vent_cut:
                    filled.add((x, y, z))
    return filled


def back_voxels():
    filled = set()
    for x in range(95):
        for y in range(67):
            for z in range(4):
                vent = z < 2 and 18 <= x < 74 and 16 <= y < 46 and (x - 18) % 8 < 4
                ribs = z >= 2 and (y in (3, 63)) and 3 <= x < 92
                if (z < 2 and not vent) or ribs:
                    filled.add((x, y, z))
    return filled


def stand_voxels():
    filled = set()
    boxes = [
        (0, 80, 0, 34, 0, 4),
        (8, 16, 5, 29, 4, 26),
        (64, 72, 5, 29, 4, 26),
        (8, 72, 5, 29, 22, 26),
    ]
    for x0, x1, y0, y1, z0, z1 in boxes:
        for x in range(x0, x1):
            for y in range(y0, y1):
                for z in range(z0, z1):
                    filled.add((x, y, z))
    return filled


FACES = [
    ((-1, 0, 0), ((0, 0, 0), (0, 0, 1), (0, 1, 1), (0, 1, 0))),
    ((1, 0, 0), ((1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1))),
    ((0, -1, 0), ((0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1))),
    ((0, 1, 0), ((0, 1, 0), (0, 1, 1), (1, 1, 1), (1, 1, 0))),
    ((0, 0, -1), ((0, 0, 0), (0, 1, 0), (1, 1, 0), (1, 0, 0))),
    ((0, 0, 1), ((0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1))),
]


def triangles(voxels):
    for x, y, z in voxels:
        for (dx, dy, dz), corners in FACES:
            if (x + dx, y + dy, z + dz) in voxels:
                continue
            points = [(x + px, y + py, z + pz) for px, py, pz in corners]
            yield points[0], points[1], points[2]
            yield points[0], points[2], points[3]


def write_stl(name, voxels):
    tris = list(triangles(voxels))
    OUT.mkdir(exist_ok=True)
    path = OUT / f"bar-boy-{name}.stl"
    with path.open("wb") as stream:
        stream.write(f"MOMO LABZ {name}".encode().ljust(80, b"\0"))
        stream.write(struct.pack("<I", len(tris)))
        for triangle in tris:
            stream.write(struct.pack("<3f", 0, 0, 0))
            for point in triangle:
                stream.write(struct.pack("<3f", *point))
            stream.write(struct.pack("<H", 0))
    print(f"{path.name}: {len(tris)} triangles")


if __name__ == "__main__":
    write_stl("body", body_voxels())
    write_stl("back", back_voxels())
    write_stl("stand", stand_voxels())
