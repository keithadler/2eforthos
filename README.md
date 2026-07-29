# 2E FORTH OS

(C) 2026 Keith Adler

A Forth system that boots to an **80-column console** on an emulated Apple
//e, with a **560x192 monochrome double hi-res** screen the language can turn
on when a program wants it.  6502 source in, bootable floppy out — no DOS on
the disk and none in memory.

```bash
make roms         # rebuild the Apple ROM set (once, see Emulator below)
make run          # assemble -> disk -> boot in MAME -> screenshot
make gui          # same, but leaves the window up so you can drive it
open shots/apple2ee/0000.png
```

Boot prints the banner, reads the disk catalog, and stops at the Forth
prompt in 80 columns.  `12 34 * .` prints `408`.

| command | |
|---|---|
| `CAT` | list the disk — number, lock, name, type, size |
| `n LOCK` | lock or unlock file *n* |
| `n DEL` | delete it (refused if locked) |
| `n REN` | rename it — type the new name at the prompt |
| `WORDS` | every definition in the dictionary |
| `HELP` | a summary of the above and the graphics words |

The graphics screen is a **word, not a mode you live in**: `HGR` turns it on,
the drawing words draw, `TEXT` comes back to the console.

```forth
HGR  3 HCOLOR  280 96 80 HCIRCLE  40 520 20 170 HFRAME
0 0 TAT T." DRAWN FROM THE PROMPT"
TEXT
```

**The OS writes to its own disk.** Lock, rename and delete all go through to
the image, and MAME writes it back — delete a file inside the emulator and
`a2kit catalog -d build/forth.dsk` on the host agrees it is gone. `make run`
therefore boots a scratch copy so automated runs stay reproducible; `make gui`
uses the real image, so changes you make interactively stick.

Boot takes about 18 emulated seconds, most of it compiling the system's own
Forth source (see *Boot cost* below).

![the console at boot](docs/images/console-boot.png)

![interference patterns from the MOIRE demo](docs/images/demo-moire.png)

## Documentation

| | |
|---|---|
| [docs/LANGUAGE.md](docs/LANGUAGE.md) | the whole word set, 310 of them, with stack effects |
| [docs/DEMOS.md](docs/DEMOS.md) | the six programs on the disk, with screenshots and source |
| this file | how it is built and why it works the way it does |

## Layout

| path | what |
|---|---|
| `src/forth.s` | top level: cold start, banner, memory map |
| `src/system.fth` | **the OS written in Forth**: catalog, file commands, greeting |
| `src/dict.inc` | dictionary format and the macros that build it |
| `src/kernel.inc` | inner interpreter and the primitive word set |
| `src/interp.inc` | outer interpreter, compiler, defining words |
| `src/hires.inc` | the 560x192 double hi-res driver |
| `src/gwords.inc` | Forth bindings for the driver |
| `src/input.inc` | keyboard and game port, as Forth words |
| `src/math.inc` | 16x16 multiply, 32/16 divide, shifts, bulk memory |
| `src/compile.inc` | DOES>, the rest of the loop set, strings, FORGET |
| `src/fill.inc` | flood fill and bitmap drawing |
| `src/sound.inc` | the speaker, and the two ways to tell the time |
| `src/text.inc` | 80x24 text on the hi-res screen |
| `src/d2core.inc` | the Disk II driver: seek, read, write, 6-and-2 |
| `src/diskii.inc` | Forth bindings for it (`DREAD`, `DWRITE`) |
| `src/zp.inc` | zero page allocation |
| `disk/*.FTH` | the demos, put on the floppy by `make disk` |
| `docs/LANGUAGE.md` | every word, with stack effects |
| `docs/DEMOS.md` | the demo gallery |
| `test/hirestest.s` | drives the graphics driver from plain assembly, no Forth |
| `examples/hello.s` | the original 31-byte hello world, from before any of this |
| `tools/contest.py` | the console test suite — types Forth, checks machine state |
| `tools/contest.lua` | the MAME side of it |
| `tools/dumptext.lua` | dumps the text screen, zero page, and dictionary state |
| `tools/drive.lua` | types lines into the running Forth at a pace it can keep up with |
| `tools/fetch-roms.py` | rebuilds the MAME ROM set from AppleWin and apple2js |
| `tools/mkfont.py` | carves a 7x8 font out of the Apple character ROM |
| `tools/mkboot.py` | converts `system.fth` into a byte table the kernel interprets |
| `tools/mkkbdrom.py` | generates the //e keyboard decoder ROM |

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

