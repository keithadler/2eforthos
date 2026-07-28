#!/usr/bin/env python3
"""Rebuild the MAME ROM set for the Apple ][+ from open-source projects.

MAME ships no Apple ROMs, and this repository does not carry them either.
Everything needed is reconstructible from two GPL projects:

  AppleWin   the six 2K system ROMs (as one 12K image), the character
             generator, and the Disk II boot PROM
  apple2js   the Disk II logic-state sequencer, transcribed from
             "Understanding the Apple IIe" rather than dumped

Every file is checked against the CRC32 MAME expects, so a mismatch is a hard
error rather than a subtly broken emulator.

    python3 tools/fetch-roms.py [--dest roms]
"""

import argparse
import itertools
import pathlib
import re
import sys
import urllib.request
import zlib

APPLEWIN = "https://raw.githubusercontent.com/AppleWin/AppleWin/master/resource/"
APPLE2JS = "https://raw.githubusercontent.com/whscullin/apple2js/main/js/cards/disk2.ts"

# name -> expected CRC32, exactly as MAME lists them for `apple2p`
SYSTEM_ROMS = [
    ("341-0011.d0",    0x6F05F949),
    ("341-0012.d8",    0x1F08087C),
    ("341-0013.e0",    0x2B8D9A89),
    ("341-0014.e8",    0x5719871A),
    ("341-0015.f0",    0x9A04EECF),
    ("341-0020-00.f8", 0x079589C4),
]
CHARGEN_CRC   = 0x64F415C6      # 341-0036.chr
DISKII_CRC    = 0xCE7144F6      # 341-0027-a.p5, the boot PROM
SEQUENCER_CRC = 0xB72A2C70      # 341-0028-a.rom, the P6 state machine


def crc(data: bytes) -> int:
    return zlib.crc32(data) & 0xFFFFFFFF


def fetch(url: str) -> bytes:
    print(f"  fetching {url.rsplit('/', 1)[-1]}")
    with urllib.request.urlopen(url, timeout=60) as response:
        return response.read()


def write(path: pathlib.Path, data: bytes, expected: int) -> bool:
    got = crc(data)
    ok = got == expected
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    print(f"  {'ok ' if ok else 'BAD'} {path.name:16} crc={got:08x} want={expected:08x}")
    return ok


def sequencer_rom(source: str) -> bytes:
    """Recover the P6 sequencer PROM from apple2js's lookup table.

    apple2js indexes the table by (state, input) for its own convenience; the
    physical PROM wires those bits to its address lines in a different order.
    The contents are the same dump, so the right permutation is found by
    trying all 8! orderings and keeping the one whose CRC matches MAME.
    """
    match = re.search(r"const SEQUENCER_ROM_16\s*=\s*\[(.*?)\];", source, re.S)
    if not match:
        raise SystemExit("could not find SEQUENCER_ROM_16 in apple2js")
    body = re.sub(r"//[^\n]*", "", match.group(1))
    values = [int(b, 16) for b in re.findall(r"0x([0-9A-Fa-f]{2})", body)]
    if len(values) != 256:
        raise SystemExit(f"expected 256 sequencer bytes, got {len(values)}")

    for perm in itertools.permutations(range(8)):
        out = bytearray(256)
        for addr in range(256):
            scrambled = 0
            for bit, dest in enumerate(perm):
                if addr >> bit & 1:
                    scrambled |= 1 << dest
            out[addr] = values[scrambled]
        if crc(out) == SEQUENCER_CRC:
            print(f"  address-line order {perm}")
            return bytes(out)
    raise SystemExit("no address-line permutation reproduced the MAME dump")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dest", default="roms", type=pathlib.Path)
    args = parser.parse_args()
    dest = args.dest
    good = True

    print("Apple ][+ system ROMs (AppleWin):")
    system = fetch(APPLEWIN + "Apple2_Plus.rom")
    if len(system) != 12288:
        raise SystemExit(f"Apple2_Plus.rom should be 12288 bytes, got {len(system)}")
    for index, (name, want) in enumerate(SYSTEM_ROMS):
        chunk = system[index * 2048:(index + 1) * 2048]
        good &= write(dest / "apple2p" / name, chunk, want)

    good &= write(dest / "apple2p" / "341-0036.chr",
                  fetch(APPLEWIN + "Apple2_Video.rom"), CHARGEN_CRC)

    print("Disk II controller:")
    good &= write(dest / "a2diskiing" / "341-0027-a.p5",
                  fetch(APPLEWIN + "DISK2.rom"), DISKII_CRC)

    print("Disk II sequencer (apple2js):")
    good &= write(dest / "d2fdc" / "341-0028-a.rom",
                  sequencer_rom(fetch(APPLE2JS).decode("utf-8", "replace")),
                  SEQUENCER_CRC)

    if not good:
        print("\nAt least one ROM did not match. Refusing to call this a good set.")
        return 1
    print(f"\nAll ROMs match MAME's CRCs. Check with:\n"
          f"  mame -rompath {dest} -verifyroms apple2p")
    return 0


if __name__ == "__main__":
    sys.exit(main())
