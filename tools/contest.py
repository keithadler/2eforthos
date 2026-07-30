#!/usr/bin/env python3
"""Run the console tests.

Each test types Forth at the prompt and then asserts against machine state --
the data stack, a variable's cell, a stretch of the graphics screen.  Checking
state rather than the screen is what makes these worth having: a screenshot
tells you something changed, the stack tells you what the system believes.

    python3 tools/contest.py            run everything
    python3 tools/contest.py arith      run named tests
    python3 tools/contest.py --list

The shot-* cases are not assertions: each loads an example, runs it and
snapshots the screen, for the images in docs/.  They are excluded from a
full run.  To regenerate one:

    rm -rf shots && python3 tools/contest.py shot-stack
    cp shots/apple2ee/0000.png docs/images/ex-stack.png
"""

import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DISK = ROOT / "build" / "run.dsk"
PDISK = ROOT / "build" / "run2.dsk"
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
    files 0
    depth 0
    type $1EAD C@ 0>
    stack -1
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
    files 0
    files 0
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
    drive 2
    wait 600
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
    files 1
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
    files 1
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
    drive 2
    wait 600
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
    drive 2
    wait 600
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
    drive 2
    wait 600
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
    drive 2
    wait 600
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
    drive 2
    wait 600
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
    drive 2
    wait 600
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
    drive 2
    wait 600
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
#
# This is a floor, not a target: it is here to catch a collapse -- something
# large accidentally compiled into the image rather than left on the disk --
# and not to hold the figure at whatever it happened to be on a good day.
# The system leaves 16458 bytes as this is written, and the threshold sits
# under that.  Raise it when the number rises; do not lower it without
# knowing what was spent.
"headroom": """
    type $C000 HERE - 15000 >
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
    files 0
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
    loadwith OVL.BIN LOADDICT
    wait 600
    clear
    type BETA
    stack 222
    clear
    type GAMMA @
    stack 7
""",

# The system's own dictionary is compiled into the language card and the
# pointer comes back to main, so the whole of main above the kernel is the
# user's.  LATEST is a system word, so it must be in the card; HERE must not.
"language-card": """
    type LATEST @ $D000 U<
    stack 0
    clear
    type HERE $C000 U<
    stack -1
    clear
    type $C000 HERE - 15000 >
    stack -1
""",

# The file count has to be right after a write, not one or four too many.
# CATLOAD used to ignore the error from DREAD, so a failed read counted the
# sector before it a second time.
"catalog-count": """
    files 0
    clear
    type CATLOAD
    wait 1800
    files 0
    clear
    type S" : X 1 ;" SAVE
    type COUNTED.FTH
    wait 1800
    files 1
    clear
    type CATLOAD
    wait 1800
    files 1
""",

# POINTER.FTH -- one test per word.  The game port is driven from the
# harness, so PTR-XY and the event queue can be exercised for real.
"ptr-sources": """
    drive 2
    wait 600
    load POINTER.FTH
    wait 2400
    clear
    point 200 100
    type JOY? 
    stack -1
    clear
    type JOY-XY
    depth 2
    clear
    type JOY-BTN0 JOY-BTN1
    stack 0 0
    clear
    type PTR-SRC@
    stack 2
    clear
    type 1 PTR-SRC! PTR-SRC@ 2 PTR-SRC!
    stack 1
""",

"ptr-position": """
    drive 2
    wait 600
    load POINTER.FTH
    wait 2400
    clear
    point 200 100
    type PTR-XY
    depth 2
    clear
    type PTR-XY DROP 200 - ABS 8 <
    stack -1
    clear
    type PTR-XY SWAP DROP 100 - ABS 6 <
    stack -1
    clear
    type 1 PTR-SRC! 300 150 PTR-POS! PTR-XY 2 PTR-SRC!
    stack 150 300
    clear
    type PTR-BTN
    stack 0
""",

"ptr-coords": """
    drive 2
    wait 600
    load POINTER.FTH
    wait 2400
    clear
    type 70 80 >CELL
    stack 10 10
    clear
    type 10 10 CELL>
    stack 80 70
    clear
    type 0 0 >CELL
    stack 0 0
    clear
    type 50 50 5 5 4 3 CLICK-IN?
    stack -1
    clear
    type 10 50 5 5 4 3 CLICK-IN?
    stack 0
    clear
    type 100 20 5 5 4 3 CLICK-IN?
    stack 0
""",

"ptr-events": """
    drive 2
    wait 600
    load POINTER.FTH
    wait 2400
    clear
    type EV-FLUSH EVENT?
    stack 0
    clear
    type 2 100 50 0 EV-PUT EVENT?
    stack -1
    clear
    type EV-GET DUP EV-TYPE SWAP DUP EV-XY ROT EV-KEY
    stack 0 50 100 2
    clear
    type EVENT?
    stack 0
    clear
    type 1 0 0 65 EV-PUT EV-GET EV-KEY
    stack 65
    clear
    type 3 1 2 0 EV-PUT EV-GET EV-PUSH EVENT?
    stack -1
""",

"ptr-hotspots": """
    drive 2
    wait 600
    load POINTER.FTH
    wait 2400
    clear
    type : HIT1 111 ; : HIT2 222 ;
    type HOT-CLEAR
    type 2 2 4 2 ' HIT1 HOT-ADD
    type 20 10 4 2 ' HIT2 HOT-ADD
    clear
    type 20 20 HOT-FIND NIP
    stack -1
    clear
    type 20 20 HOT-FIND DROP EXECUTE
    stack 111
    clear
    type 145 85 HOT-FIND DROP EXECUTE
    stack 222
    clear
    type 500 180 HOT-FIND
    stack 0 0
    clear
    type HOT-CLEAR 20 20 HOT-FIND
    stack 0 0
""",