310 words. `/` `MOD` `/MOD` `*/MOD` and `FM/MOD` are **floored** — the
quotient rounds toward negative infinity and the remainder takes the sign of
the divisor, so `-10 3 /MOD` gives 2 and −4. `SM/REM` truncates toward zero
instead, and is there when that is what you want.

**The system's own source is `src/system.fth`**, converted to a byte table by
`tools/mkboot.py` and interpreted at boot before the keyboard is read.
Anything expressible in Forth lives there rather than in assembly — the
catalog parser, the file commands, and the greeting itself are all Forth.
Definitions must precede their first use, so the file reads top-down:
helpers, shapes, the catalog, the file commands, and the greeting last.

One consequence worth knowing: `."` **compiles** an inline string, so at the
top level it builds one nobody runs. The banner is a definition (`GREET`)
that is then called.

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
stack2    -ROT TUCK 2SWAP 2OVER PICK ROLL 2>R 2R> 2R@
maths2    UM* UM/MOD M* SM/REM FM/MOD */ */MOD S>D LSHIFT RSHIFT
double    D+ D- DNEGATE DABS D.
memory    @ ! C@ C! +! 2@ 2! CMOVE MOVE FILL ERASE BLANK COUNT WITHIN
          CELL+ CELLS CHAR+ CHARS ALIGN ALIGNED >BODY
