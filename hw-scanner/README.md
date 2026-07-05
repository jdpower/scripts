# Useful shell scripts

## hwinfo.sh

A shell script to display hardware and system information.

> **Linux only.** This script relies on Linux-specific interfaces (`/proc`, `/sys`, `dmidecode`, `lsblk`, `ip`, etc.) and will not work on macOS or Windows.
>
> Tested on Debian-based distros (Ubuntu, Debian, Raspberry Pi OS, etc.).

### Usage

```bash
./hwinfo.sh              # run all sections
./hwinfo.sh -c           # CPU only
./hwinfo.sh -c -r        # CPU and RAM
./hwinfo.sh -h           # help
```

### Flags

| Flag | Section |
|------|---------|
| `-o` | Operating System |
| `-c` | CPU / Processor |
| `-r` | Memory (RAM & Swap) |
| `-s` | Storage |
| `-n` | Network |
| `-g` | GPU / Graphics |
| `-h` | Help |
