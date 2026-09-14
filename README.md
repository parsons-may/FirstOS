# FirstOS

FirstOS is a bootable operating-system project written in 16-bit x86 assembly. It boots from a FAT12 disk image in QEMU, loads a custom kernel, and provides an interactive command shell with ten built-in commands:

- `HELP`
- `CLS`
- `VER`
- `REBOOT`
- `LIST`
- `TYPE`
- `RENAME`
- `DELETE`
- `ABOUT`
- `ECHO`

## Requirements

- `nasm`
- `qemu-system-i386`
- `make`

## Build

```bash
make
```

This creates a bootable FAT12 floppy image at `build/firstos.img`.

## Run

```bash
make run
```

## How it works

- `boot.asm` is the boot sector. It includes a FAT12 BIOS Parameter Block and
  loads the next 15 reserved sectors into memory as the kernel.
- `kernel.asm` is the tiny shell kernel that reads keyboard input, lists the
  FAT12 root directory, can print a file with `TYPE`, rename files with
  `RENAME`, and delete files with `DELETE`.
- `build_image.py` creates a deterministic floppy image with FAT tables, a root
  directory, and sample text files from `fs/`.

## Notes

- Commands are case-insensitive because input is normalized to uppercase.
- `LIST` now reads actual directory entries from the root of the floppy image.
- `TYPE README.TXT` reads a real file by following the FAT12 cluster chain.
- `RENAME OLD.TXT NEW.TXT` updates the FAT12 root-directory entry in place.
- `DELETE HELLO.TXT` marks the directory entry deleted and frees its FAT chain.
- This is BIOS-based real mode code, so it is meant for emulators like QEMU.

## Demo

FirstOS running in QEMU with its interactive command shell and FAT12 file operations.

<img width="716" height="427" alt="Screenshot 2026-09-14 at 1 42 10 PM" src="https://github.com/user-attachments/assets/d465eac9-102f-4262-8700-cfe77779825e" />