# The button, and the events it generates, driven through the game port.
"ptr-button": """
    drive 2
    wait 600
    load POINTER.FTH
    wait 2400
    clear
    point 300 100
    type PTR-BTN
    stack 0
    clear
    press
    type JOY-BTN0
    stack -1
    clear
    type PTR-BTN
    stack -1
    clear
    release
    type PTR-BTN
    stack 0
""",

# EV-GEN turns a change in the pointer into a queued event.
"ptr-event-gen": """
    drive 2
    wait 600
    load POINTER.FTH
    wait 2400
    clear
    point 300 100
    type EV-FLUSH EVENT-POLL DROP EV-FLUSH
    press
    type EVENT-POLL DUP EV-TYPE SWAP DROP
    stack 2
    clear
    release
    type EVENT-POLL DUP EV-TYPE SWAP DROP
    stack 3
    clear
    type EV-FLUSH KBD-PTR
    stack 0
""",

# --- coverage: words that had neither a test nor an example ---------------
"cov-stack": """
    type 1 2 3 4 2SWAP
    stack 2 1 4 3
    clear
    type 1 2 3 4 2OVER
    stack 2 1 4 3 2 1
    clear
    type 1 2 3 -ROT
    stack 2 1 3
    clear
    type 5 3 U> 3 5 U> 4 0> -4 0>
    stack 0 -1 0 -1
    clear
    type 5 1 10 WITHIN 15 1 10 WITHIN 1 1 10 WITHIN
    stack -1 0 -1
""",

"cov-rstack": """
    type : RT1 >R 5 R> ;
    type 9 RT1
    stack 9 5
    clear
    type : RT2 >R R@ R> + ;
    type 6 RT2
    stack 12
""",

"cov-memory": """
    type $0E00 111 SWAP ! $0E02 222 SWAP !
    type $0E00 2@
    stack 111 222
    clear
    type 333 444 $0E00 2! $0E00 @ $0E02 @
    stack 333 444
    clear
    type $0E10 8 65 FILL $0E10 4 ERASE $0E10 C@ $0E14 C@
    stack 65 0
    clear
    type $0E20 4 BLANK $0E20 C@
    stack 32
    clear
    type $0E30 77 SWAP C! $0E30 C@
    stack 77
    clear
    type 2 CELLS 3 CELL+ 3 CHAR+ 5 ALIGN 6 ALIGNED
    stack 6 5 4 5 4
""",

"cov-numbers": """
    type 1000 2 U/MOD
    stack 500 0
    clear
    type 5 INVERT 8 2/
    stack 4 -6
    clear
    type -6 S>D DABS
    stack 0 6
    clear
    type 5 0 3 0 D-
    stack 0 2
    clear
    type 100 3 7 */MOD
    stack 42 6
    clear
    type 100 0 7 FM/MOD
    stack 14 2
""",

"cov-output": """
    type 42 U. 42 . 7 .R
    depth 0
    clear
    type $0E40 111 SWAP ! $0E40 ?
    depth 0
    clear
    type 5 SPACES SPACE
    depth 0
    clear
    type -1234 0 D.
    depth 0
    clear
    type 1234 6 U.R
    depth 0
    clear
    type S" ABC   " -TRAILING NIP
    stack 3
    clear
    type 255 0 <# #S #> TYPE
    depth 0
""",

"cov-compile": """
    type : CV1 5 ; IMMEDIATE
    type : CV2 CV1 ;
    type CV2
    stack 5
    clear
    type : CV3 0 BEGIN 1+ DUP 3 > IF EXIT THEN AGAIN ;
    type CV3
    stack 4
    clear
    type : CV4 ' DUP COMPILE, ; 
    depth 0
    clear
    type STATE @ DP @ HERE =
    stack -1 0
""",

# Lunar lander: the physics stepped by hand, with the knowns asserted --
# three steps of gravity, one step of burn, the ground under a spot, and
# the touchdown test both ways.  LANDER itself is interactive and is not
# run here; every piece it is made of is.
"lander": """
    wait 300
    drive 2
    wait 600
    type 1 RND-SEED!
    load LANDER.FTH
    wait 3000
    clear
    type MAKE-MOON PAD# @ 2 > PAD# @ 33 < AND
    stack -1
    clear
    type 0 VY ! 0 THR ! 0 SIDE ! 900 FUEL ! PHYS PHYS PHYS VY @
    stack 6
    clear
    type 1 THR ! PHYS VY @
    stack 2
    clear
    type 100 64 * SX ! 180 64 * SY ! PY DOWN?
    stack -1 180
    clear
    type 20 64 * SY ! DOWN?
    stack 0
    clear
    type 520 64 * SX ! PX
    stack 520
""",

# Breakout: build the wall, knock a brick out of it, bounce off a side
# wall, and check the bat answers the paddle.  The paddle idles at 128,
# which is the middle of the travel, so the bat should sit mid-screen.
"breakout": """
    wait 300
    drive 2
    wait 600
    type 1 RND-SEED!
    load BREAKOUT.FTH
    wait 3000
    clear
    type HGR 3 HCOLOR -1 HXOR 0 SCORE ! WALL NLEFT @
    wait 2400
    stack 84
    clear
    type 1 0 BRICK C@  50 20 HPOINT
    stack -1 1
    clear
    type 100 X ! 20 Y ! HITS 0<>
    stack -1
    clear
    type HITS KILL NLEFT @ SCORE @
    stack 10 83
    clear
    type HITS
    stack 0
    clear
    type 1 X ! -3 DX ! 100 Y ! BOUNCE DX @
    stack 3
    clear
    type BAT-AT 240 > BAT-AT 260 < AND
    stack -1
    type TEXT
""",

# The hat: the altitude function at its calm centre and on a slope, and
# one full row through the middle, which must land a pixel dead centre.
# The whole HAT takes two minutes and is for looking at, not asserting.
"hat": """
    wait 300
    drive 2
    wait 600
    load HAT.FTH
    wait 2400
    clear
    type 0 0 ALT
    stack 30
    clear
    type 30 0 ALT DUP -31 > SWAP 31 < AND
    stack -1
    clear
    type HGR HCLS 3 HCOLOR HCLR 0 HATROW
    wait 2400
    type 280 80 HPOINT
    stack -1
    type TEXT
""",

