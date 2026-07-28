# Apple ][+ Forth

A Forth system with a hi-res graphics driver and a mouse-pointer windowing
environment, running on an emulated Apple ][+.  6502 source in, bootable
DOS 3.3 floppy out.

```bash
make roms         # rebuild the Apple ROM set (once, see Emulator below)
make run          # assemble -> disk -> boot in MAME -> screenshot
make gui          # same, but leaves the window up so you can drive it
open shots/apple2p/0000.png
```

Boot shows a splash with the OS name and version, reads the disk catalog, and
lands on a desktop: a menu bar with free-space, a file explorer listing the
DOS 3.3 catalog, a draggable window, and an arrow pointer.  A live Forth REPL
sits in the bottom four text lines — `12 34 * .` prints `408`.

`DESK` enters the event loop:

| key | |
|---|---|
| `I` `J` `K` `L` | move the pointer |
| space | click — select a file, raise/carry a window, or close one |
| `T` | lock/unlock the selected file (writes the catalog back) |
| `M` | read the joystick |
| `Q` | leave the event loop |

Boot takes about 32 emulated seconds, most of it compiling the system's own
Forth source (see *Bootstrap cost* below).

## Layout

| path | what |
|---|---|
| `src/forth.s` | top level: cold start, banner, memory map |
| `src/system.fth` | **the OS written in Forth**: windows, explorer, event loop |
| `src/dict.inc` | dictionary format and the macros that build it |
| `src/kernel.inc` | inner interpreter and the primitive word set |
| `src/interp.inc` | outer interpreter, compiler, defining words |
| `src/hires.inc` | the 280×192 screen driver |
| `src/gwords.inc` | Forth bindings for the driver |
| `src/pointer.inc` | XOR mouse pointer, keyboard and joystick input |
| `src/text.inc` | 40x24 text on the hi-res screen |
| `src/disk.inc` | raw sector access through DOS 3.3's RWTS |
| `src/zp.inc` | zero page allocation |
| `test/hirestest.s` | drives the graphics driver from plain assembly |
| `examples/hello.s` | the original 31-byte hello world |
| `tools/dumptext.lua` | dumps the text screen, zero page, and dictionary state |
| `tools/drive.lua` | types lines into the running Forth at a pace it can keep up with |
| `tools/fetch-roms.py` | rebuilds the MAME ROM set from AppleWin and apple2js |
| `tools/mkfont.py` | carves a 7x8 font out of the Apple character ROM |
| `tools/mkboot.py` | converts `system.fth` into a byte table the kernel interprets |

Everything in `src/*.s` is one assembly unit — `forth.s` includes the rest,
because the dictionary is a linked list that has to be chained in a single
pass.

## The kernel

**Direct-threaded.** A thread cell is a code field address, so the inner
interpreter ends in `JMP (W)` and a primitive costs no bytes beyond its own
machine code. A colon definition's code field is `JSR DOCOL`, which leaves
the parameter field address on the hardware stack for `DOCOL` to pick up.

**Registers.** `X` is the data stack pointer and is sacred; anything needing
`X` parks it in `XSAV` first. The data stack is 48 cells in zero page
(`$50-$AF`), addressed as `0,X`/`1,X`. The 6502 hardware stack doubles as
Forth's return stack.

**The outer interpreter is assembly**, not a colon definition. That avoids the
bootstrap problem where the thing that compiles definitions would itself need
compiling. It reaches back into Forth through `DoRun`, a two-cell thread
holding the word to run followed by a primitive that restores `IP` and
`RTS`es to the assembly caller.

**The system's own source is `src/system.fth`**, converted to a byte table by
`tools/mkboot.py` and interpreted at boot before the keyboard is read.
Anything expressible in Forth lives there rather than in assembly — the
windows, the explorer, the event loop, and the boot sequence itself are all
Forth. Definitions must precede their first use, so the file reads
bottom-up: helpers, shapes, the window list, disk, text, explorer, painting,
input, and the boot line last.

### Word set

```
stack     DUP DROP SWAP OVER ROT NIP ?DUP DEPTH >R R> R@ 2DUP 2DROP
maths     + - * U/MOD / MOD /MOD 1+ 1- 2* 2/ NEGATE ABS MIN MAX
logic     AND OR XOR INVERT
compare   = <> < > U< 0= 0<
memory    @ ! C@ C! +!
i/o       EMIT KEY CR SPACE PAGE . ."
control   IF ELSE THEN BEGIN UNTIL AGAIN WHILE REPEAT DO LOOP I EXIT EXECUTE
define    : ; VARIABLE CONSTANT CREATE IMMEDIATE , C, ALLOT HERE ' \
system    STATE BASE DP LATEST WORDS BYE
graphics  HGR HGRFULL TEXT HCLS HCOLOR HPLOT HLINE HVLINE HBOX
hires text TAT TEMIT TINV T."
pointer   PTRSHOW PTRHIDE PTRAT PTRX PTRY MREAD
input     KEY? KEYC BTN PADDLE
disk      RSECT WSECT
memory    CMOVE
windows   HFRAME WINDOW ADDWIN PAINT REPAINT HIT RAISE CLICK PSTEP DESK
files     CATLOAD FREE EXPLORER EPICK FLOCK
```

Numbers accept a leading `-` and a `$` prefix for hex.

## The hi-res driver

280×192, 8K at `$2000`. Two things make it awkward and both are handled by
table lookup rather than arithmetic:

- **Rows are scrambled.** Row *y* lives at
  `$2000 + $400*(y mod 8) + $80*((y/8) mod 8) + $28*(y/64)`, so there is a
  192-entry address table instead of a computation.
- **x is 16-bit.** 280 > 255, so `x/7` (byte column) and `1<<(x mod 7)` (bit
  within it) come from 280-byte tables. 280 is exactly 40×7, so each table is
  just a 7-entry pattern repeated 40 times.

**Colour.** A byte holds 7 pixels in bits 0–6; bit 7 picks the palette. The
pixel pattern shifts by 7 bit positions from one byte to the next, and 7 is
odd, so a two-pixel-period colour pattern inverts every byte column. Each
colour therefore carries two bytes — one for even byte columns, one for odd —
and the driver selects by column parity. Colours are Applesoft's: 0 black,
1 green, 2 violet, 3 white, 4 black2, 5 orange, 6 blue, 7 white2.

A consequence worth knowing: a one-pixel-wide vertical line **cannot be
white**. It comes out green or violet depending on which column it lands in.
That is the hardware, not a bug — the window borders in the demo show it.

`HLINE` stores whole bytes across the middle of a span and only does
read-modify-write on the two end bytes, which is what makes filling fast
enough to be usable. Both span routines order their own endpoints, so a
reversed span can't run the fill loop off the end of a row.

## The pointer

There is **no mouse**. The Apple Mouse Card was a 1984 IIe-era product, and
MAME's `a2mouse` needs four ROMs of which only one exists in any open
repository. The Apple ][+'s pointing device is the analog game port, so that
is what `MREAD` reads — `PREAD` on paddles 0 and 1, scaled to the pointer
area (x by 17/16, y by 19/32), with `BTN` for button 0. The keyboard arrows
(IJKL) drive the same pointer, which is what the demo and the automated tests
use.

The arrow is drawn by XORing an 8×8 shape into the screen and erased by XORing
it again. XOR is self-inverse, so there is no backing store to save and
restore, and the pointer stays legible over both the dark window interiors and
the white title bars because it inverts whatever it covers.

A screen byte holds 7 pixels in bits 0–6, so an 8-pixel-wide row shifted by
0–6 occupies at most 14 bits — always exactly two screen bytes, never three.
That is why `PtrXor` has no third-byte case.

## The windowing layer

All of it is Forth, on top of the driver primitives.

Four records of five cells in `WINS`: `x1 x2 y1 y2` and a spare. **Array order
is z-order** — the last record is the frontmost window. That one decision
makes most of the rest fall out:

- `PAINT` walks the array forward, so later windows naturally overdraw
  earlier ones.
- `HIT` walks it forward and keeps the *last* match, which is the frontmost
  window under the pointer.
- `RAISE` shuffles a record to the end of the array with `CMOVE`.

**There is no backing store under a window.** Everything is redrawn back to
front on every change, which is what makes overlap, raising, dragging, and
closing free. The cost is a full repaint per drag step — see below.

`CLICK` reads the pointer, hit-tests, raises the window, then dispatches on
where in it the click landed: close box → `CLOSEW`, title bar → set `GRAB`,
anywhere else → just raise. `GRAB` holds the index of the window being
carried, or −1. `PSTEP` moves the pointer and, if something is grabbed, shifts
that window by the same delta and repaints.

## Text on the hi-res screen

A screen byte holds 7 pixels and the font is 7 wide, so a character is exactly
one byte column: **40 columns by 24 rows**, and drawing a glyph is eight
stores down consecutive raster rows with no shifting and no read-modify-write.
That alignment is the only reason the font is 7 wide rather than 5.

The glyphs come from the Apple II character generator ROM, carved out at build
time by `tools/mkfont.py`. Its bit order is the mirror of the hi-res screen's,
so every byte is reversed on the way out. `build/font.inc` is a build product
and is not committed — the shapes are Apple's.

Strokes are one pixel wide, so text fringes green and violet depending on
which column it lands in. That is what Apple II hi-res text has always looked
like. `TINV` swaps ink and paper by XORing `$7F`, which is how the menu bar,
the window titles, and the selected file row are highlighted.

## The disk

DOS 3.3 is still resident at `$9600`, so rather than driving the Disk II by
hand the kernel borrows its **RWTS**: `$03E3` hands back DOS's own IOB, already
filled in with slot, drive and device table, and `$03D9` performs whatever the
IOB describes. `RSECT` and `WSECT` expose that to Forth as raw 256-byte
sector reads and writes.

RWTS works entirely below `$0050` in zero page — exactly the region this Forth
was built to keep its hands off from the very first commit. That decision is
what makes calling it safe now, with no shadowing or save/restore.

Everything above sector level is Forth. `CATLOAD` walks the catalog: the VTOC
at track 17 sector 0 names the first catalog sector, each catalog sector names
the next, entries are 35 bytes each starting at offset `$0B`, a `$00` first
byte ends the catalog and `$FF` marks a deletion. Parsed entries go into
`CATBUF` as 36-byte records — type, size, **where the entry came from**
(catalog track, sector, byte offset), and the 30-character name. Keeping the
origin is what lets `FLOCK` write a change back.

`FREE` counts free sectors out of the VTOC's four-byte-per-track bitmap.

## The explorer

Window 0 is the file browser. Its text grid is derived from the window
rectangle rather than hardcoded, so it stays correct if the window moves; the
window's top edge is a multiple of 8 so its title bar lands exactly on a text
row.

Clicking it selects a file rather than raising or dragging, which is also why
it never leaves the back of the z-order — everything else can be raised over
it. `T` toggles the lock bit on the selected file: read the catalog sector,
flip bit 7 of the type byte, write the sector back, reload. That is the only
thing in the system that writes to the disk.

## Memory map

| range | what |
|---|---|
| `$0800-$0FFF` | one raw disk sector |
| `$1000-$1FFF` | the parsed catalog, 36 bytes per file |
| `$2000-$3FFF` | hi-res page 1, the visible screen |
| `$4000-$6E9x` | the kernel |
| `$6E9x-$92FF` | dictionary, growing upward |
| `$9300-$95FF` | DOS 3.3 file buffer (one, see below) |
| `$9600-$BFFF` | DOS 3.3 |

The disk's greeting issues `MAXFILES 1` before `BRUN`, which drops DOS from
three file buffers to one and hands about 2K back to the dictionary.

Hi-res page 2 used to sit at `$4000` as a would-be back buffer; the OS needs
the room more than it needs double buffering.

Zero page: `$00-$4F` is left alone (the monitor's text window state and DOS's
RWTS live there, and we call both). `$50-$DF` was Applesoft's, and Forth
replaces Applesoft, so it is all ours. The data stack occupies `$50-$9F` and
**`$A0-$AF` is a deliberate gap** — the deepest primitive reaches `7,X`, so an
empty-stack fetch lands in the gap rather than on `IP`. Without it, `@` on an
empty stack stores its result *into* `IP` and the inner interpreter jumps
somewhere random: a mistyped line has to produce an error, not a crash.

## Bootstrap cost

Boot is about 32 emulated seconds, and roughly two thirds of that is
compiling `system.fth`. `FindWord` is a linear scan of a linked list that
reaches ~210 entries — around 10 ms per token — and the source is well over
two thousand tokens. Nothing is wrong; it is just an unindexed dictionary.

The kernel primitives are defined first, so they sit at the *tail* of the
chain and every lookup of `+` or `@` walks the entire list. If boot time
starts to matter, that is the thing to attack: a hash or a per-length bucket
chain would cut it by an order of magnitude.

A repaint (desktop fill plus three windows) is roughly half a second, so
dragging is chunky. Hi-res page 2 at `$4000` is untouched and is the obvious
place to double-buffer.

## Debugging

Reading characters off a screenshot is guesswork. `tools/dumptext.lua` prints
the actual text screen bytes, zero page, and the dictionary state (`DP`,
`LATEST`, `STATE`, whether the link chain terminates, and the newest
definitions — the first name is whatever was being compiled if `STATE` is
non-zero):

```bash
mame apple2p -rompath ./roms -sl4 "" -gameio joy -flop1 build/forth.dsk \
  -skip_gameinfo -window -nothrottle -seconds_to_run 40 \
  -autoboot_delay 0 -autoboot_script tools/dumptext.lua
```

`-autoboot_command` types at a fixed rate, and the Apple II keyboard has no
buffer — a new keypress simply overwrites the last — so anything typed while
Forth is busy interpreting is **silently lost**, which looks exactly like a
logic bug. `tools/drive.lua` posts one line, waits, then posts the next:

```bash
DRIVE='140 92 PTRAT CLICK GRAB @ .;;-30 0 PSTEP;;2 .X1 @ .' START=1700 GAP=420 \
mame apple2p -rompath ./roms -sl4 "" -gameio joy -flop1 build/forth.dsk \
  -skip_gameinfo -window -nothrottle -seconds_to_run 60 \
  -autoboot_delay 0 -autoboot_script tools/drive.lua
```

It waits for the system to actually be ready rather than guessing: the
kernel's bootstrap source pointer (`SRC+1` at `$CF`) is non-zero while the
built-in source is being interpreted and drops to zero when the interpreter
turns to the keyboard — exactly when the prompt appears. `GAP` is the frames
between lines; widen it for lines that repaint or touch the disk. Single
characters work too, so the event loop can be driven key by key:
`DRIVE='DESK;;K;; ;;J;;J;;Q'`. `PEEK='0x2285,0x2685'` dumps memory at the end,
which is how the font blitter was verified byte for byte.

Two flag-clobber bugs cost most of the debugging time on this system, both
the same shape — a flag set, then an unrelated instruction between it and the
branch:

```
ora 1,x        ; Z now says whether TOS is zero
inx            ; ...and INX just overwrote it with "is X zero"
inx
beq DoBranch   ; never taken
```

That was `0BRANCH`, so `IF` never branched and every conditional body always
ran. The other was `LDX XSAV` before `BMI` in `(LOOP)`, which made every
counted loop infinite. Both looked like higher-level logic errors. If
something conditional misbehaves here, check the instruction between the test
and the branch first.

## Build system

```
src/system.fth ─mkboot.py─┐
roms/…341-0036.chr ─mkfont.py─┤
                              ├→ ca65 → ld65 → forth.bin → a2kit → .dsk → MAME
src/*.s src/*.inc ────────────┘
```

The disk carries the OS binary, an Applesoft greeting that sets `MAXFILES 1`
and `BRUN`s it, `SYSTEM.FTH` (the OS's own source), and a `README` — so the
explorer has a real catalog to browse.

| knob | default | meaning |
|---|---|---|
| `PROG` | `forth` | output binary/disk name |
| `SRCDIR` | `src` | which directory to assemble |
| `ORG` | `0x4000` | load address |
| `SECS` | `32` | emulated seconds before auto-exit (boot needs ~32) |

```bash
make run                                          # the Forth system
make run PROG=hirestest SRCDIR=test               # the driver test
make run PROG=hello SRCDIR=examples ORG=0x0800    # hello world
```

`make run` boots unthrottled (~15x) and exits after `SECS` emulated seconds,
dropping a PNG in `shots/`. Emulation is deterministic, so unthrottling
changes only wall-clock pacing. `make gui` runs at true 1 MHz for interactive
work.

### Conventions

- **Entry point goes in `.segment "STARTUP"`**, which links first so it lands
  exactly at `ORG` regardless of how many source files there are.
- **Exit with `jmp $03D0`, not `rts`** — `BRUN` loads the binary over the
  Applesoft greeting, so there is no BASIC program to return into. The
  Makefile defines `DOS` (`ca65 -D DOS=1`) so sources can tell which path they
  were built for.
- **High ASCII.** The text screen wants the high bit set: `'H'` is `$C8`.

### Disk

`make disk` produces a bootable DOS 3.3 image holding a one-line Applesoft
greeting that `BRUN`s the binary. It is a standard DOS-order `.dsk`, so it
also runs in other emulators or on real hardware via ADTPro. Inspect it with
`a2kit catalog -d build/forth.dsk`.

## Emulator

MAME's `apple2p` driver (Apple ][+, 48K). MAME ships no Apple ROMs and
**neither does this repository** — they are not ours to redistribute. Rebuild
them:

```bash
make roms
```

That reconstructs all nine from two GPL projects and refuses to finish unless
every CRC32 matches what MAME expects:

- **AppleWin** carries the six 2K system ROMs (as one 12K image), the
  character generator, and the Disk II boot PROM.
- **apple2js** carries the Disk II logic-state sequencer, transcribed from
  *Understanding the Apple IIe* rather than dumped. It indexes the table by
  (state, input); the physical PROM wires those bits to its address lines in
  a different order, so the script searches all 8! orderings for the one whose
  CRC matches. It is the same data, re-addressed.

Check the result independently with:

```bash
mame -rompath ./roms -verifyroms apple2p
```

The only ROM reported missing is `sc01a.bin`, the Votrax speech chip on the
Mockingboard in slot 4, which `-sl4 ""` removes.

| tool | role |
|---|---|
| `ca65` / `ld65` (cc65) | 6502 assembler and linker |
| `a2kit` | disk images, file import, Applesoft tokenising |
| `mame` | the Apple ][+ itself |
