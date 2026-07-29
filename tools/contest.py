#!/usr/bin/env python3
"""Run the console tests.

Each test types Forth at the prompt and then asserts against machine state --
the data stack, a variable's cell, a stretch of the graphics screen.  Checking
state rather than the screen is what makes these worth having: a screenshot
tells you something changed, the stack tells you what the system believes.

    python3 tools/contest.py            run everything
    python3 tools/contest.py arith      run named tests
    python3 tools/contest.py --list
"""

import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DISK = ROOT / "build" / "run.dsk"
LBL  = ROOT / "build" / "forth.lbl"
ZP   = ROOT / "src" / "zp.inc"

# Raster row 96 of the hi-res screen, which is where the line tests draw:
# $2000 + $400*(96 mod 8) + $80*((96/8) mod 8) + $28*(96/64)
ROW96 = 0x2228

# Scratch for the memory tests.  $0D00-$0FFF is the only RAM the system
# leaves alone: the sector buffers end at $0CFF and the catalog starts at
# $1000.  Anything above the kernel is dictionary and moves as the system
# grows -- which is how these tests broke the first time.

TESTS = {

"boot": """
    check NFILE 22
    depth 0
""",

"arith": """
    type 2 3 +
    stack 5
    type 7 *
    stack 35
    type 100 SWAP -
    stack 65
    type DUP DUP + SWAP -
    stack 65
""",

# Division is unsigned and comes as a pair, so both halves get checked.
"division": """
    type 17 5 /MOD
    stack 3 2
    type 2DROP 1000 7 /
    stack 142
    type DROP 1000 7 MOD
    stack 6
""",

"stack-words": """
    type 1 2 3
    stack 3 2 1
    type ROT
    stack 1 3 2
    type NIP
    stack 1 2
    type OVER
    stack 2 1 2
    type DEPTH
    stack 3 2 1 2
""",

"compare": """
    type 3 4 <
    stack -1
    type DROP 4 3 <
    stack 0
    type DROP 5 5 =
    stack -1
    type DROP -7 ABS
    stack 7
    type DROP 3 9 MIN 4 2 MAX
    stack 4 3
""",

# A definition made at the prompt has to survive and run.
"colon": """
    type : SQ DUP * ;
    type 12 SQ
    stack 144
    type : CUBE DUP SQ * ;
    type 5 CUBE
    stack 125 144
""",

"loops": """
    type : SUMN 0 SWAP 0 DO I + LOOP ;
    type 10 SUMN
    stack 45
    type : CNT 0 BEGIN 1+ DUP 7 < 0= UNTIL ;
    type CNT
    stack 7 45
""",

"variables": """
    type VARIABLE FOO 42 FOO !
    type FOO @
    stack 42
    type DROP 8 FOO +! FOO @
    stack 50
    check FOO 50
""",

# The catalog is read from the disk at boot, not compiled in.
"catalog": """
    check NFILE 22
    type NFILE @
    stack 22
    clear
    type FREE
    wait 240
    depth 1
""",

# The graphics screen is a thing the language turns on, and comes back from.
"graphics": """
    type HGR
    mem 2228 0
    type HCLS
    mem 2228 0
    type 3 HCOLOR 0 559 96 HLINE
    nonzero 2228 40
    type TEXT
    type 6 7 *
    stack 42
    shot
""",

# Drawing the same shape twice in XOR mode has to leave the screen alone.
"xor": """
    type HGR HCLS
    mem 2228 0
    type 3 HCOLOR -1 HXOR
    type 100 200 96 HLINE
    nonzero 2228 40
    type 100 200 96 HLINE
    mem 2228 0
    type 0 HXOR TEXT
""",

"shapes": """
    type HGR HCLS 3 HCOLOR
    type 40 200 40 120 HFRAME
    nonzero 2228 40
    type HCLS 280 96 60 HCIRCLE
    nonzero 2228 40
    type HCLS 280 96 60 HDISC
    nonzero 2228 40
    type TEXT
""",

# A line that pops more than it pushes must be caught, not left to run wild.
"underflow": """
    type 1 2 3
    stack 3 2 1
    type DROP DROP DROP DROP DROP
    depth 0
    type 9 9 +
    stack 18
""",

# The console commands have to leave nothing on the stack behind them.
"commands": """
    type CAT
    wait 600
    depth 0
    shot
    type HELP
    wait 600
    depth 0
    shot
    type 99 LOCK
    wait 240
    depth 0
""",

# ud is two cells, low pushed first, so the high cell is the one on top.
"um-star": """
    type 10 20 UM*
    stack 0 200
    type 2DROP 65535 65535 UM*
    stack -2 1
    type 2DROP 1000 1000 UM*
    stack 15 16960
""",

"um-slash-mod": """
    type 200 0 20 UM/MOD
    stack 10 0
    type 2DROP 16960 15 1000 UM/MOD
    stack 1000 0
    type 2DROP 7 0 2 UM/MOD
    stack 3 1
""",

"shifts": """
    type 1 4 LSHIFT
    stack 16
    type DROP -1 1 RSHIFT
    stack 32767
    type DROP 1 16 LSHIFT
    stack 0
    type DROP -32768 15 RSHIFT
    stack 1
""",

"double-cells": """
    type 1 0 2 0 D+
    stack 0 3
    type 2DROP 1 0 DNEGATE
    stack -1 -1
    type 2DROP 65535 0 1 0 D+
    stack 1 0
""",

"pick-roll": """
    type 11 22 33 0 PICK
    stack 33 33 22 11
    type DROP 2 PICK
    stack 11 33 22 11
    type DROP 2 ROLL
    stack 11 33 22
""",

"fill-move": """
    type $0D00 16 65 FILL
    type $0D00 C@ $0D0F C@
    stack 65 65
    type 2DROP $0D00 $0D80 16 MOVE
    type $0D80 C@ $0D8F C@
    stack 65 65
    type 2DROP $0D00 $0D02 8 MOVE
    type $0D02 C@ $0D09 C@
    stack 65 65
""",

# CREATE ... DOES> is the thing a Forth is not a Forth without.
"does": """
    type : KONST CREATE , DOES> @ ;
    type 42 KONST ANSWER
    type ANSWER
    stack 42
    type DROP : TBL CREATE 0 DO I , LOOP DOES> SWAP 2 * + @ ;
    type 5 TBL SQUARES
    type 3 SQUARES
    stack 3
    type DROP 0 SQUARES
    stack 0
""",

"loops-plus": """
    type : T1 0 10 0 DO 1+ LOOP ;
    type T1
    stack 10
    type DROP : T2 0 10 0 DO 1+ 2 +LOOP ;
    type T2
    stack 5
    type DROP : T3 0 0 10 DO 1+ -1 +LOOP ;
    type T3
    stack 11
""",

"loops-question": """
    type : T4 0 5 0 ?DO 1+ LOOP ;
    type T4
    stack 5
    type DROP : T5 0 0 0 ?DO 1+ LOOP ;
    type T5
    stack 0
""",

"leave": """
    type : T6 0 100 0 DO 1+ DUP 7 = IF LEAVE THEN LOOP ;
    type T6
    stack 7
    type DROP : T7 0 10 0 DO 10 0 DO 1+ LOOP LOOP ;
    type T7
    stack 100
""",

"nested-j": """
    type : T8 0 3 0 DO 3 0 DO J + LOOP LOOP ;
    type T8
    stack 9
""",

"strings": """
    type : GS S" HELLO" ;
    type GS
    depth 2
    type DROP C@
    stack 72
    type DROP : GC C" HI" ;
    type GC COUNT NIP
    stack 2
    clear
    type 1 2 ( this is a comment ) 3
    stack 3 2 1
    clear
    type S" ABC" NIP
    stack 3
""",

"compile-time": """
    type : SIX [ 2 3 * ] LITERAL ;
    type SIX
    stack 6
    type DROP : GETXT ['] DUP ;
    type GETXT 5 SWAP EXECUTE
    stack 5 5
    type 2DROP : GA [CHAR] A ;
    type GA
    stack 65
    type DROP CHAR Z
    stack 90
""",

"recurse": """
    type : FACT DUP 1 > IF DUP 1- RECURSE * THEN ;
    type 5 FACT
    stack 120
    type DROP 7 FACT
    stack 5040
""",

"signed-division": """
    type -10 3 /MOD
    stack -4 2
    type 2DROP 10 -3 /MOD
    stack -4 -2
    type 2DROP -10 -3 /MOD
    stack 3 -1
    type 2DROP -7 2 /
    stack -4
    type DROP -7 2 MOD
    stack 1
""",

"scaling": """
    type 1000 1000 100 */
    stack 10000
    type DROP 32767 3 4 */
    stack 24575
    type DROP -1000 7 10 */
    stack -700
    type DROP 7 8 M*
    stack 0 56
""",

"pictured": """
    type 12345 0 <# #S #> NIP
    stack 5
    type DROP 255 0 <# #S #> DROP C@
    stack 50
    type DROP 16 BASE ! 255 0 <# #S #> NIP
    stack 2
    type DROP 10 BASE !
    depth 0
""",

"case": """
    type : NAME CASE 1 OF 111 ENDOF 2 OF 222 ENDOF 999 SWAP ENDCASE ;
    type 1 NAME
    stack 111
    type DROP 2 NAME
    stack 222
    type DROP 7 NAME
    stack 999
""",

"return-stack": """
    type : RT 1 2 2>R 9 2R> ;
    type RT
    stack 2 1 9
    type : RA 5 6 2>R 2R@ 2R> ;
    type 2DROP DROP RA
    stack 6 5 6 5
""",

"forget": """
    type : ZZZ 1 ;
    type : YYY 2 ;
    type YYY ZZZ
    stack 1 2
    type 2DROP FORGET ZZZ
    type ZZZ
    depth 0
    type 3 4 +
    stack 7
""",

# SYSTEM.FTH is on the disk as text; loading it recompiles the whole system
# over itself, which is the strongest test of LOAD there is.
# TEST.FTH is on the disk as text: definitions, a variable, and a
# CREATE ... DOES> array, all of which have to survive being read off a
# floppy a sector at a time.
"load": """
    load TEST.FTH
    wait 600
    clear
    check LOADED -1
    type 7 TRIPLE
    stack 21
    clear
    type 100 SUMTO
    stack 5050
    clear
    type 5 SQ
    stack 25
    clear
    type 2 3 +
    stack 5
""",

# A sector that is neither 0 nor 15, so the DOS-to-physical translation has
# to be right in both directions.  The tests run on a scratch copy of the
# image, so writing to it is safe.
"sector-io": """
    type $0D00 256 65 FILL
    clear
    type 34 7 $0D00 DWRITE
    wait 240
    stack 0
    clear
    type $0E00 256 0 FILL
    clear
    type 34 7 $0E00 DREAD
    wait 240
    stack 0
    mem 0E00 65
    mem 0EFF 65
""",

# A box drawn in white, then flooded from a point inside it: the inside
# fills and the outside must not.
"flood": """
    type HGR HCLS 3 HCOLOR
    type 100 300 40 120 HFRAME
    type 200 80 HFILL
    wait 2400
    type 200 80 HPOINT
    stack -1
    clear
    type 50 80 HPOINT
    stack 0
    clear
    type 101 41 HPOINT
    stack -1
    clear
    type TEXT
    depth 0
""",

# Eight pixels a byte, bit 0 leftmost: $FF is a solid row, $81 is its ends.
"blit": """
    type CREATE BM $FF C, $81 C, $81 C, $FF C,
    type HGR HCLS 3 HCOLOR
    type BM 8 4 100 50 BLIT
    wait 120
    type 100 50 HPOINT
    stack -1
    clear
    type 107 50 HPOINT
    stack -1
    clear
    type 101 51 HPOINT
    stack 0
    clear
    type 100 51 HPOINT
    stack -1
    clear
    type TEXT
    depth 0
""",

# Drawing a bitmap twice in XOR mode has to leave the screen as it was.
"blit-xor": """
    type CREATE BX $FF C, $FF C,
    type HGR HCLS 3 HCOLOR
    type BX 8 2 200 60 BLIT
    type 200 60 HPOINT
    stack -1
    clear
    type -1 HXOR BX 8 2 200 60 BLIT BX 8 2 200 60 BLIT 0 HXOR
    type 200 60 HPOINT
    stack -1
    clear
    type TEXT
    depth 0
""",

"sound-timing": """
    type CLICK
    depth 0
    type 90 40 TONE
    depth 0
    type 20 MS
    depth 0
    type VBL VBL
    depth 0
""",

# Write a file, then read it back through the catalog as source.
# Write a file from the console, then read it back through the catalog and
# run what it defined.  SAVE asks for the name, so the line after it is the
# answer rather than more Forth.
"save-load": """
    type S" : NEWWORD 4242 ;" SAVE
    type SAVED.FTH
    wait 900
    check NFILE 23
    clear
    load SAVED.FTH
    wait 900
    clear
    type NEWWORD
    stack 4242
""",

# A binary save keeps DOS's four-byte header, so BLOAD can put it back and
# say how long it was.
"bsave-bload": """
    type $0D00 16 90 FILL
    clear
    type $0D00 16 BSAVE
    type BLOB
    wait 900
    check NFILE 23
    clear
    type $0E00 16 0 FILL
    clear
    type NFILE @ 1- $0E00 BLOAD
    wait 600
    stack 16
    mem 0E00 90
    mem 0E0F 90
""",

# HCIRCLE takes the centre then the radius, and leaves the middle empty.
"circle": """
    type HGR HCLS 3 HCOLOR 280 96 60 HCIRCLE
    wait 120
    type 220 96 HPOINT
    stack -1
    clear
    type 340 96 HPOINT
    stack -1
    clear
    type 280 36 HPOINT
    stack -1
    clear
    type 280 96 HPOINT
    stack 0
    clear
    type TEXT
""",

# A tall box has to fill all the way to its corners, which is what the seed
# stack has to be big enough for.
"flood-big": """
    type HGR HCLS 3 HCOLOR 40 260 30 120 HFRAME
    type 150 76 HFILL
    wait 2400
    type 41 31 HPOINT
    stack -1
    clear
    type 259 119 HPOINT
    stack -1
    clear
    type 150 76 HPOINT
    stack -1
    clear
    type 20 76 HPOINT
    stack 0
    clear
    type TEXT
""",

# A quoted string has to say something at the prompt too, not only from
# inside a definition.
"dot-quote": """
    type : SAYS ." IN A DEFINITION" CR ;
    type SAYS
    depth 0
    type ." AT THE PROMPT"
    depth 0
    type HGR HCLS 3 HCOLOR 4 10 TAT T." ON THE GRAPHICS SCREEN"
    wait 120
    nonzero 2000 8000
    type TEXT
    depth 0
""",

# Each demo has to load inside the dictionary that is left and run without
# leaving anything on the stack.  They are listed here in catalog order.
"demo-gfx": """
    load GFX.FTH
    wait 1200
    clear
    type GFX
    wait 3600
    nonzero 2000 8000
    type TEXT
    depth 0
""",

"demo-moire": """
    load MOIRE.FTH
    wait 1200
    clear
    type BANDS
    wait 900
    nonzero 2000 8000
    type MOIRE
    wait 3600
    nonzero 2000 8000
    type TEXT
    depth 0
""",

"demo-bounce": """
    load BOUNCE.FTH
    wait 1200
    clear
    type 0 BX ! 0 BY ! 7 DX ! 3 DY ! STEP
    depth 0
    type BX @ BY @
    stack 3 7
    clear
    type TEXT
    depth 0
""",

"demo-primes": """
    load PRIMES.FTH
    wait 1200
    clear
    type 97 PRIME?
    stack -1
    clear
    type 91 PRIME?
    stack 0
    clear
    type 2 PRIME? 9 PRIME?
    stack 0 -1
    clear
    type PRIMES
    wait 1200
    depth 0
""",

"demo-lang": """
    load LANG.FTH
    wait 1200
    clear
    type FILLSQ 7 SQUARES @
    stack 49
    clear
    type DEMO
    wait 600
    depth 0
""",

"demo-sound": """
    load SOUND.FTH
    wait 1200
    clear
    type 120 NOTE
    depth 0
    type CHIRP
    wait 900
    depth 0
""",

# Both comment forms have to survive being read off the disk, including one
# that runs to the end of a line of code.
"comments": """
    load COMMENTS.FTH
    wait 1200
    clear
    type 7 SIXFOLD
    stack 42
    clear
    type 1 2 ( a bracket comment ) 3
    stack 3 2 1
    clear
    type 4 DOUBLE 4 TREBLE
    stack 12 8
""",

# How much dictionary a fresh boot leaves.  The whole point of streaming the
# source off the disk rather than carrying it in the image.
"headroom": """
    type $BF00 HERE - 10000 >
    stack -1
""",

# A precompiled overlay: define words, save the dictionary image, and read it
# back in a later session with the words simply there.  It has to land at the
# address it came from, and it has to refuse if it cannot.
"overlay": """
    type MARK
    type : ALPHA 111 ; : BETA ALPHA 2 * ; VARIABLE GAMMA 7 GAMMA !
    type BETA GAMMA @
    stack 7 222
    clear
    type NFILE @
    stack 22
    clear
    type SAVEDICT
    type OVL.BIN
    wait 1800
    clear
    type FORGET ALPHA
    type BETA
    depth 0
""",

# Saved, thrown away, and read back at the address it came from -- the words
# are simply there, with nothing compiled.
"overlay-load": """
    type MARK
    type : ALPHA 111 ; : BETA ALPHA 2 * ; VARIABLE GAMMA 7 GAMMA !
    type SAVEDICT
    type OVL.BIN
    wait 900
    clear
    type UNMARK
    type BETA
    depth 0
    type NFILE @ 1- LOADDICT
    wait 600
    clear
    type BETA
    stack 222
    clear
    type GAMMA @
    stack 7
""",

# Is the language card there, and can it be written?  Read $C08B twice to
# get read-RAM/write-RAM on bank 1, poke, peek, then $C082 to put the ROM
# back -- all on one line, so nothing tries to print while the ROM is gone.
"lc-ram": """
    type $C08B C@ DROP $C08B C@ DROP 123 $D000 C! $D000 C@ $C082 C@ DROP
    stack 123
    clear
    type $C08B C@ DROP $C08B C@ DROP 77 $E000 C! 88 $FE00 C! $C082 C@ DROP
    depth 0
    type $C08B C@ DROP $C08B C@ DROP $E000 C@ $FE00 C@ $C082 C@ DROP
    stack 88 77
""",

"raw-sectors": """
    type 17 0 2048 DREAD
    stack 0
    type DROP 2049 C@
    stack 17
""",
}


