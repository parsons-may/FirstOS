#!/usr/bin/env python3

from __future__ import annotations

import math
import pathlib
import struct
import sys

SECTOR_SIZE = 512
TOTAL_SECTORS = 2880
RESERVED_SECTORS = 16
NUM_FATS = 2
SECTORS_PER_FAT = 9
ROOT_ENTRIES = 224
ROOT_DIR_SECTORS = (ROOT_ENTRIES * 32 + SECTOR_SIZE - 1) // SECTOR_SIZE
DATA_START_SECTOR = RESERVED_SECTORS + NUM_FATS * SECTORS_PER_FAT + ROOT_DIR_SECTORS
MAX_KERNEL_SECTORS = RESERVED_SECTORS - 1


def to_fat_name(name: str) -> bytes:
    path = pathlib.Path(name)
    stem = path.stem.upper()
    suffix = path.suffix[1:].upper()
    if not stem or len(stem) > 8 or len(suffix) > 3:
        raise ValueError(f"{name} is not a valid 8.3 filename")
    return stem.ljust(8).encode("ascii") + suffix.ljust(3).encode("ascii")


def set_fat12_entry(fat: bytearray, cluster: int, value: int) -> None:
    offset = cluster + cluster // 2
    if cluster & 1:
        current = fat[offset] | (fat[offset + 1] << 8)
        current = (current & 0x000F) | ((value & 0x0FFF) << 4)
    else:
        current = fat[offset] | (fat[offset + 1] << 8)
        current = (current & 0xF000) | (value & 0x0FFF)
    fat[offset] = current & 0xFF
    fat[offset + 1] = (current >> 8) & 0xFF


def collect_files(fs_dir: pathlib.Path) -> list[tuple[pathlib.Path, bytes]]:
    files = []
    for path in sorted(fs_dir.iterdir()):
        if path.is_file():
            files.append((path, path.read_bytes()))
    return files


def build_image(boot_path: pathlib.Path, kernel_path: pathlib.Path, fs_dir: pathlib.Path, out_path: pathlib.Path) -> None:
    boot = boot_path.read_bytes()
    kernel = kernel_path.read_bytes()
    files = collect_files(fs_dir)

    if len(boot) != SECTOR_SIZE:
        raise ValueError("boot sector must be exactly 512 bytes")

    kernel_sectors = math.ceil(len(kernel) / SECTOR_SIZE)
    if kernel_sectors > MAX_KERNEL_SECTORS:
        raise ValueError(f"kernel is too large: {kernel_sectors} sectors, max is {MAX_KERNEL_SECTORS}")

    image = bytearray(SECTOR_SIZE * TOTAL_SECTORS)
    image[:SECTOR_SIZE] = boot
    image[SECTOR_SIZE : SECTOR_SIZE + len(kernel)] = kernel

    fat = bytearray(SECTORS_PER_FAT * SECTOR_SIZE)
    fat[0:3] = b"\xF0\xFF\xFF"
    root_dir = bytearray(ROOT_DIR_SECTORS * SECTOR_SIZE)

    next_cluster = 2
    data_cursor = DATA_START_SECTOR * SECTOR_SIZE

    for index, (path, data) in enumerate(files):
        name = to_fat_name(path.name)
        entry = bytearray(32)
        entry[0:11] = name
        entry[11] = 0x20

        cluster_count = max(1, math.ceil(len(data) / SECTOR_SIZE))
        first_cluster = next_cluster

        for chunk_index in range(cluster_count):
            cluster = next_cluster + chunk_index
            last_cluster = chunk_index == cluster_count - 1
            set_fat12_entry(fat, cluster, 0xFFF if last_cluster else cluster + 1)

            start = chunk_index * SECTOR_SIZE
            end = start + SECTOR_SIZE
            chunk = data[start:end]
            image[data_cursor : data_cursor + len(chunk)] = chunk
            data_cursor += SECTOR_SIZE

        entry[26:28] = struct.pack("<H", first_cluster)
        entry[28:32] = struct.pack("<I", len(data))
        root_dir[index * 32 : (index + 1) * 32] = entry
        next_cluster += cluster_count

    fat1_offset = RESERVED_SECTORS * SECTOR_SIZE
    fat2_offset = fat1_offset + SECTORS_PER_FAT * SECTOR_SIZE
    root_offset = (RESERVED_SECTORS + NUM_FATS * SECTORS_PER_FAT) * SECTOR_SIZE
    image[fat1_offset : fat1_offset + len(fat)] = fat
    image[fat2_offset : fat2_offset + len(fat)] = fat
    image[root_offset : root_offset + len(root_dir)] = root_dir

    out_path.write_bytes(image)


def main(argv: list[str]) -> int:
    if len(argv) != 5:
        print("usage: build_image.py boot.bin kernel.bin fs_dir output.img", file=sys.stderr)
        return 1

    build_image(pathlib.Path(argv[1]), pathlib.Path(argv[2]), pathlib.Path(argv[3]), pathlib.Path(argv[4]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