# MORE pages a file; a short file ends without paging, which is the part
# a test can hold still.  MKEY and the Q exit need a hand on the keyboard.
"more": """
    wait 300
    loadwith MORE.FTH LOAD
    wait 1500
    clear
    loadwith KEYS MORE
    wait 1500
    depth 0
    type 999 MORE
    wait 600
    depth 0
""",

# MENU folds 2 DRIVE CAT n LOAD into a question.  Answering with a number
# past the catalog exercises the whole path without depending on which
# file is which number; MNUM is asserted directly both ways.
"menu": """
    wait 300
    loadwith MENU.FTH LOAD
    wait 1500
    clear
    type S" 123" MNUM
    stack -1 123
    clear
    type S" 12X" MNUM NIP
    stack 0
    clear
    type S" " DROP 0 MNUM NIP
    stack 0
    clear
    type MENU
    wait 900
    type 99
    wait 900
    depth 0
""",

# The RAM disk: LIB RAMDISK.FTH probes the RamWorks card MAME carries in
# the aux slot, and drive 3 becomes a 560-sector volume in banks 1-3 --
# auto-formatted on first use, instant, volatile.  The guard before the
# LIB proves the resident system refuses drive 3 until the library is in.
"ramdisk": """
    wait 300
    type 3 DRIVE
    wait 600
    depth 0
    type RAMDISK
    wait 4800
    clear
    type NBK @ 15 >
    stack -1
    clear
    type 3 DRIVE
    wait 2400
    filesabs 0
    type S" : RWORD 777 ;" SAVE
    type RAM.FTH
    wait 1500
    filesabs 1
    clear
    loadwith RAM.FTH LOAD
    wait 900
    type RWORD
    stack 777
    clear
    type FREE
    wait 600
    stack 542
    clear
    type 1 DRIVE
    wait 900
    type NFILE @ 0>
    stack -1
""",

# The autoload hook: an unknown word whose name matches a WORD.FTH on the
# system disk loads it -- from either drive -- and an unknown word that
# matches nothing still just gets its question mark.  MORE pages file 13
# on drive 2 the way a person would try it cold.
"autoload": """
    wait 300
    type 2 DRIVE
    wait 900
    type 13 MORE
    wait 4800
    clear
    type 13 MORE
    wait 2400
    type Q
    wait 900
    depth 0
    type XYZZY 1 2 +
    wait 900
    depth 0
    clear
    type 1 DRIVE
    wait 900
    type MENU
    wait 4800
    clear
    type S" 12" MNUM
    stack -1 12
""",

# ForthPaint: the tools driven by hand -- pen segment, the two-click
# state machine, and a disc -- with the crosshair loop left out of it.
"paint": """
    wait 300
    type PAINT
    wait 4200
    clear
    type HGR HCLS 3 INK ! 1 TOOL ! 100 CX ! 50 CY ! 90 PX2 ! 50 PY2 !
    wait 600
    type PRESS 95 50 HPOINT
    wait 600
    stack -1
    clear
    type 5 TOOL ! 0 ANCH ! 2CLICK?
    stack 0
    clear
    type 2CLICK? ANCH @
    stack 0 -1
    clear
    type 300 CX ! 100 CY ! 4 TOOL ! 0 ANCH ! PRESS 320 CX ! PRESS
    wait 900
    type 310 100 HPOINT
    wait 300
    stack -1
    type TEXT
""",

# ForthWrite: the wrap machinery -- a word straddling the margin is
# carried whole onto the next line, and the document flattens for SAVE.
"forthwrite": """
    wait 300
    type WRITE
    wait 4200
    clear
    type 0 WLINES ! WOPEN 72 WPUT 73 WPUT WCOL @
    stack 2
    clear
    type WFLUSH WLINES @ WCOL @
    stack 0 1
    clear
    type 0 WLINES ! WOPEN
    type : TFILL 0 DO 65 WPUT LOOP 32 WPUT ;
    type 55 TFILL 87 WPUT 88 WPUT 89 WPUT WCOL @
    stack 59
    clear
    type WWRAP WLINES @ WCOL @
    stack 3 1
    clear
    type WCUR 1+ C@ WCUR 2 + C@ WCUR 3 + C@
    stack 89 88 87
""",

# The checkbook: exact cents in doubles, a running balance, and the whole
# flow arriving by autoload from drive 2 -- LEDGER is typed, not loaded.
"ledger": """
    wait 300
    type LEDGER
    wait 4200
    type LEDGER
    wait 1200
    type 12 50 IN SALARY
    wait 900
    type 3 15 OUT COFFEE
    wait 900
    clear
    type BLO @ BHI @
    stack 0 935
    clear
    type 1250 00 IN PAYDAY BLO @ BHI @
    wait 900
    stack 1 -5137
    clear
    type LN @
    stack 3
    clear
    type 0 LENT 2@ D. 1 LENT 2@ D.
    wait 600
    depth 0
""",

# HELP with a name reads the entry out of HELPTEXT on the system disk;
# plain HELP is the entry named HELP.  A word with no entry says so.
"help": """
    wait 300
    type HELP HGR
    wait 2400
    depth 0
    type HELP XYZZY
    wait 3600
    depth 0
    clear
    type S" HELPTEXT" FINDF 0 <
    stack 0
    clear
    type S" NOSUCH.XYZ" FINDF
    stack -1
    clear
    type PARSE-NAME FOO NIP
    stack 3
""",