def run(name, script, keep_shots=False):
    shots = ROOT / "shots"
    if not keep_shots:
        subprocess.run(["rm", "-rf", str(shots)], check=False)
    subprocess.run(["cp", str(ROOT / "build" / "forth.dsk"), str(DISK)], check=True)

    syms = {}
    for line in LBL.read_text().splitlines():
        m = re.match(r"al\s+([0-9A-Fa-f]+)\s+\.?(\w+)$", line.strip())
        if m:
            syms[m.group(2)] = int(m.group(1), 16)
    if "LATESTV" not in syms:
        sys.exit("LATESTV not in build/forth.lbl -- build first")
    # The stack pointer and its bounds are assembly-time equates, so they are
    # in the source rather than the label file.
    for line in ZP.read_text().splitlines():
        m = re.match(r"(\w+)\s*=\s*\$([0-9A-Fa-f]+)", line.strip())
        if m:
            syms.setdefault(m.group(1), int(m.group(2), 16))
    wanted = ("XSAV", "DSTACK_TOP", "DSTACK_BOT")
    missing = [n for n in wanted if n not in syms]
    if missing:
        sys.exit(f"cannot find {', '.join(missing)}")
    symarg = ",".join(f"{n}={syms[n]}" for n in wanted)

    env = dict(os.environ, TEST=script, LATESTV=str(syms["LATESTV"]),
               SYMS=symarg)
    cmd = [
        "mame", "apple2ee", "-rompath", str(ROOT / "roms"), "-sl4", "",
        "-gameio", "joy", "-cfg_directory", str(ROOT / "cfg"),
        "-flop1", str(DISK), "-skip_gameinfo",
        # No window and no sound: the tests read memory, not the screen, and
        # a window stealing focus every forty seconds makes the machine
        # unusable while a suite runs.
        "-video", "none", "-sound", "none",
        "-nothrottle", "-seconds_to_run", "180", "-autoboot_delay", "0",
        "-autoboot_script", str(ROOT / "tools" / "contest.lua"),
        "-snapshot_directory", str(shots),
    ]
    # MAME's Lua print goes to stderr, so both streams have to be read.
    proc = subprocess.run(cmd, cwd=ROOT, env=env, capture_output=True, text=True)
    out = proc.stdout + proc.stderr

    print(f"\n=== {name} ===")
    passed = failed = 0
    for line in out.splitlines():
        if line.startswith(("PASS", "FAIL", "     ")):
            print("  " + line)
            if line.startswith("PASS"):
                passed += 1
            elif line.startswith("FAIL"):
                failed += 1
    if not passed and not failed and "RESULT " not in out:
        print("  no results -- the console may not have come up")
        return 0, 1
    return passed, failed


def main(argv):
    if "--list" in argv:
        print("\n".join(TESTS))
        return 0
    names = [a for a in argv[1:] if not a.startswith("-")] or list(TESTS)
    total_p = total_f = 0
    for name in names:
        if name not in TESTS:
            print(f"no such test: {name}")
            return 2
        p, f = run(name, TESTS[name])
        total_p += p
        total_f += f
    print(f"\n{'=' * 40}\n{total_p} passed, {total_f} failed")
    return 1 if total_f else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