loops     DO ?DO LOOP +LOOP I J LEAVE UNLOOP
compile   [ ] LITERAL POSTPONE ['] [CHAR] CHAR COMPILE, RECURSE DOES>
          IMMEDIATE ( \
strings   ." S" C" ABORT" TYPE -TRAILING
output    . U. .R U.R ? .S <# # #S #> HOLD SIGN
control2  CASE OF ENDOF ENDCASE ABORT
system2   FORGET WORDS BYE
graphics  HGR TEXT HCLS HCOLOR HXOR HPLOT HLINE HVLINE HLINE2 HBOX
          HPOINT HCIRCLE HDISC HFRAME HFILL BLIT
hires text TAT TEMIT TINV T."
input     KEY? KEYC BTN PADDLE
sound     CLICK TONE
timing    MS VBL
disk      DREAD DWRITE
console   CAT LOCK DEL REN LOAD SAVE BSAVE BLOAD HELP
banks     AUXBANK MAINBANK
files     CATLOAD FREE ASKLN
```

Numbers accept a leading `-` and a `$` prefix for hex.

## The double hi-res driver

560×192 monochrome. Double hi-res doubles the horizontal resolution by
fetching **two bytes per position** — one from auxiliary memory, one from
main. A row of 80 byte columns is interleaved

```
aux[0] main[0] aux[1] main[1] ... aux[39] main[39]
```

so byte column *c* lives at `HGRROW[y] + (c >> 1)`, in aux when *c* is even
and main when it is odd. Each byte still carries 7 pixels in bits 0–6.

**Choosing the bank is a soft switch, not an address.** With `80STORE` set,
`$C055` points `$2000-$3FFF` at aux and `$C054` at main. Every routine leaves
main selected on the way out, because `80STORE` also makes that same switch
control the text page at `$0400-$07FF` — leave aux selected and the monitor's
output goes somewhere the display never looks.

Two things about the geometry are handled by table lookup rather than
arithmetic:

- **Rows are scrambled.** Row *y* lives at
  `$2000 + $400*(y mod 8) + $80*((y/8) mod 8) + $28*(y/64)` — the same address
  in both banks — so there is a 192-entry table instead of a computation.
- **x is 16-bit.** `x/7`, `1<<(x mod 7)` and `x mod 7` come from 560-byte
  tables. 560 is exactly 80×7, so each is a 7-entry pattern repeated 80 times.

**Monochrome simplifies things.** In double hi-res bit 7 is not a palette bit
and is simply unused, so there is none of the ][+'s colour-fringing
arithmetic: a one-pixel vertical line really is white. What used to be the
colour table is now a **dither** table — a pattern byte for each phase, giving
black, two greys and white. The phase alternates along *both* axes (`column
XOR row`); alternating by column alone turns a 50% pattern into vertical
stripes instead of grey.

`HLINE` stores whole bytes across the middle of a span and only does
read-modify-write on the two end bytes. Both span routines order their own
endpoints, so a reversed span can't run the fill loop off the end of a row.

## The console

The //e has an 80-column driver in ROM. Entering it is `JSR $FB2F` then
`JSR $C300`, and it costs nothing in the image: it scrolls both banks, keeps
the cursor, and understands the monitor's control codes. It takes over `CSW`
and `KSW`, so **nothing may set those afterwards** — `COUT` and `GETLN` reach
the firmware through them, and writing the ROM's own vectors back there
disconnects the console without any other symptom.

Text lives in `$0400-$07FF` in *both* banks: even columns in aux, odd in main.
Two soft switches make that work, and both matter on the way back from
graphics:

- `80COL` is what makes the video hardware fetch the aux half of a row.
- `80STORE` is what lets the firmware write it.

Clearing either on the way out of `HGR` leaves the screen showing main memory
alone — every other character of every line, which is exactly what an
80-column screen displayed 40 columns wide looks like. `HgrText` sets both.

## The graphics screen

There is no windowing environment. `HGR` switches the display to double
hi-res and clears it, the drawing words draw, and `TEXT` puts the console
back; between those two the whole 560×192 screen belongs to whatever is being
written.

`HXOR` makes every drawing word XOR what it draws rather than replace it, so
drawing a shape twice leaves the screen as it was found. That touches two
paths in the driver, because they write differently: `MergeByte` skips its
read so the masked bits flip rather than take the pattern, and `HgrHLine`'s
solid middle bytes — which bypass `MergeByte` entirely for speed — EOR
instead of store.

## Text on the graphics screen

A screen byte holds 7 pixels and the font is 7 wide, so a character is exactly
one byte column: **80 columns by 24 rows**, and drawing a glyph is eight
stores down consecutive raster rows with no shifting and no
read-modify-write. That alignment is the only reason the font is 7 wide
rather than 5, and it is what makes double hi-res give a full 80 columns.
The bank is fixed for a whole character, so it is chosen once per glyph.

The glyphs come from the Apple II character generator ROM, carved out at build
time by `tools/mkfont.py`. Its bit order is the mirror of the hi-res screen's,
so every byte is reversed on the way out. `build/font.inc` is a build product
and is not committed — the shapes are Apple's.

`TINV` swaps ink and paper by XORing `$7F`, which is how the menu bar, the
window titles, and the selected file row are highlighted.

## The disk

**There is no DOS**, on the disk or in memory. `src/d2core.inc` drives the
Disk II directly — phase stepping, 4-and-4 address fields, 6-and-2 data — and
`DREAD` and `DWRITE` expose it to Forth as raw 256-byte sector reads and
writes. A DOS 3.3 *filesystem* is still what is on the floppy, so the image
stays readable by anything else; what went away is DOS the program.

Everything above sector level is Forth. `CATLOAD` walks the catalog: the VTOC
at track 17 sector 0 names the first catalog sector, each catalog sector names
the next, entries are 35 bytes each starting at offset `$0B`, a `$00` first
byte ends the catalog and `$FF` marks a deletion. Parsed entries go into
`CATBUF` as 36-byte records — type, size, **where the entry came from**
(catalog track, sector, byte offset), and the 30-character name. Keeping the
origin is what lets `FLOCK` write a change back.

`FREE` counts free sectors out of the VTOC's four-byte-per-track bitmap.

**DOS numbers sectors in a different order from the one they are laid down
in**: physical sector *P* of a track holds DOS sector
`0,7,14,6,13,5,12,4,11,3,10,2,9,1,8,15`. `DREAD` and `DWRITE` translate, and
`D2ReadSector` keeps speaking physical numbers because that is what the boot
loader wants.

That translation was missing for a long time and nothing noticed, because 0
and 15 are the two fixed points of the permutation — and the VTOC is sector 0
and the first catalog sector is 15. Every read the system did worked until the
first one that reached a file's own data.

`FLOCK` is now `LOCK`, and the rest are `DEL` and `REN`; each takes the number
`CAT` printed, and refuses an index outside the catalog rather than trusting
it, because every one of them writes to the disk.

## Flood fill and bitmaps

`x y HFILL` fills by scanlines, not by pixels: the seed stack holds one entry
per run rather than one per pixel, and each run is drawn with `HgrHLine`,
which writes whole bytes in the middle. That is the only reason a large area
finishes at all — the scanning either side of a run is still per-pixel, so
filling something the size of the screen takes tens of seconds.

What it fills is the connected region of pixels **matching the seed**, and it
fills them with the opposite value. Defining it that way rather than "fill
with `HCOLOR`" is what makes it terminate: a dithered pattern leaves some of
the pixels it writes still matching the seed, and those seed the fill again
for as long as you care to wait. Filling with black is the same word with the
seed on a white region.

`addr w h x y BLIT` draws a bitmap: rows of whole bytes, eight pixels each,
bit 0 leftmost. A set bit plots in the current colour and a clear bit leaves
the screen alone, so a shape is drawn without a mask. With `HXOR` on, drawing
it twice puts the screen back.

## Writing files

`addr len SAVE` and `addr len BSAVE` ask for a name and create a DOS file:
sectors marked used in the VTOC, a track/sector list naming them, the data,
and a catalog entry pointing at the list. Nothing is written until all four
are ready except the data sectors, which are harmless on their own — an
interrupted save leaks sectors rather than corrupting the catalog. `BSAVE`
writes DOS's four-byte header (load address, then length) and `n addr BLOAD`
steps it back off and returns the length.

## Loading source from the disk

`n LOAD` reads a text file off the floppy and interprets it, which is what
makes anything typed at the console survivable — write it to a file, load it
back.

Setting the kernel's own source pointer is all it takes: the outer
interpreter already prefers that source to the keyboard and drops back to the
keyboard at the first zero byte, which is exactly a file's end.

The text goes on **hi-res page 1**, which costs no dictionary at all — and
that matters, because the definitions the file makes have to fit somewhere.
Turning the graphics screen on while a file is still being read overwrites
what is left of it.

That buffer needs care. `80STORE` is set for the console, and with `80STORE`
set `$2000-$3FFF` follows `PAGE2` — which the 80-column firmware toggles on
every character it prints. `Refill` puts `PAGE2` back to main once per line
before it reads; the firmware sets it again for itself the next time it
prints. Without that the buffer moves out from under the interpreter
mid-line, which is exactly what it looked like.

One file at a time: a load inside a load would move the ground under the first.

## The file commands

The three operations that change the disk all work the same way: read the
catalog sector the entry came from, edit it, write it back, reload. Keeping
each parsed entry's **origin** — catalog track, sector and byte offset — is
what makes that possible.

- **Lock** flips bit 7 of the type byte.
- **Rename** rewrites the 30-byte name field, high-bit set and space padded,
  from a line read with `ASKLN`. That word copies the typed text straight out
  of `TIB` into its own buffer, because `TIB` is also the outer interpreter's
  input buffer.
- **Delete** is the involved one. It walks the file's track/sector list
  freeing every data sector in the VTOC bitmap, then the list sectors
  themselves, then marks the entry the way DOS does — the first track byte
  moves to the last byte of the name and `$FF` takes its place — and writes
  both the catalog sector and the VTOC back. A locked file is refused, which
  is what the lock is for.

A track byte of zero means an unused slot in a track/sector list, which is
unambiguous because track 0 holds the boot loader and is never allocated to a
file.

## Example programs

Three kinds, in increasing order of how much of the system they need:

| | |
|---|---|
| `examples/hello.s` | 31 bytes of 6502 that prints a string through the monitor ROM. Where this started. |
| `test/hirestest.s` | drives `hires.inc` directly — no Forth, no disk, just the screen driver and a diagonal. |
| `disk/*.FTH` | six Forth programs on the floppy, below. |

Both assembly ones still build:

```bash
ca65 -I src -I build examples/hello.s -o /tmp/h.o
ca65 -I src -I build test/hirestest.s -o /tmp/ht.o
```

## The demos on the disk

Six Forth programs ship on the floppy. `CAT` lists them; `n LOAD` reads one
in and tells you what to type. [docs/DEMOS.md](docs/DEMOS.md) has the source
and a screenshot of each.

| | |
|---|---|
| `GFX` | shapes, flood fill, a sprite, text on the graphics screen |
| `MOIRE` `BANDS` | XOR interference patterns; the eight dither colours |
| `BOUNCE` | an XOR sprite animation paced off the video counter |
| `PRIMES` | loops and right-justified output |
| `DEMO` | `CREATE ... DOES>` and `CASE` |
| `SCALE` `CHIRP` `SIREN` | the speaker |

Each defines a marker as its first word, so `FORGET GFX--` and friends give
the space back. With about 1.1K of dictionary free, it is one demo at a time.

![HELP on the machine](docs/images/console-help.png)

## Memory map

| range | what |
|---|---|
| `$0400-$07FF` | the text screen, in **both** banks — even columns in aux, odd in main |
| `$0800-$0FFF` | one raw disk sector |
| `$1000-$1FFF` | the parsed catalog, 36 bytes per file |
| `$2000-$3FFF` | hi-res page 1 — in **both** banks; aux and main interleave byte by byte to make 560 pixels per row |
| `$1900-$1CBF` | fill seed stack and the two line buffers |
| `$4000-$9E50` | the kernel |
| `$9E51-$BFFF` | dictionary, growing upward |

The kernel and the dictionary share one 32K region, so moving something from
one to the other gains nothing — the only wins are code that is smaller or
RAM that is somewhere else. The fill's seed stack and the two line buffers
therefore live above the catalog: `CATBUF` is a page-aligned `$1000-$1FFF`
but only sixty 36-byte records deep, so everything past `$186F` was going
begging. That is worth about 950 bytes of dictionary.

**A fresh boot leaves about 1.1K free.** That is enough to work in and not
much more; the language is now large enough that it, rather than the kernel,
is what fills the machine. The next real gain would have to come from the
language card.

Zero page: `$00-$4F` is left alone — the monitor's text window state and the
80-column firmware's own variables live there, and the console calls both on
every line typed. `$50-$DF` was Applesoft's, and Forth replaces Applesoft, so
it is all ours. The data stack occupies `$50-$9F` and **`$A0-$AF` is a
deliberate gap** — the deepest primitive reaches `7,X`, so an empty-stack
fetch lands in the gap rather than on `IP`. Without it, `@` on an empty stack
stores its result *into* `IP` and the inner interpreter jumps somewhere
random: a mistyped line has to produce an error, not a crash.

## Boot cost

About 18 emulated seconds, nearly all of it compiling `system.fth`. The
history is worth recording, because two of the three attempts at this were
aimed at the wrong thing:

- **Indexing the dictionary** cut compiling from ~28s to ~11s. `FindWord` was
  a linear scan of a linked list that reached ~210 entries, and the kernel
  primitives are defined first, so every lookup of `+` or `@` walked the whole
  chain. It is now hashed into 16 buckets on the first character and length.
- **Bypassing DOS's file manager** to load the kernel produced no measurable
  gain, because loading was never the cost.
- **Dropping DOS entirely** — a boot sector that pulls the kernel off track 0
  with the system's own Disk II driver — took ~24s off the front, because a
  DOS boot cost the same whether it then ran a 2-sector binary or a 15K one.
  It also handed back the 10K DOS occupied at `$9600-$BFFF`.

Removing the windowing environment took the image from 23233 bytes to 15577
and the boot from ~28 emulated seconds to ~18. Filling the language back out
to 310 words put it at 24145 bytes and ~31 seconds — the extra time is
compiling the Forth half of the word set, not loading it.

`make gui SPEED=8` boots in about two seconds.

## Testing

`make test` types Forth at the console and checks **machine state**, not the
screen: a screenshot tells you something changed, the data stack tells you
what the system believes. `X` is the stack pointer and the top level parks it
in `XSAV` before waiting for a line, so while the prompt is up the whole stack
can be read out of zero page.

```bash
make test                # everything: 38 tests, ~2 minutes
make test T="arith xor"  # named tests
python3 tools/contest.py --list
```

The suite runs **headless** (`-video none -sound none`). It reads memory
rather than the screen, so a window would only steal focus once per test.

Three things about the harness were worth more than they cost:

- **`natkeyboard:post` types over many frames.** Guessing how long put every
  assertion a line behind; `natkeyboard.is_posting` says when it is done.
- **Readiness waits for a variable, not a frame count.** `NFREE` is filled by
  the greeting, so a non-zero `NFREE` means the console is up — and growing
  the image no longer moves the finish line.
- **An ioport field does not stay written.** Anything driving the game port
  has to reassert it every frame, or an input lands or is missed depending on
  which frame it fell on.
- **A step that touches the disk needs to be waited for.** Sampling the stack
  forty frames after a line was typed catches a word that seeks the head
  half-finished, and a half-finished word looks exactly like a wrong one. A
  flood fill needs longer still.
- **Reading a graphics address from the test harness only sees main memory.**
  Even byte columns are in aux, so a check aimed at one reads zero however
  well the drawing worked. Scan a wide range, or aim at an odd column.
- **Scratch addresses in the tests must be below the kernel.** `$0D00-$0FFF`
  is the only RAM the system leaves alone. Anything above `$4000` is kernel
  or dictionary and moves as the system grows, which is how a working test
  started failing.

## Debugging

Reading characters off a screenshot is guesswork. `tools/dumptext.lua` prints
zero page and the dictionary state (`DP`, `LATEST`, `STATE`, whether the link
chain terminates, and the newest definitions — the first name is whatever was
being compiled if `STATE` is non-zero). Its screen dump now shows only the
**odd** columns, since it reads main memory and the console keeps the even
ones in aux:

```bash
mame apple2ee -rompath ./roms -sl4 "" -flop1 build/forth.dsk \
  -skip_gameinfo -window -nothrottle -seconds_to_run 40 \
  -autoboot_delay 0 -autoboot_script tools/dumptext.lua
```

`-autoboot_command` types at a fixed rate, and the Apple II keyboard has no
buffer — a new keypress simply overwrites the last — so anything typed while
Forth is busy interpreting is **silently lost**, which looks exactly like a
logic bug. That is what `tools/contest.lua` exists to get right; for one-off
poking, `tools/drive.lua` posts one line, waits, then posts the next:

```bash
DRIVE='2 3 + .;;HGR;;3 HCOLOR 0 559 96 HLINE;;TEXT' START=1200 GAP=240 \
mame apple2ee -rompath ./roms -sl4 "" -flop1 build/forth.dsk \
  -skip_gameinfo -window -nothrottle -seconds_to_run 60 \
  -autoboot_delay 0 -autoboot_script tools/drive.lua
```

It waits for the system to be ready rather than guessing: the kernel's
bootstrap source pointer (`SRC+1`) is non-zero while the built-in source is
being interpreted and drops to zero when the interpreter turns to the
keyboard — exactly when the prompt appears. `GAP` is the frames between
lines; widen it for lines that touch the disk.

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

The disk carries **its own boot sector** on track 0, the kernel on the tracks
after it, and a DOS 3.3 filesystem holding `SYSTEM.FTH` (the OS's own source)
and a few text files — so `CAT` has a real catalog to list. There is no DOS
and no Applesoft greeting: the boot PROM loads `boot/boot1.s`, which reads the
kernel with the same Disk II driver the system uses afterwards.

| knob | default | meaning |
|---|---|---|
| `PROG` | `forth` | output binary/disk name |
| `MACHINE` | `apple2ee` | MAME driver (`apple2p` still builds for the ][+ tests) |
| `MONITOR` | `4` | MAME monitor type — 4 is B&W, 0 is colour |
| `SRCDIR` | `src` | which directory to assemble |
| `ORG` | `0x4000` | load address |
| `SECS` | `32` | emulated seconds before auto-exit (boot needs ~18) |

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
- **High ASCII.** The text screen wants the high bit set: `'H'` is `$C8`.

### Disk

`make disk` produces a bootable image: own boot sector, kernel, and a DOS 3.3
filesystem for the files. It is a standard DOS-order `.dsk`, so it also runs
in other emulators or on real hardware via ADTPro. Inspect the filesystem
side with `a2kit catalog -d build/forth.dsk`.

## Emulator

MAME's `apple2ee` driver (enhanced Apple //e). MAME already makes the
Extended 80-column card the default aux device, so 128K and double hi-res are
standard — no extra ROM for either. MAME ships no Apple ROMs and **neither
does this repository** — they are not ours to redistribute. Rebuild them:

```bash
make roms
```

Everything downloaded is CRC-checked against what MAME expects, and the script
refuses to finish on a mismatch:

- **AppleWin** carries the //e main ROMs (as one 16K image) and the mousetext
  character generator, plus the ][+ system ROMs and the Disk II boot PROM.
- **apple2js** carries the Disk II logic-state sequencer, transcribed from
  *Understanding the Apple IIe* rather than dumped. It indexes the table by
  (state, input); the physical PROM wires those bits to its address lines in
  a different order, so the script searches all 8! orderings for the one whose
  CRC matches. Same data, re-addressed.

### The keyboard ROM

One file is **generated, not downloaded**: `341-0132-d.e12`, the //e keyboard
decoder. No open project ships that dump — GitHub turns up only references to
it, including MAME's own source and Mednafen's documentation listing its
SHA-256. With a blank stand-in the machine boots perfectly and the keyboard is
completely dead.

It does not have to be Apple's dump, though, because MAME uses it as a plain
lookup (`apple2e.cpp`, `ay3600_data_ready_w`):

```
address = key << 2 | !shift | !ctrl << 1 | !capslock << 9
ascii   = kbdrom[address]
```

with `key = row * 10 + column` (`kb3600.cpp`). `tools/mkkbdrom.py` builds a
table that decodes correctly from the published North American //e matrix.

A detail that cost a debugging round: the matrix must follow MAME's **`PORT_CHAR`
assignments**, not the ASCII-art comment above them — the two disagree about
N and M, and the ports are what MAME actually scans. Get it wrong and keys
come out as their neighbours.

MAME prints a checksum warning for this file on startup. That is cosmetic; the
keyboard works. Drop a real dump over the top and the warning goes away.

Check the result independently with:

```bash
mame -rompath ./roms -verifyroms apple2p    # the ][+ set is complete
mame -rompath ./roms -verifyroms apple2ee   # warns on the generated keyboard
```

The other ROM reported missing is `sc01a.bin`, the Votrax speech chip on the
Mockingboard in slot 4, which `-sl4 ""` removes.

### Monochrome

Double hi-res is a colour mode by default, and one-pixel strokes fringe badly.
MAME's per-machine **Monitor type** config selects B&W; `make monitor` writes
that setting into `cfg/$(MACHINE).cfg` before every run, which is what makes
560×192 read as 560 monochrome pixels. Override with `MONITOR=0` for colour.

| tool | role |
|---|---|
| `ca65` / `ld65` (cc65) | 6502 assembler and linker |
| `a2kit` | disk images, file import, Applesoft tokenising |
| `mame` | the Apple ][+ itself |