# The DREAD comes with the head deliberately left BETWEEN tracks by DHALF,
# and recovering from that costs the driver a couple of seconds of address
# fields that match no track.  The wait is for that: sampling early catches
# the read mid-flight, with its track argument still on the stack.
"cov-disk": """
    type DRECAL
    depth 0
    clear
    type 22 DSEEK
    depth 0
    clear
    type 17 0 $0E80 DREAD
    wait 600
    stack 0
""",

"cov-banks": """
    type MAINBANK $0E90 123 SWAP ! $0E90 @
    stack 123
    clear
    type AUXBANK MAINBANK $0E90 @
    stack 123
""",

"cov-graphics2": """
    type HGR HCLS 3 HCOLOR
    type 107 40 160 HVLINE
    nonzero 2228 40
    type 0 0 TAT -1 TINV
    type 65 TEMIT 0 TINV
    type TEXT
    depth 0
""",

"cov-files": """
    files 0
    type S" : ZZ 5 ;" SAVE
    type COVTMP.FTH
    wait 1800
    files 1
    clear
    loadwith COVTMP.FTH CATENT
    type C@
    stack 0
    clear
    loadwith COVTMP.FTH LOCK
    wait 1800
    clear
    loadwith COVTMP.FTH CATENT
    type C@
    stack 128
    clear
    loadwith COVTMP.FTH LOCK
    wait 1800
    clear
    loadwith COVTMP.FTH CATENT
    type C@
    stack 0
    clear
    loadwith COVTMP.FTH DEL
    wait 2400
    files 0
""",

# The last of the uncovered words.  BYE is not run -- it halts the machine --
# but it is looked up, which proves it is there and spelled right.
"cov-rest": """
    type 1 2 3 ABORT
    depth 0
    clear
    type : AB1 ABORT" GONE" ;
    type 0 AB1
    depth 0
    clear
    type 99 ' AB1 DROP
    stack 99
    clear
    type ' BYE 0<>
    stack -1
    clear
    type PAGE
    depth 0
""",

"cov-rest2": """
    type CREATE CB1 7 , ' CB1 >BODY @
    stack 7
    clear
    type $0EA0 4 65 FILL $0EA0 $0EB0 4 CMOVE $0EB0 C@
    stack 65
    clear
    type REINDEX 3 4 +
    stack 7
    clear
    type NFREE @ 0 U>
    stack -1
    clear
    type CATBUF VTOCBUF TSBUF
    stack 2560 2304 4096
""",

# ASKLN reads a line; REN renames using one.  Both go through the same path
# SAVE does, so the answer is typed as the following line.
"cov-askln": """
    type S" : QQ 1 ;" SAVE
    type COVREN.FTH
    wait 1800
    clear
    loadwith COVREN.FTH REN
    type COVGONE.FTH
    wait 2400
    clear
    files 1
    clear
    loadwith COVGONE.FTH DEL
    wait 2400
    files 0
""",

"shot-moire": """
    drive 2
    wait 600
    load MOIRE.FTH
    wait 2400
    clear
    type MOIRE
    wait 4800
    shot
""",

"shot-float": """
    drive 2
    wait 600
    load FLOAT.FTH
    wait 2400
    clear
    type CONSTANTS
    wait 900
    type ROOTS
    wait 1200
    type TRIG
    wait 1800
    shot
""",

"shot-chart": """
    drive 2
    wait 600
    load CHART.FTH
    wait 2400
    clear
    type BARS
    wait 2400
    shot
""",

"shot-arc": """
    type LIB GFXLIB.FTH
    wait 2400
    clear
    type HGR HCLS 3 HCOLOR
    type 140 96 70 0 360 HARC
    wait 2400
    type 380 96 70 0 90 HPIE
    wait 1200
    type 380 96 50 100 200 HPIE
    wait 1200
    shot
""",

"shot-inspect": """
    type SEE
    wait 3000
    clear
    type : CUBE DUP DUP * * ;
    type : GREET 42 CUBE DROP ;
    type SEE CUBE
    wait 900
    type SEE GREET
    wait 900
    type PAD 24 DUMP
    wait 600
    shot
""",

# --- screenshots for the documentation ------------------------------------
# Not assertions: each loads an example, runs it, and snapshots what it put
# on the screen.  Run one at a time and copy shots/apple2ee/0000.png.
"shot-stack": """
    drive 2
    wait 600
    load STACK.FTH
    wait 2400
    clear
    type ALL
    wait 600
    shot
""",

"shot-conds": """
    drive 2
    wait 600
    load CONDS.FTH
    wait 2400
    clear
    type -5 SIGNOF 0 SIGNOF 7 SIGNOF
    type 95 GRADE 85 GRADE 65 GRADE
    type 1 NAMEOF 2 NAMEOF 3 NAMEOF 9 NAMEOF
    wait 600
    shot
""",

"shot-defining": """
    drive 2
    wait 600
    load DEFINING.FTH
    wait 2400
    clear
    type SHOWARR
    type SHOWCOL
    wait 600
    shot
""",

"shot-sound": """
    drive 2
    wait 600
    load SOUND.FTH
    wait 2400
    clear
    type CHIRP
    wait 900
    type SCALE
    wait 900
    shot
""",

"shot-diskio": """
    drive 2
    wait 600
    load DISKIO.FTH
    wait 2400
    clear
    type SHOWVTOC
    wait 1800
    shot
""",

"shot-paddle": """
    drive 2
    wait 600
    load PADDLE.FTH
    wait 2400
    clear
    point 300 120
    type SHOWPDL
    wait 900
    shot
""",

"shot-pointer": """
    drive 2
    wait 600
    load POINTER.FTH
    wait 2400
    clear
    type EV-FLUSH
    point 200 80
    press
    type EVENT-POLL DUP EV-TYPE . EV-XY SWAP . . CR
    release
    point 420 150
    press
    type EVENT-POLL DUP EV-TYPE . EV-XY SWAP . . CR
    release
    type 2 2 4 2 ' PTR-DEMO HOT-ADD  20 20 HOT-FIND NIP . CR
    wait 300
    shot
""",

