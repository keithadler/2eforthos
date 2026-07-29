#!/usr/bin/env python3
"""Lay the boot loader and the kernel onto a disk image at fixed sectors.

There is no DOS on this disk.  Track 0 holds the boot loader, which the
controller's PROM loads for us, and the kernel follows from track 1.  The
DOS 3.3 filesystem is still there from track 17 onwards, because the explorer
reads that catalog -- what has gone is DOS itself.

The one thing that would silently scramble everything: a .dsk stores sectors
in DOS *logical* order, while the driver matches the *physical* sector number
written in each address field.  DOS's skew maps between the two, so a chunk
destined for physical sector P is written at logical position SKEW[P].  Get
this wrong and every sector still reads back cleanly, just in the wrong order.

    python3 tools/mkdisk.py disk.dsk boot1.bin forth.bin [interleave [src.bin]]

The last argument is the system's own Forth source, which the kernel streams
a sector at a time rather than carrying in its image.  It goes at SRCTRACK,
consecutively: a sector takes about a second to compile and the disk turns
five times in that, so spacing them out would buy nothing.
"""

import pathlib
import sys

SECTOR = 256
SECTORS = 16

# physical sector -> logical position in a DOS-order image
PHYS_TO_LOGICAL = [0, 7, 14, 6, 13, 5, 12, 4, 11, 3, 10, 2, 9, 1, 8, 15]

VTOC_TRACK, VTOC_SECTOR = 17, 0
VTOC_BITMAP = 0x38                      # four bytes per track, a set bit = free


def put(img, track, phys, data):
    off = (track * SECTORS + PHYS_TO_LOGICAL[phys]) * SECTOR
    img[off:off + SECTOR] = data.ljust(SECTOR, b"\x00")


def mark_used(img, track):
    off = (VTOC_TRACK * SECTORS + VTOC_SECTOR) * SECTOR + VTOC_BITMAP + track * 4
    img[off] = 0
    img[off + 1] = 0


def lay(img, image_bytes, track, label, interleave=1):
    """Write a whole image from `track` onward.

    interleave is the step the reader takes between successive sectors.  The
    boot loader reads the kernel three apart, because decoding a sector takes
    longer than the gap to the next one; consecutive placement would cost a
    whole revolution per sector.  The PROM reads the boot block itself
    consecutively, so that one stays at interleave 1.
    """
    chunks = [image_bytes[i:i + SECTOR] for i in range(0, len(image_bytes), SECTOR)]
    for index, chunk in enumerate(chunks):
        within = index % SECTORS
        put(img, track + index // SECTORS, (within * interleave) % SECTORS, chunk)
    last = track + (len(chunks) - 1) // SECTORS
    for t in range(track, last + 1):
        mark_used(img, t)
    print(f"  {label}: {len(chunks)} sectors, tracks {track}-{last}")
    return len(chunks)


SRCTRACK = 8            # must match tools/mkboot.py
RESERVED = 11           # tracks 0-10: boot loader, kernel, and the source


def reserve(disk, last):
    """Mark tracks 0..last used, before the filesystem allocates anything.

    The boot loader, the kernel and the system's own source are laid at fixed
    sectors, outside the filesystem entirely -- but the filesystem does not
    know that, and DOS will happily put a file wherever the VTOC says is
    free.  Marking them used first is what keeps the two from writing over
    each other.  Doing it afterwards, which is what used to happen, sets the
    bitmap right and leaves the file already written underneath the kernel.
    """
    img = bytearray(disk.read_bytes())
    for track in range(last + 1):
        mark_used(img, track)
    disk.write_bytes(bytes(img))
    print(f"  reserved tracks 0-{last} before the filesystem was filled")


def main(argv):
    if len(argv) == 4 and argv[1] == "--reserve":
        reserve(pathlib.Path(argv[2]), int(argv[3]))
        return 0
    if len(argv) not in (4, 5, 6):
        print(__doc__)
        return 2
    disk = pathlib.Path(argv[1])
    img = bytearray(disk.read_bytes())
    if len(img) != 35 * SECTORS * SECTOR:
        raise SystemExit(f"expected a 143360-byte image, got {len(img)}")

    print("laying out:")
    boot = pathlib.Path(argv[2]).read_bytes()
    lay(img, boot, 0, "boot loader")
    kernel = pathlib.Path(argv[3]).read_bytes()
    step = int(argv[4]) if len(argv) >= 5 else 3
    used = lay(img, kernel, 1, "kernel", interleave=step)
    if used > SRCTRACK * SECTORS:
        raise SystemExit(f"kernel is {used} sectors and runs into the source "
                         f"at track {SRCTRACK}")
    if len(argv) == 6:
        source = pathlib.Path(argv[5]).read_bytes()
        lay(img, source, SRCTRACK, "boot source", interleave=1)

    disk.write_bytes(bytes(img))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
