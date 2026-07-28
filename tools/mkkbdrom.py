#!/usr/bin/env python3
"""Generate a functional Apple //e keyboard decoder ROM.

MAME's //e needs `341-0132-d.e12`, a 2K lookup table that turns a key matrix
position plus modifiers into ASCII.  Unlike the system ROMs, that dump is not
carried by any open-source project -- GitHub turns up references to it (MAME's
own source, Mednafen's documentation listing its SHA-256) but no copy.  With a
blank stand-in the machine boots and the keyboard is completely dead.

It does not have to be Apple's dump, though, because MAME uses it as a plain
lookup (see apple2e.cpp, ay3600_data_ready_w):

    address = key << 2 | !shift | !ctrl << 1 | !capslock << 9
    ascii   = kbdrom[address]

and the key number is just `row * 10 + column` (kb3600.cpp).  So the table can
be built from the published North American //e key matrix rather than copied.
This generates one that decodes correctly.

It will NOT match Apple's CRC, so MAME prints a checksum warning on start.
That is cosmetic: the keyboard works.  Drop a real dump in over the top if you
have one and the warning goes away.

    python3 tools/mkkbdrom.py roms/apple2ee/341-0132-d.e12
"""

import pathlib
import sys

ESC, TAB, CR, LF, BS, NAK, VT, DEL = 27, 9, 13, 10, 8, 21, 11, 127

# The North American //e key matrix, transcribed from MAME's own PORT_CHAR
# assignments in apple2e.cpp -- not from the ASCII-art comment above them,
# which disagrees about N and M.  The ports are what MAME actually scans, and
# they are the contract between a host keypress and a matrix position, so the
# table has to agree with them or keys come out as their neighbours.
#
# 5/6 and T/Y really do sit in swapped columns; that part is the real wiring.
# Each entry is (unshifted, shifted); None is a position with no key.
MATRIX = [
    # X0
    [(ESC, ESC), ('1', '!'), ('2', '@'), ('3', '#'), ('4', '$'),
     ('6', '^'), ('5', '%'), ('7', '&'), ('8', '*'), ('9', '(')],
    # X1
    [(TAB, TAB), ('q', 'Q'), ('w', 'W'), ('e', 'E'), ('r', 'R'),
     ('y', 'Y'), ('t', 'T'), ('u', 'U'), ('i', 'I'), ('o', 'O')],
    # X2
    [('a', 'A'), ('d', 'D'), ('s', 'S'), ('h', 'H'), ('f', 'F'),
     ('g', 'G'), ('j', 'J'), ('k', 'K'), (';', ':'), ('l', 'L')],
    # X3
    [('z', 'Z'), ('x', 'X'), ('c', 'C'), ('v', 'V'), ('b', 'B'),
     ('n', 'N'), ('m', 'M'), (',', '<'), ('.', '>'), ('/', '?')],
    # X4
    [None] * 6 + [('\\', '|'), ('=', '+'), ('0', ')'), ('-', '_')],
    # X5
    [None] * 6 + [('`', '~'), ('p', 'P'), ('[', '{'), (']', '}')],
    # X6
    [None] * 6 + [(CR, CR), (VT, VT), (' ', ' '), ("'", '"')],
    # X7
    # MAME gives the DELETE position PORT_CHAR(8), so that is what the host
    # backspace key lands on; matching it keeps GETLN's line editing working.
    [None] * 6 + [(BS, BS), (LF, LF), (BS, BS), (NAK, NAK)],
    # X8 -- scanned but unpopulated on a //e
    [None] * 10,
]


def code(entry):
    return entry if isinstance(entry, int) else ord(entry)


def main(argv):
    if len(argv) != 2:
        print(__doc__)
        return 2

    rom = bytearray(2048)
    keys = 0
    for row, cells in enumerate(MATRIX):
        for col, cell in enumerate(cells):
            if cell is None:
                continue
            keys += 1
            key = row * 10 + col
            plain, shifted = (code(c) for c in cell)
            # The three modifier bits are all active low: a 1 means the
            # modifier is NOT being held.
            for caps in (0, 1):
                for ctrl in (0, 1):
                    for shift in (0, 1):
                        ch = plain if shift else shifted
                        if not caps and 0x61 <= ch <= 0x7A:
                            ch -= 0x20              # caps lock engaged
                        if not ctrl:
                            upper = ch - 0x20 if 0x61 <= ch <= 0x7A else ch
                            if 0x40 <= upper <= 0x5F:
                                ch = upper & 0x1F   # ctrl folds @ through _
                        rom[(key << 2) | shift | (ctrl << 1) | (caps << 9)] = ch

    # Bit 10 selects an alternate language layout; mirror the US table into it
    # so a stray selection cannot produce a dead keyboard.
    rom[1024:2048] = rom[0:1024]

    dst = pathlib.Path(argv[1])
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_bytes(bytes(rom))
    print(f"wrote {dst}: {keys} keys, {len(rom)} bytes "
          f"(generated -- MAME will warn about the checksum)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