# The primitives have to mean exactly what the colon definitions did.
"fast-words": """
    type 3 4 > 4 3 > 5 5 >
    stack 0 -1 0
    clear
    type 3 4 <> 5 5 <> 0 0<> 7 0<>
    stack -1 0 0 -1
    clear
    type 5 0> -5 0> 0 0>
    stack 0 0 -1
    clear
    type 9 3 U> 3 9 U>
    stack 0 -1
    clear
    type -7 ABS 7 ABS 0 ABS
    stack 0 7 7
    clear
    type 3 9 MIN 3 9 MAX -4 2 MIN -4 2 MAX
    stack 2 -4 9 3
    clear
    type 1 2 3 -ROT
    stack 2 1 3
    clear
    type 1 2 TUCK
    stack 2 1 2
    clear
    type 1 2 2DUP
    stack 2 1 2 1
    clear
    type 1 2 3 4 2DROP
    stack 2 1
""",

# A size budget, which this did not have until the kernel had grown by a
# third in a day and broken PICSAVE without anything noticing.
#
# Two thresholds matter.  15000 is the floor: below it there is not enough
# room to load a demo and define anything.  16384 is what PICSAVE needs to
# stage both halves of the screen -- once 412 bytes out of reach, regained
# when the uninitialized buffers moved out of the image, and asserted here
# so it cannot quietly go away again.
"unused": """
    type UNUSED 15000 >
    stack -1
    clear
    type UNUSED 16384 < 0=
    stack -1
    clear
    type UNUSED $C000 HERE - =
    stack -1
    clear
    type UNUSED
    show-only
""",

"stack-pointers": """
    type SP@ SP@ -
    stack 2
    clear
    type RP@ $0100 U> RP@ $0200 U<
    stack -1 -1
    clear
    type 5 6 +
    stack 11
""",

# A word can try something and recover, instead of the line going down.
# Note: ' not ['] -- ['] is compile-only and pushes nothing at the prompt,
# which is what made this look broken the first time it was written.
"catch-throw": """
    type : BOOM 42 THROW ;
    type : SAFE 99 ;
    type ' SAFE CATCH
    stack 0 99
    clear
    type ' BOOM CATCH
    stack 42
    clear
    type : DEEP BOOM 1 2 3 ;
    type ' DEEP CATCH
    stack 42
    clear
    type 7 8 +
    stack 15
""",

# Writing into $C000 is not a crash, it is soft switches: it would bank the
# language card out from under the dictionary.  The guard has to catch it,
# say so, and leave the machine usable.
"dict-full": """
    type $BFF0 DP !
    depth 0
    clear
    type 1 , 1 , 1 , 1 , 1 , 1 , 1 , 1 ,
    depth 0
    clear
    type 3 4 +
    stack 7
""",

# The screen is 16K -- $2000-$3FFF in *both* banks -- so BSAVE of 8K saves
# half a picture.  PICSAVE stages both halves into one contiguous block,
# which needs 16K free.  For a while the kernel had grown past leaving that
# much and this test asserted the polite refusal; the uninitialized buffers
# then moved out of the image to the block above the catalog, and the room
# came back.  UNUSED PICLEN < is the assertion that keeps it: if this fails,
# the kernel has grown past 16K free again and PICSAVE is dead again.
"picture": """
    type HGR HCLS 3 HCOLOR 0 559 96 HLINE
    wait 300
    type MAINBANK $2228 C@ AUXBANK $2228 C@ MAINBANK
    stack 127 127
    clear
    type UNUSED PICLEN <
    stack 0
    clear
    type TEXT 6 7 *
    stack 42
""",

# The whole journey: format, draw, save the screen, wipe it, load it back.
# On the stock disk a picture does not fit -- 65 sectors against 23 free --
# so the test INITs first, which is also the only regular exercise INIT and
# the write-then-read settling get: sixteen writes and then a read of what
# was just written is exactly the sequence that used to come back with the
# catalog it had erased.
"picture-roundtrip": """
    wait 300
    type INIT
    wait 1500
    filesabs 0
    type HGR HCLS 3 HCOLOR 100 40 HPLOT 200 96 50 HCIRCLE
    wait 600
    type PICSAVE
    type PIC
    wait 4200
    filesabs 1
    type HCLS
    wait 600
    type 100 40 HPOINT 200 146 HPOINT
    wait 300
    stack 0 0
    clear
    type 0 PICLOAD
    wait 3000
    type 100 40 HPOINT 200 146 HPOINT
    wait 300
    stack -1 -1
    clear
    type TEXT
    depth 0
""",

# Portraits of the games, for docs/images and the README.
"shot-lander": """
    wait 300
    drive 2
    wait 600
    type 1 RND-SEED!
    load LANDER.FTH
    wait 3000
    clear
    type START 1 FLAME ! SHIP HUD
    wait 600
    shot
    type TEXT
""",

"shot-breakout": """
    wait 300
    drive 2
    wait 600
    type 1 RND-SEED!
    load BREAKOUT.FTH
    wait 3000
    clear
    type HGR 3 HCOLOR -1 HXOR 0 SCORE ! 3 BALLS ! WALL
    wait 2400
    type BAT-AT DUP DRAW-BAT OLDBAT ! BATX !
    type 260 X ! 150 Y ! BALL 40 SCORE ! SHOW
    wait 600
    shot
    type TEXT
""",

# The full hat, which is the point.  Two emulated minutes of ROM
# floating point; the PAUSE at the end holds the picture for the shot.
"shot-hat": """
    wait 300
    drive 2
    wait 600
    load HAT.FTH
    wait 2400
    clear
    type HAT
    wait 11400
    shot
    type Q
""",

