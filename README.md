# lilith


A POSIX-like x86-64 kernel and userspace written in Crystal.

## Screenshot

![screenshot](https://raw.githubusercontent.com/ffwff/lilith/master/img/screenshot23.png "screenshot of lilith")

## Building

lilith needs to be compiled with a patched crystal compiler, to build it, run the command:

```
make toolchain/crystal/.build/crystal
```

You will also need an appropriate `x86_64-elf` binutils toolchain in order to link and assemble the kernel, as well as `i686-elf` binutils to build the bootstrap code.

```
make build/kernel
```

### Building the userspace

A Makefile is provided for building the userspace toolchain, to build it, go to the `userspace/toolchain` directory and use `make`.

Once built, a patched version of GCC/Binutils will be installed in `userspace/toolchain/tools/bin`, simply set your PATH variable to that location and you can use the toolchain (with the `i386-elf-lilith` or `x86_64-elf-lilith` prefix).

After building the toolchain, set the necessary environment variables by doing:

```
source ./env.sh
```

To compile C programs for the system, you'll also need to build the libc:

```
./pkgs/missio build libc
```

## Running

A CPU with x64 support is required to run the OS. The Makefile provides a script which will run QEMU on the kernel:

```
make run
```

To run with storage, an MBR-formatted hard drive image with a FAT16 partition must be provided in the running directory with the name `drive.img`. The kernel will automatically boot the `main.bin` executable on the hard drive, or panic if it can't be loaded.

```
make run_img
```

## Features

* Basic x86-64 support
* Hybrid conservative-precise incremental garbage collector
* IDE/ATA support (well, it can only load from primary master)
* FAT16 support
* Unix syscalls (open, read, write, spawn,...)
* Preemptive multitasking!
* Userspace C library written in Crystal (mostly)
* A window manager and some graphical programs (terminal emulator, file manager)
* And much more as I go...

## License

Lilith is licensed under MIT. See LICENSE for more details.