"shot-paint": """
    wait 300
    type PAINT
    wait 4200
    clear
    type HGR HCLS
    type 3 INK ! INK! 40 520 20 170 HFRAME
    type 150 110 42 HDISC  0 HCOLOR 150 110 20 HDISC
    type 3 HCOLOR 300 150 340 150 HLINE2 340 150 320 60 HLINE2
    type 320 60 300 150 HLINE2 321 100 HFILL
    type 430 70 26 HCIRCLE 400 470 120 155 HFRAME
    wait 1800
    type 250 CX ! 90 CY ! CROSS
    wait 600
    shot
    type TEXT
""",

"shot-ledger": """
    wait 300
    type LEDGER
    wait 4200
    type LEDGER
    wait 1200
    type 1250 00 IN SALARY
    wait 900
    type 42 50 OUT GROCERIES
    wait 900
    type 18 99 OUT RECORDS
    wait 900
    type 600 00 IN CONSULTING
    wait 900
    type ENTRIES
    wait 1200
    shot
""",

"gfxlib": """
    type LIB GFXLIB.FTH
    wait 2400
    clear
    type HGR HCLS 3 HCOLOR
    type 280 96 60 40 HELLIPSE
    wait 1200
    nonzero 2228 40
    clear
    type HCLS 3 HCOLOR 100 40 HPLOT
    wait 300
    type 100 40 HPOINT
    stack -1
    clear
    type HERE 100 40 4 4 BLK-SAVE
    wait 300
    type HERE C@
    stack 1
    clear
    type HCLS HERE 200 40 4 4 BLK-REST
    wait 300
    type 200 40 HPOINT
    stack -1
    clear
    type TEXT
    depth 0
""",

# Floating point by calling Applesoft's, which is several kilobytes of
# debugged code sitting in the ROM.  The machine has to bank the ROM back in
# around every call, because the language card holds the dictionary.
"float": """
    type 144 S>F FSQRT F>S
    stack 12
    clear
    type FDEPTH
    stack 0
    clear
    type 3 S>F 4 S>F F+ F>S
    stack 7
    clear
    type 6 S>F 7 S>F F* F>S
    stack 42
    clear
    type 100 S>F 4 S>F F/ F>S
    stack 25
    clear
    type 10 S>F 3 S>F F- F>S
    stack 7
    clear
    type 2 S>F FSQRT 2 S>F FSQRT F* F>S
    stack 2
    clear
    type FDEPTH
    stack 0
""",

# The whole point of the exercise: transcendentals nobody had to write.
"float-transcendental": """
    type 0 S>F FCOS 1000 S>F F* F>S
    stack 999
    clear
    type 0 S>F FSIN F>S
    stack 0
    clear
    type 1 S>F FEXP 1000 S>F F* F>S
    stack 2718
    clear
    type 1 S>F FATN 4000 S>F F* F>S
    stack 3141
    clear
    type 20 S>F FLN 1000 S>F F* F>S
    stack 2995
    clear
    type FDEPTH
    stack 0
""",

# And that the interpreter is unharmed by all the banking and zero page
# saving that goes on underneath.
"float-safety": """
    type 1 2 3 144 S>F FSQRT F>S
    stack 12 3 2 1
    clear
    type : SQ DUP * ; 12 SQ
    stack 144
    clear
    type 7 S>F F.
    depth 0
    clear
    type 22 S>F 7 S>F F/ F.
    depth 0
    clear
    type -10 3 /MOD
    stack -4 2
""",

# The file commands read a sector, change a few bytes and write it back.  A
# read whose error is ignored writes the *previous* sector's contents back
# in its place.  These check the whole round trip survives, and that RD and
# WR report rather than corrupt.
"file-roundtrip": """
    type S" : RT 1 ;" SAVE
    type RTRIP.FTH
    wait 900
    files 1
    clear
    loadwith RTRIP.FTH LOCK
    wait 900
    clear
    loadwith RTRIP.FTH CATENT
    type C@
    stack 128
    clear
    loadwith RTRIP.FTH REN
    type RTRIP2.FTH
    wait 900
    files 1
    clear
    loadwith RTRIP2.FTH CATENT
    type C@
    stack 128
    clear
    loadwith RTRIP2.FTH DEL
    wait 900
    files 1
    clear
    loadwith RTRIP2.FTH LOCK
    wait 900
    clear
    loadwith RTRIP2.FTH DEL
    wait 900
    files 0
""",

# Reading a file a byte at a time, without swallowing it whole.  TEST.FTH
# starts with a backslash comment, stored high-bit set the way DOS does.
"file-read": """
    drive 2
    wait 600
    loadwith TEST.FTH FOPEN
    wait 1200
    stack -1
    clear
    type FGETC
    stack 220
    clear
    type FGETC FGETC
    stack 212 160
    clear
    type PAD 16 FREAD
    stack 16
    clear
    type PAD C@ PAD 1+ C@
    stack 211 197
    clear
    type FCLOSE FGETC
    stack -1
""",

# CALL runs a subroutine; ROMCALL switches the ROM back first, which is what
# anything at $D000-$FFFF needs now the card holds the dictionary.  $FC58 is
# the monitor's HOME.  $FBE4 is BELL, which returns harmlessly.
"call": """
    type $FBE4 ROMCALL
    depth 0
    clear
    type 3 4 + $FBE4 ROMCALL
    stack 7
    clear
    type $FC58 ROMCALL 5 6 *
    stack 30
""",

# A sixteen-bit xorshift: same value from the same seed, different values in
# sequence, and everything lands inside the range asked for.
"random": """
    type 1 RND-SEED! RND 0<>
    stack -1
    clear
    type 1 RND-SEED! RND 1 RND-SEED! RND =
    stack -1
    clear
    type 1 RND-SEED! RND RND =
    stack 0
    clear
    type 7 RND-SEED! 0 10 RND-RANGE 0 10 RND-RANGE 0 10 RND-RANGE
    depth 3
    clear
    type 7 RND-SEED! 0 10 RND-RANGE 11 U<
    stack -1
    clear
    type 5 5 RND-RANGE
    stack 5
""",

# A line at a time, which is what interchanging a text file with anything
# else needs.  TEST.FTH's first line is a backslash comment.
"file-lines": """
    drive 2
    wait 600
    loadwith TEST.FTH FOPEN
    wait 1200
    clear
    type PAD 80 DFGETS
    stack 0 62
    clear
    type PAD C@ PAD 1+ C@
    stack 32 92
    clear
    type PAD 80 DFGETS DROP 0>
    stack -1
    clear
    type FCLOSE
    depth 0
""",

# Lo-res is the text page seen differently: two blocks a byte, low nibble
# above the high one.  Row 0 is $0400, row 2 is $0480 -- the text screen's
# own scrambled order, not consecutive.
"lores": """
    type GR 0 GCLS
    wait 300
    mem 0400 0
    clear
    type 15 GCOLOR! 0 0 GPLOT
    wait 300
    mem 0400 15
    clear
    type 0 1 GPLOT
    wait 300
    mem 0400 255
    clear
    type 12 GCOLOR! 0 1 GPLOT
    wait 300
    mem 0400 207
    clear
    type 0 0 GSCRN 0 1 GSCRN
    stack 12 15
    clear
    type 0 GCLS 3 GCOLOR! 0 39 0 GHLIN
    wait 600
    mem 0400 3
    mem 0427 3
    type 0 0 GSCRN 39 0 GSCRN 20 0 GSCRN
    stack 3 3 3
    clear
    type 0 39 10 GVLIN
    wait 900
    type 10 0 GSCRN
    stack 3
    clear
    type 10 39 GSCRN
    stack 3
    clear
    type 5 GCOLOR! 20 10 8 GBAR
    wait 600
    type 20 10 GSCRN 20 17 GSCRN 20 18 GSCRN
    stack 0 5 5
    clear
    type DATA: 11 +VAL 22 +VAL 33 +VAL ;DATA DATA#
    stack 3
    clear
    type READ-VAL READ-VAL RESTORE-DATA READ-VAL
    stack 11 22 11
    clear
    type 45 45 GSCRN 39 48 GSCRN
    stack 0 0
    clear
    type TEXT
    depth 0
""",

# Applesoft's DATA and READ: values in the dictionary, walked in order.
"data-read": """
    type DATA: 10 +VAL 20 +VAL 30 +VAL ;DATA
    type DATA#
    stack 3
    clear
    type READ-VAL READ-VAL READ-VAL
    stack 30 20 10
    clear
    type READ-VAL
    stack 0
    clear
    type RESTORE-DATA READ-VAL
    stack 10
""",

"ipow": """
    type 2 10 IPOW
    stack 1024
    clear
    type 3 0 IPOW 7 1 IPOW -2 3 IPOW
    stack -8 7 1
""",

# FDUP FSWAP FOVER: without them a formula cannot reach its operands twice.
"float-stack": """
    type 7 S>F FDUP F* F>S
    stack 49
    clear
    type FDEPTH
    stack 0
    clear
    type 10 S>F 3 S>F FSWAP F- F>S
    stack -7
    clear
    type 2 S>F 5 S>F FOVER F* F>S FDROP FDROP
    stack 10
    clear
    type FDEPTH
    stack 0
""",

"shuffle-wait": """
    type CREATE SHT 1 C, 2 C, 3 C, 4 C, 5 C, 6 C, 7 C, 8 C,
    type : SUM8 0 8 0 ?DO SHT I + C@ + LOOP ;
    type SUM8
    stack 36
    clear
    type 9 RND-SEED! SHT 8 1 SHUFFLE
    wait 600
    type SUM8
    stack 36
    clear
    type SHT C@ 1 = SHT 1+ C@ 2 = AND
    stack 0
    clear
    type $0E00 170 SWAP C! $0E00 255 170 WAIT-BIT 5 6 *
    stack 30
""",

"finance": """
    drive 2
    wait 600
    load FINANCE.FTH
    wait 2400
    clear
    type 2 S>F 10 S>F F** F>S
    stack 1024
    clear
    type FDEPTH
    stack 0
    clear
    type 10000 500 30 PMT F>S
    stack 650
    clear
    type 10000 500 30 COMPOUND F>S
    stack 32767
    clear
    type 10000 500 30 COMPOUND F.
    depth 0
    clear
    type 1000 500 10 PV F>S
    stack 7721
    clear
    type 1000 500 10 FV F>S
    stack 12577
    clear
    type 9000 1000 5 SLN F>S
    stack 1600
    clear
    type FDEPTH
    stack 0
""",

# The debugging tax your friend named: an interactive interpreter is not the
# same as being able to stop and ask what a thing is.
"inspect": """
    type SEE
    wait 3000
    clear
    type $0E00 65 SWAP C! $0E01 66 SWAP C!
    type $0E00 8 DUMP
    depth 0
    clear
    type ' DUP >NAME NIP
    stack 3
    clear
    type ' DUP >NAME DROP C@
    stack 68
    clear
    type : SQ DUP * ;
    type SEE SQ
    wait 600
    depth 0
    clear
    type SEE DUP
    depth 0
    clear
    type SEE NOSUCHWORD
    depth 0
""",

# MARKER makes a word that forgets everything after it, itself included.
"marker": """
    type SEE
    wait 3000
    clear
    type MARKER -WORK
    type : W1 111 ; : W2 222 ;
    type W1 W2
    stack 222 111
    clear
    type -WORK
    wait 300
    type W1
    depth 0
    clear
    type 3 4 +
    stack 7
    clear
    type MARKER -AGAIN : W3 5 ; W3
    stack 5
""",

# An arc, now that FSIN and FCOS exist.  At zero degrees the point is due
# right of the centre; at ninety it is directly below, y growing downward.
"arc": """
    type LIB GFXLIB.FTH
    wait 2400
    clear
    type HGR HCLS 3 HCOLOR
    type 280 96 60 0 90 HARC
    wait 1800
    type 340 96 HPOINT
    stack -1
    clear
    type 280 156 HPOINT
    stack -1
    clear
    type 220 96 HPOINT
    stack 0
    clear
    type TEXT
    depth 0
""",

"eg-float": """
    drive 2
    wait 600
    load FLOAT.FTH
    wait 2400
    clear
    type PI 1000 S>F F* F>S
    stack 3141
    clear
    type E 1000 S>F F* F>S
    stack 2718
    clear
    type 90 S>F DEG>RAD FSIN 1000 S>F F* F>S
    stack 999
    clear
    type ROOTS
    wait 900
    depth 0
    clear
    type FDEPTH
    stack 0
""",

"eg-chart": """
    drive 2
    wait 600
    load CHART.FTH
    wait 2400
    clear
    type DATA#
    stack 7
    clear
    type BARS
    wait 1800
    type 3 39 GSCRN
    stack 15
    clear
    type TEXT 2 3 +
    stack 5
""",

# A line editor, so code can be written on the machine instead of on the
# host.  Type lines in, list them, edit one, write it out, load it back --
# which is the whole loop this system did not have.
"editor": """
    drive 2
    wait 600
    rebase
    load EDIT.FTH
    wait 3000
    clear
    type NEW ELINES @
    stack 0
    clear
    type +L
    type : ETEST 111 ;
    type : ETEST2 ETEST 2 * ;
    type .
    wait 300
    type ELINES @
    stack 2
    clear
    type 0 ELINE COUNT NIP
    stack 13
    clear
    type 1 SET
    type : ETEST2 ETEST 3 * ;
    wait 300
    type ELINES @
    stack 2
    clear
    type EWRITE
    wait 300
    type EDTMP.FTH
    wait 2400
    files 1
    clear
    loadwith EDTMP.FTH LOAD
    wait 2400
    clear
    type ETEST2
    stack 333
    clear
    type NEW ELINES @
    stack 0
    clear
    loadwith EDTMP.FTH EREAD
    wait 2400
    type ELINES @
    stack 2
    clear
    type 0 ELINE COUNT NIP
    stack 13
""",

"raw-sectors": """
    type 17 0 2048 DREAD
    stack 0
    type DROP 2049 C@
    stack 17
""",

# INIT is the one word that can make a disk unbootable, and it did: it
# marked a fixed eleven tracks used, the source grew to reach track 12, and
# a formatted disk would then hand tracks 11 and 12 to the next file written
# and put it straight over the source.
#
# The free count is what pins it.  Thirty-five tracks, less tracks 0 to
# SRCEND and the catalog at 17: with the source ending at track 12 that is
# fourteen tracks used and 21*16 = 336 sectors free.  Reserving only 0-10
# would leave 368, so this number knows the difference.
"init": """
    type SRCEND
    stack 12
    clear
    type INIT
    wait 1800
    type CATLOAD
    wait 900
    filesabs 0
    clear
    type FREE
    stack 336
    clear
    type 12 0 $0D00 RD
    stack -1
""",
}


def run(name, script, keep_shots=False):
    shots = ROOT / "shots"
    if not keep_shots:
        subprocess.run(["rm", "-rf", str(shots)], check=False)
    subprocess.run(["cp", str(ROOT / "build" / "forth.dsk"), str(DISK)], check=True)
    subprocess.run(["cp", str(ROOT / "build" / "programs.dsk"), str(PDISK)], check=True)

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
    wanted = ("XSAV", "DSTACK_TOP", "DSTACK_BOT", "ReadLine")
    missing = [n for n in wanted if n not in syms]
    if missing:
        sys.exit(f"cannot find {', '.join(missing)}")
    symarg = ",".join(f"{n}={syms[n]}" for n in wanted)

    # -video none is not enough on macOS: SDL still opens a window, which
    # takes over a Space and blacks the screen.  A dummy SDL driver is what
    # actually keeps it off the display.
    env = dict(os.environ, TEST=script, LATESTV=str(syms["LATESTV"]),
               SYMS=symarg, SDL_VIDEODRIVER="dummy", SDL_AUDIODRIVER="dummy")
    cmd = [
        "mame", "apple2ee", "-rompath", str(ROOT / "roms"), "-sl4", "",
        "-aux", "rw3",
        "-gameio", "joy", "-cfg_directory", str(ROOT / "cfg"),
        "-flop1", str(DISK), "-flop2", str(PDISK), "-skip_gameinfo",
        # No window and no sound: the tests read memory, not the screen, and
        # a window stealing focus every forty seconds makes the machine
        # unusable while a suite runs.
        "-video", "none", "-sound", "none",
        # SNAPSIZE=1680x1152 for captures meant to be looked at rather than
        # asserted on; the native 560x384 goes soft the moment anything
        # scales it up.
        *(["-snapsize", os.environ["SNAPSIZE"], "-snapview", "internal"]
          if os.environ.get("SNAPSIZE") else []),
        "-nothrottle", "-seconds_to_run", "480", "-autoboot_delay", "0",
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
    # shot-* cases are for regenerating the documentation images, not for
    # asserting -- a full run skips them, exactly as the docstring says.
    names = ([a for a in argv[1:] if not a.startswith("-")]
             or [n for n in TESTS if not n.startswith("shot-")])
    total_p = total_f = 0
    # Which cases failed, not just how many assertions did.  A full run is
    # thousands of lines and the count at the bottom does not say where to
    # look; this is the line worth reading.
    broken = []
    for name in names:
        if name not in TESTS:
            print(f"no such test: {name}")
            return 2
        p, f = run(name, TESTS[name])
        total_p += p
        total_f += f
        if f:
            broken.append(f"{name}({f})")
    print(f"\n{'=' * 40}\n{total_p} passed, {total_f} failed")
    if broken:
        print("failing cases: " + " ".join(broken))
    return 1 if total_f else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
