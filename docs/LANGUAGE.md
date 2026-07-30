# The 2E Forth OS language

310 words. This is the whole reference; `HELP` on the machine prints a
condensed version of it.

Notation is the usual Forth stack comment, `( before -- after )`, with the top
of the stack on the right. `n` is a signed cell, `u` unsigned, `d` a
double-cell (two cells, low pushed first, so the high cell is the one on
top), `addr` an address, `c` a character, `flag` is `0` for false and `-1`
for true.

A cell is two bytes. A character is one. Nothing needs alignment on a 6502,
so `ALIGN` and `ALIGNED` are here to be spelled rather than to act.

---

## Contents

- [Numbers and the interpreter](#numbers-and-the-interpreter)
- [Stack](#stack)
- [Return stack](#return-stack)
- [Arithmetic](#arithmetic)
- [Mixed and double precision](#mixed-and-double-precision)
- [Logic and comparison](#logic-and-comparison)
- [Memory](#memory)
- [Defining words](#defining-words)
- [Compiling](#compiling)
- [Control flow](#control-flow)
- [Text and numbers out](#text-and-numbers-out)
- [Input](#input)
- [Floating point](#floating-point)
- [The graphics screen](#the-graphics-screen)
- [The lo-res screen](#the-lo-res-screen)
- [Text on the graphics screen](#text-on-the-graphics-screen)
- [Sound and timing](#sound-and-timing)
- [The disk](#the-disk)
- [Files](#files)
- [Inline tables of numbers](#inline-tables-of-numbers)
- [Calling machine code](#calling-machine-code)
- [Random](#random)
- [Looking at things](#looking-at-things)
- [Precompiled overlays](#precompiled-overlays)
- [System variables and internals](#system-variables-and-internals)

---

## Numbers and the interpreter

Numbers are read in `BASE`, which starts at 10. A leading `$` reads hex
whatever `BASE` says, so `$C030` always means what it looks like. A leading
`-` negates.

Input is folded to upper case as it is read, because every name in the
dictionary is upper case. That also means a string typed at the prompt
arrives in upper case; strings *compiled* from a loaded file keep their case,
since a file is not folded.

The interpreter reads a word, looks it up, and either runs it or compiles it
depending on `STATE`. A word it cannot find it tries to read as a number; if
that fails too it echoes the word with a `?` and abandons the line.

The data stack holds 40 cells. A line that pops more than it pushes is caught
at the end of the line — `STACK?` — rather than being left to run wild.

---

## Stack

| Word | Effect | |
|---|---|---|
| `DUP` | `( x -- x x )` | |
| `?DUP` | `( x -- 0 \| x x )` | duplicates only if non-zero |
| `DROP` | `( x -- )` | |
| `SWAP` | `( x1 x2 -- x2 x1 )` | |
| `OVER` | `( x1 x2 -- x1 x2 x1 )` | |
| `TUCK` | `( x1 x2 -- x2 x1 x2 )` | |
| `NIP` | `( x1 x2 -- x2 )` | |
| `ROT` | `( x1 x2 x3 -- x2 x3 x1 )` | |
| `-ROT` | `( x1 x2 x3 -- x3 x1 x2 )` | |
| `2DUP` | `( x1 x2 -- x1 x2 x1 x2 )` | |
| `2DROP` | `( x1 x2 -- )` | |
| `2SWAP` | `( x1 x2 x3 x4 -- x3 x4 x1 x2 )` | |
| `2OVER` | `( x1 x2 x3 x4 -- x1 x2 x3 x4 x1 x2 )` | |
| `PICK` | `( xu..x0 u -- xu..x0 xu )` | `0 PICK` is `DUP` |
| `ROLL` | `( xu..x0 u -- xu-1..x0 xu )` | `2 ROLL` is `ROT` |
| `DEPTH` | `( -- u )` | cells on the stack before the push |

`PICK` and `ROLL` reach a cell whose depth is not known until run time. The
stack is in zero page and indexed by X, so a cell's address is a single byte
— which means it fits in Y and can be reached with absolute indexed
addressing into page zero. That is the only way to do it.

## Return stack

| Word | Effect |
|---|---|
| `>R` | `( x -- )` `( R: -- x )` |
| `R>` | `( -- x )` `( R: x -- )` |
| `R@` | `( -- x )` copy, leaves it on the return stack |
| `2>R` | `( x1 x2 -- )` `( R: -- x1 x2 )` |
| `2R>` | `( -- x1 x2 )` |
| `2R@` | `( -- x1 x2 )` copy |

The return stack is the 6502's own. Anything pushed must be taken back before
the word ends, or the word will return into it. That is also why these are
primitives and not colon definitions: entering a colon definition pushes the
caller's address onto the same stack.

## Arithmetic

| Word | Effect | |
|---|---|---|
| `+` `-` `*` | `( n1 n2 -- n3 )` | |
| `1+` `1-` | `( n -- n' )` | |
| `2*` `2/` | `( n -- n' )` | shifts; `2/` is arithmetic |
| `NEGATE` | `( n -- -n )` | |
| `ABS` | `( n -- \|n\| )` | |
| `MIN` `MAX` | `( n1 n2 -- n3 )` | signed |
| `/` | `( n1 n2 -- n3 )` | **floored** |
| `MOD` | `( n1 n2 -- n3 )` | remainder takes the divisor's sign |
| `/MOD` | `( n1 n2 -- rem quot )` | |
| `*/` | `( n1 n2 n3 -- n4 )` | `n1*n2/n3` with a 32-bit intermediate |
| `*/MOD` | `( n1 n2 n3 -- rem quot )` | |
| `LSHIFT` `RSHIFT` | `( x u -- x' )` | logical; 16 or more gives zero |
| `U/MOD` | `( u1 u2 -- rem quot )` | unsigned, 16 by 16 |

**Division is floored**: the quotient rounds toward negative infinity and the
remainder takes the sign of the divisor. `-10 3 /MOD` gives `2 -4`.
`SM/REM` truncates toward zero instead and gives `-1 -3`; it is there when
that is what you want.

`*/` exists because `n1*n2` often overflows a cell when `n1*n2/n3` does not.
Scaling a coordinate by 17/8 is `17 8 */`, not `17 * 8 /`.

## Mixed and double precision

A double is two cells, low pushed first, so the high cell is the one on top.

| Word | Effect | |
|---|---|---|
| `UM*` | `( u1 u2 -- ud )` | 16 by 16 giving 32, unsigned |
| `UM/MOD` | `( ud u -- rem quot )` | 32 by 16 giving 16, unsigned |
| `M*` | `( n1 n2 -- d )` | signed |
| `SM/REM` | `( d n -- rem quot )` | truncates toward zero |
| `FM/MOD` | `( d n -- rem quot )` | floors toward negative infinity |
| `S>D` | `( n -- d )` | sign-extend |
| `D+` `D-` | `( d1 d2 -- d3 )` | |
| `DNEGATE` `DABS` | `( d -- d' )` | |
| `UD/MOD` | `( ud u -- rem ud' )` | used by `#` |

`UM*` and `UM/MOD` are the two primitives everything else is built on.
Everything signed is those two with the signs taken off first and put back
afterwards, because sign fixing is cheap and unsigned arithmetic is not.

## Logic and comparison

| Word | Effect | |
|---|---|---|
| `AND` `OR` `XOR` | `( x1 x2 -- x3 )` | bitwise |
| `INVERT` | `( x -- x' )` | one's complement |
| `=` `<>` | `( x1 x2 -- flag )` | |
| `<` `>` | `( n1 n2 -- flag )` | signed |
| `U<` `U>` | `( u1 u2 -- flag )` | unsigned |
| `0=` `0<>` `0<` `0>` | `( n -- flag )` | |
| `WITHIN` | `( n lo hi -- flag )` | `lo <= n < hi` |

**Addresses above `$7FFF` are negative as cells.** Comparing them with `<`
gets the wrong answer; use `U<`. This is not a theoretical concern — it was a
real bug here, and it hid for a while because the dictionary happens to live
above `$8000` too.

## Memory

| Word | Effect | |
|---|---|---|
| `@` `!` | `( addr -- x )` / `( x addr -- )` | cell |
| `C@` `C!` | `( addr -- c )` / `( c addr -- )` | byte |
| `+!` | `( n addr -- )` | add to a cell |
| `2@` `2!` | `( addr -- d )` / `( d addr -- )` | |
| `CMOVE` | `( src dst u -- )` | forward, `u <= 255` |
| `MOVE` | `( src dst u -- )` | any length, handles overlap |
| `FILL` | `( addr u c -- )` | |
| `ERASE` `BLANK` | `( addr u -- )` | fill with 0 / with a space |
| `COUNT` | `( addr -- addr+1 u )` | unpack a counted string |
| `HERE` | `( -- addr )` | next free dictionary byte |
| `ALLOT` | `( n -- )` | move `HERE` |
| `,` `C,` | `( x -- )` / `( c -- )` | append and move `HERE` |
| `CELL+` `CELLS` | `( n -- n' )` | `+2`, `*2` |
| `CHAR+` `CHARS` | `( n -- n' )` | `+1`, nothing |
| `ALIGN` `ALIGNED` | | nothing, on a 6502 |
| `>BODY` | `( xt -- addr )` | past the `JSR` in a code field |

`MOVE` copies in whichever direction reads a byte before it is written over:
upward when the destination is below the source, downward when it is above.

## Defining words

| Word | |
|---|---|
| `: NAME ... ;` | a new word |
| `VARIABLE NAME` | a cell; the word pushes its address |
| `CONSTANT NAME` | `( x -- )` at definition; the word pushes `x` |
| `CREATE NAME` | a word that pushes the address of what follows it |
| `DOES> ...` | says what the words a defining word makes should do |
| `IMMEDIATE` | marks the last definition to run while compiling |
| `'` | `( -- xt )` looks up the next word |
| `FORGET NAME` | throws away `NAME` and everything after it |

`CREATE ... DOES>` is how the language grows:

```forth
: ARRAY CREATE CELLS ALLOT DOES> SWAP CELLS + ;
10 ARRAY SQUARES
```

`ARRAY` now makes words. `CREATE` lays down the space at definition time, and
everything after `DOES>` is what `SQUARES` does when it runs: it is handed
the address of its own data, and the index is underneath.

`FORGET` sets `HERE` back to the header and rebuilds the hash buckets from
scratch, which is cheaper than unpicking sixteen chains by hand. It is the
way to reclaim space after trying something out — the demos on the disk each
define a marker for exactly that.

## Compiling

| Word | |
|---|---|
| `[` `]` | leave and re-enter compiling |
| `LITERAL` | `( x -- )` compile `x` as a literal |
| `[']` | compile the next word's execution token as a literal |
| `COMPILE,` | `( xt -- )` compile a call |
| `POSTPONE` | compile the next word's *compilation* behaviour |
| `[CHAR]` | compile the next word's first character |
| `CHAR` | `( -- c )` the next word's first character, now |
| `RECURSE` | compile a call to the definition being defined |
| `(` `... )` | comment, to the closing bracket |
| `\` | comment, to the end of the line |

`[ ... ]` computes at compile time: `: SIX [ 2 3 * ] LITERAL ;` puts a 6 in
the definition rather than a multiply.

`POSTPONE` handles both cases: an immediate word is compiled so that it runs
later, an ordinary one is compiled as code that will compile it later. That
is what `CASE` and friends are built from.

## Control flow

| Word | |
|---|---|
| `IF ... THEN`, `IF ... ELSE ... THEN` | `( flag -- )` |
| `BEGIN ... UNTIL` | `( flag -- )` loops while false |
| `BEGIN ... AGAIN` | forever |
| `BEGIN ... WHILE ... REPEAT` | `( flag -- )` at the `WHILE` |
| `DO ... LOOP` | `( limit start -- )` |
| `?DO ... LOOP` | the same, but skips entirely if they are equal |
| `... +LOOP` | `( n -- )` step by `n`, either sign |
| `I` `J` | the loop index, and the next loop out |
| `LEAVE` | jump past the `LOOP` |
| `UNLOOP` | discard the loop's parameters before `EXIT` |
| `EXIT` | return from a definition |
| `EXECUTE` | `( xt -- )` run an execution token |
| `CASE ... OF ... ENDOF ... ENDCASE` | |
| `ABORT` | clear the stack and return to the prompt |
| `ABORT" ..."` | `( flag -- )` if true, print and abort |

`DO ... LOOP` always runs at least once, which is the traditional behaviour
and a trap: `0 0 DO` runs 65536 times. `?DO` is the one that checks first,
and is what a loop over a possibly-empty count wants.

`+LOOP` stops when the index crosses the boundary between `limit-1` and
`limit`. Comparing the index against the limit cannot see that on its own;
the test is whether `index - limit` changed sign, which works for a step of
either direction.

`LEAVE` and `?DO` compile forward branches that `LOOP` resolves. The compiler
keeps them on a stack of their own, and `DO` records how deep it was, so a
`LEAVE` in an inner loop cannot escape the wrong one.

## Text and numbers out

| Word | Effect | |
|---|---|---|
| `EMIT` | `( c -- )` | |
| `CR` | | |
| `SPACE` `SPACES` | `( -- )` / `( u -- )` | |
| `PAGE` | | clear the screen |
| `TYPE` | `( addr u -- )` | |
| `-TRAILING` | `( addr u -- addr u' )` | drop trailing spaces |
| `." ..."` | | print, compiling or not |
| `S" ..."` | `( -- addr u )` | |
| `C" ..."` | `( -- addr )` | counted string |
| `.` | `( n -- )` | signed |
| `U.` | `( u -- )` | unsigned |
| `.R` `U.R` | `( n u -- )` | right-justified in `u` columns |
| `D.` | `( d -- )` | |
| `?` | `( addr -- )` | print what is there |
| `.S` | | print the stack without disturbing it |

Pictured numeric output, for anything the above does not cover:

| Word | Effect | |
|---|---|---|
| `<#` | | start |
| `#` | `( ud -- ud' )` | one digit, in `BASE` |
| `#S` | `( ud -- 0 0 )` | the rest of them |
| `HOLD` | `( c -- )` | insert a character |
| `SIGN` | `( n -- )` | a minus if `n` is negative |
| `#>` | `( ud -- addr u )` | finish |

Digits come out least significant first, so they are laid down backwards into
a buffer and the string is whatever is left between the pointer and the end.
`U.` is `0 <# #S #> TYPE SPACE`.

## Input

| Word | Effect | |
|---|---|---|
| `KEY` | `( -- c )` | wait for a key |
| `KEY?` | `( -- flag )` | is one waiting, without taking it |
| `KEYC` | `( -- c )` | take the waiting key |
| `ASKLN` | `( -- addr u )` | read a line |
| `PARSE-NAME` | `( -- addr u )` | the next word on the current line, u=0 if none |
| `BTN` | `( -- flag )` | game port button 0 |
| `PADDLE` | `( n -- u )` | game port channel `n`, 0..255 |

**Decimal numbers.** `3.14159` at the prompt pushes a float. The whole part
must fit a cell and four places of fraction are kept, which is about what a
five-byte float can honestly show. Interpreting only: inside a colon
definition a decimal is still an unknown word.

It took two attempts. Written entirely in Forth it compiled into the
language card, which had a few hundred bytes left — and a dictionary that
close to its ceiling stops being a dictionary, silently: words as ordinary
as `/` and `MOD` went missing and `*/` ran into the monitor. The working
version splits it. The kernel scans the digits, in main memory, which
became affordable when `PICSAVE` stopped staging both halves of the screen
at once; the arithmetic is thirty cells of Forth behind the `'F#` vector,
because the arithmetic wants the ROM's floating point and that is already
wrapped in Forth. Storing 0 in `'F#` turns decimals off.

**Strings.** `STR` loads them: `S=` `SUB` `LEFT` `RIGHT` `SCAN` `SPLIT`
`TRIM` `UPPER` `S>N` `N>S` `SBUF` `SCOPY` `SCAT`. A string is an address and
a length, and where the bytes live is yours to decide; `SBUF` offers eight
64-byte slots for when it should not be. `S>N` is `VAL` with a flag, because
Applesoft quietly returning 0 for rubbish turns a typo into an answer.

**`DRV`** holds the current drive, 1 2 or 3. `DRIVE` sets it; every file
word reads it.

**On the words this reference does not list.** `WORDS` prints 441 names and
this document describes about 300 of them. The rest are the system's own
working parts — `FFA`, `WCNT`, `TSFLUSH`, the buffers and counters the
catalog and the file writer keep between them. They are visible because a
Forth dictionary is flat and hiding them would cost bytes to no purpose,
but they are not a contract: they exist to serve the word above them and
may be renamed or dropped whenever that word is rewritten. If a name is
not here or in `HELPTEXT`, treat it as machinery, not as an interface.

**Where an error happened.** An error inside a `LOAD` names the line:
`ZZZQQ ? IN LINE 3`. `LINE#` holds the line the interpreter has reached and
`LOAD` zeroes it — but reading carries on after an error, so `LINE#` ends a
line or two past the fault and the printed number is the one to trust.

**Arrays.** `ARRAY` loads them: `20 ARRAY SCORES` makes twenty cells and
`3 SCORES` is the address of one. A subscript outside the array stops the
line rather than handing back the next word's memory. `CARRAY` for bytes,
`r c 2ARRAY` for two dimensions, both subscripts checked.

**Asking questions.** `INPUT` loads `ASK$`, `ASK#` and `ASKY?` — prompt,
read, convert, in one word each. `ASK#` returns a flag beside the number
and does not loop until the answer is valid: a word that will not give up
is a word you cannot get out of, and this machine has no interrupt key.

A word that is neither defined nor a number is offered to the **autoload
hook** before it becomes an error: if the system disk carries `WORD.FTH`,
that file is loaded — from either drive — and announces itself; the line is
abandoned and typed again, the word exists. `'NF` holds the handler's xt
(`AUTOLOAD`, armed at boot); storing 0 turns the feature off. This is how
`MORE`, `MENU`, `SEE`, `DUMP`, `MARKER` and `RAMDISK` are commands without
costing the dictionary a byte before first use.

`PARSE-NAME` is how a word takes an argument from the line it was typed on:
`HELP HGR` is `HELP` calling it and finding `HGR`. The text lives in the
input buffer and lasts only until the next line is read.

`HELP` alone prints a command summary; `HELP NAME` prints one word's entry.
Both come from the `HELPTEXT` file on the system disk — data, not code, so
editing it costs no dictionary and adding an entry is adding text.

`PADDLE` waits out the game port's timer afterwards. It returns the moment
its capacitor has discharged, so a small reading returns early and leaves the
shared timer still charged — and the next channel then reads back skewed by
the first.

## Floating point

Five-byte floats on their own stack, eight deep, computed by Applesoft's own
routines in the ROM. The language card holds the dictionary, so every one of
these switches the ROM back for the length of the call and saves the zero
page Applesoft treads on — which is why they are machine code and none of
them can be a colon definition.

`F>S` **truncates**: `1 S>F FEXP F>S` is 2, not 3. It saturates rather than
overflowing, because Applesoft's own converter jumps into an error handler
this machine has nothing under.

| Word | Effect | |
|---|---|---|
| `S>F` | `( n -- )` | push an integer as a float |
| `F>S` | `( -- n )` | pop one as an integer, truncating |
| `FDUP` `FDROP` `FSWAP` `FOVER` | | the float stack |
| `FDEPTH` | `( -- n )` | how many floats |
| `F+` `F-` `F*` `F/` | | arithmetic |
| `FSQRT` | | square root |
| `FSIN` `FCOS` `FTAN` `FATN` | | radians |
| `FLN` `FEXP` | | natural log and its inverse |
| `F.` | | print and drop |

```forth
144 S>F FSQRT F>S .              \ 12
1 S>F FATN 4 S>F F* 1000 S>F F* F>S .    \ 3141
22 S>F 7 S>F F/ F.              \ 3.14285714
```

There is no `**`. `x` to the `n` is `FLN`, multiply, `FEXP` — which is what
Applesoft's own `^` does. `IPOW` is the exact integer version.

## The graphics screen

560 by 192, monochrome, one bit per pixel. `HGR` turns it on and `TEXT`
brings the console back.

| Word | Effect | |
|---|---|---|
| `HGR` | | graphics on, cleared |
| `TEXT` | | back to the 80-column console |
| `HCLS` | | clear |
| `HCOLOR` | `( n -- )` | 0 black, 3 white, the rest dithers |
| `HXOR` | `( flag -- )` | draw by XOR |
| `HPLOT` | `( x y -- )` | |
| `HPOINT` | `( x y -- flag )` | read a pixel back |
| `HLINE` | `( x1 x2 y -- )` | horizontal |
| `HVLINE` | `( x y1 y2 -- )` | vertical |
| `HLINE2` | `( x1 y1 x2 y2 -- )` | any slope |
| `HBOX` | `( x1 x2 y1 y2 -- )` | filled |
| `HFRAME` | `( x1 x2 y1 y2 -- )` | outline |
| `HCIRCLE` | `( x y r -- )` | outline |
| `HDISC` | `( x y r -- )` | filled |
| `HFILL` | `( x y -- )` | flood |
| `BLIT` | `( addr w h x y -- )` | bitmap |
| `AUXBANK` `MAINBANK` | | which half of the screen the CPU sees |

Coordinates are clamped, not wrapped: an `x` of 600 draws at 559.

**`HXOR`** makes every drawing word exclusive-or what it draws instead of
replacing it, so drawing the same thing twice leaves the screen as it was
found. That is how the demos animate without saving any background.

**`HFILL`** fills the connected region of pixels *matching the seed* with the
opposite value. Defining it that way rather than "fill with `HCOLOR`" is what
makes it terminate — a dithered pattern leaves some of the pixels it writes
still matching the seed, and those seed the fill again for as long as you
care to wait. Filling with black is the same word with the seed on a white
region. It fills by scanlines, but the scanning either side of a run is still
per pixel, so a very large area takes seconds.

**`BLIT`** takes rows of whole bytes, eight pixels each, bit 0 leftmost. A
set bit plots in the current colour and a clear bit leaves the screen alone,
so a shape needs no mask and no rectangle of background around it. Build one
with `CREATE` and `C,`:

```forth
CREATE BALL $3C C, $7E C, $FF C, $FF C, $FF C, $FF C, $7E C, $3C C,
BALL 8 8 100 50 BLIT
```

The screen is half in each memory bank — even byte columns in auxiliary
memory, odd ones in main — so saving one to disk is two saves with
`AUXBANK` and `MAINBANK` between them. Nothing may print while auxiliary is
selected: with `80STORE` set for the console, the same switch moves the text
screen.

## Text on the graphics screen

| Word | Effect | |
|---|---|---|
| `TAT` | `( col row -- )` | 80 by 24 grid |
| `TEMIT` | `( c -- )` | |
| `TINV` | `( flag -- )` | inverse video |
| `T." ..."` | | print, compiling or not |

## The lo-res screen

40 by 48 in sixteen colours, and much faster than double hi-res because it
is the text page seen differently: two blocks to a byte, no shifting. The
right screen for a bar chart.

`GR` keeps four lines of text at the bottom, so **rows 40-47 belong to the
console** and anything drawn there is scrolled over. `GR-FULL` shows all
forty-eight. `TEXT` brings the 80-column console back.

| Word | Effect | |
|---|---|---|
| `GR` | | lo-res with four text lines |
| `GR-FULL` | | all 48 rows |
| `GCLS` | `( n -- )` | clear to a colour |
| `GCOLOR!` | `( n -- )` | 0-15 |
| `GPLOT` | `( x y -- )` | |
| `GSCRN` | `( x y -- n )` | read a block back |
| `GHLIN` | `( x1 x2 y -- )` | |
| `GVLIN` | `( y1 y2 x -- )` | |
| `GBAR` | `( x y n -- )` | a bar n tall, for charts |

## Sound and timing

| Word | Effect | |
|---|---|---|
| `CLICK` | | one movement of the speaker cone |
| `TONE` | `( delay cycles -- )` | a square wave |
| `MS` | `( u -- )` | wait, roughly |
| `VBL` | | wait for the video counter to change |

The speaker is one soft switch: reading it moves the cone one way, and
reading it again moves it back. A tone is that pair of reads repeated at the
pitch you want, so `TONE` sits in a delay loop for the whole note — there is
no timer to hand it off to. A bigger delay is a lower note; dividing a
constant by the delay keeps every note the same length:

```forth
: NOTE ( delay -- ) DUP 30000 SWAP / TONE ;
```

Nor is there a clock. What there is is the video counter, which changes state
once per frame, so `VBL` is a sixtieth of a second measured by the same
crystal that drives everything else. `MS` is a counted loop and is only as
accurate as the 1.023 MHz it assumes.

## The disk

Every read and write is retried four times before it is called a failure. A
read straight after a write fails often enough to matter — the head has just
been somewhere else and the sector comes round when it comes round — which is
why DOS retried too. `DERR` holds the last error code.

The retry is only half of it. Nothing in the system calls `DREAD` or `DWRITE`
directly any more; everything goes through `RD` and `WR`, which return a flag,
and every caller looks at it and prints `DISK ERROR` rather than carrying on.
A read whose error is dropped leaves the *previous* sector in the buffer, and
the code that follows believes it — the catalog walk took a failed read for
the end of the chain and reported seven files out of twenty-nine with an `OK`
after it, and the file commands wrote one catalog sector over another.
Silently, in both cases.

A read shortly after a write is a special case, and a nasty one: it cannot be
trusted even when it *succeeds*. Some such reads fail — the retry catches
those — and some return the sector's **old** contents with no error at all.
`INIT` wrote an empty catalog, read it straight back, and got the twenty-eight
files it had just erased. So the first read after a write steps the head away
and back first (the way DOS recalibrated between retry groups), which forces
the written track out of the drive's hands; writes themselves never mind and
pay nothing.



| Word | Effect | |
|---|---|---|
| `DREAD` | `( t s addr -- err )` | read one sector |
| `DWRITE` | `( t s addr -- err )` | write one |
| `DSEEK` | `( t -- )` | move the head |
| `DRECAL` | | back to track 0 |

Sector numbers are DOS's, not the order they are written in — physical sector
*P* of a track holds DOS sector `0,7,14,6,13,5,12,4,11,3,10,2,9,1,8,15`.
`DREAD` and `DWRITE` translate. Sectors 0 and 15 are the two fixed points of
that permutation, which is why a missing translation can hide for a long
time: the VTOC is sector 0 and the first catalog sector is 15.

## Files

Three drives. Drive 1 is the system's own disk; drive 2 is the Programs
disk — no kernel underneath it, so nearly the whole floppy is free, and it
is where the examples live and big programs get built. Drive 3 is a RAM
disk and exists only if the machine carries a RamWorks-style memory card —
an optional extra, never a requirement: type `RAMDISK` and the probe either
makes banks 1–3 a full 560-sector volume (formatted on first use, instant,
gone at power-off) or says `NO RAM EXPANSION FOUND` and costs you nothing.
`n DRIVE` switches; everything below acts on the current drive.


Reading a file a byte or a line at a time, for data rather than source.
`FGETC` hands back every byte of every sector the file was allocated, high
bit and all — DOS keeps no byte count for a text file, so where one stops is
the caller's business. `DFGETS` strips the high bit and stops at a carriage
return.

| Word | Effect | |
|---|---|---|
| `FOPEN` | `( n -- ok )` | one file at a time |
| `FGETC` | `( -- c )` | -1 at the end |
| `FREAD` | `( addr n -- got )` | |
| `DFGETS` | `( addr n -- got eof )` | one line |
| `FEOF?` | `( -- f )` | |
| `FCLOSE` | | |
| `PICSAVE` | | write the screen as two files, one per bank |
| `PICLOAD` | `( nmain naux -- )` | read one back |
| `INIT` | | a fresh VTOC and empty catalog |

`INIT` cannot format — writing address fields needs a track writer this
driver does not have. It marks tracks 0 to `SRCEND` and track 17 used, so
running it on the disk you booted from loses the files and leaves the machine
bootable.

`SRCEND ( -- t )` is the last track the system's own source occupies, filled
in by the build. Anything that hands out disk space has to ask rather than
assume: the source grows with every word added to `system.fth`, and `INIT`
reserving a fixed eleven tracks — while the source had reached track 12 — is
exactly how a formatted disk came to put its first file on top of the system
and stop booting.

`PICSAVE` needs 16K of free dictionary to stage both halves of the screen — a
fresh boot leaves about 16.4K, so it fits, with a few dozen bytes to spare.
If the kernel ever grows past leaving 16K again, `PICSAVE` refuses and says
so rather than writing into the I/O page.

| Word | Effect | |
|---|---|---|
| `CAT` | | list the disk |
| `DRIVE` | `( n -- )` | switch to drive 1 or 2 and reload the catalog |
| `LIB` | | `LIB GFXLIB.FTH` — load a library off the system disk by name, from either drive |
| `FINDF` | `( addr len -- n )` | a file's catalog number by name, or -1 |
| `FREE` | `( -- u )` | free sectors |
| `LOCK` | `( n -- )` | toggle the lock on a file |
| `DEL` | `( n -- )` | delete one; locked files are refused |
| `REN` | `( n -- )` | rename one, asking for the name |
| `LOAD` | `( n -- )` | interpret a text file as Forth |
| `SAVE` | `( addr len -- )` | write a text file, asking for the name |
| `BSAVE` | `( addr len -- )` | the same as a binary file |
| `BLOAD` | `( n addr -- len )` | read one back |

`n` is the number `CAT` prints. An index outside the catalog is refused
rather than trusted, because every one of these writes to the disk.

`LOAD` reads the text onto hi-res page 1 and points the interpreter's source
pointer at it, so it costs no dictionary at all — which matters, because the
definitions the file makes have to fit somewhere. Turning the graphics screen
on while a file is still being read overwrites what is left of it. One file
at a time: a load inside a load would move the ground under the first.

`SAVE` and `BSAVE` create a real DOS 3.3 file: sectors marked used in the
VTOC, a track/sector list naming them, the data, and a catalog entry pointing
at the list. Nothing is written until all four are ready except the data
sectors, which are harmless on their own — an interrupted save leaks sectors
rather than corrupting the catalog. `BSAVE` writes DOS's four-byte header
(load address, then length) and `BLOAD` steps it back off and returns the
length.

The round trip, from the console:

```forth
S" : HELLO 1234 ;" SAVE
```

It asks for a name; `CAT` then shows it, and `n LOAD` reads it back and
defines `HELLO`.

## Recovering from a failure

Without these an error takes the whole line down and clears the stack: a word
cannot try something and recover. `CATCH` remembers where both stacks were
and hands that to `THROW`, which puts them back and returns through `CATCH`
rather than through whatever was in the middle.

| Word | Effect | |
|---|---|---|
| `CATCH` | `( xt -- 0 \| n )` | run it; 0 if it finished |
| `THROW` | `( n -- )` | give up, back to the `CATCH` |
| `SP@` `SP!` | `( -- addr )` `( addr -- )` | the data stack pointer |
| `RP@` `RP!` | `( -- addr )` `( addr -- )` | the return stack pointer |
| `PAD` | `( -- addr )` | 256 bytes of scratch at `$0F00` |

```forth
: RISKY 42 THROW ;
' RISKY CATCH .          \ 42
' NOTHING-WRONG CATCH .  \ 0
```

`THROW` with zero does nothing, so a word can `THROW` a status without
knowing whether it is an error.

**The system's own words do not use these yet.** `LOCK`, `DEL`, `REN` and
the file writer print a message and stop; a caller has to read `DERR` to
tell success from failure.

## Inline tables of numbers

Applesoft's `DATA` and `READ`. The values go into the dictionary between
`DATA:` and `;DATA`.

| Word | Effect | |
|---|---|---|
| `DATA:` | | start a table at `HERE` |
| `+VAL` | `( n -- )` | add a value |
| `;DATA` | | finish, and rewind |
| `READ-VAL` | `( -- n )` | the next one, 0 when exhausted |
| `RESTORE-DATA` | | rewind |
| `DATA#` | `( -- n )` | how many |

## Calling machine code

| Word | Effect | |
|---|---|---|
| `CALL` | `( addr -- )` | run a subroutine as things stand |
| `ROMCALL` | `( addr -- )` | switch the ROM back first, and save zero page |
| `CALL-A` | `( n addr -- n )` | with the accumulator in and out |
| `WAIT-BIT` | `( addr mask val -- )` | poll until the masked bits match |

Anything at `$D000-$FFFF` needs `ROMCALL`, because the language card holds
the dictionary. `$FC58 ROMCALL` clears the text screen.

## Random

| Word | Effect | |
|---|---|---|
| `RND` | `( -- u )` | 16-bit xorshift |
| `RND-SEED!` | `( n -- )` | seeding to zero is refused |
| `RND-RANGE` | `( lo hi -- n )` | inclusive |
| `SHUFFLE` | `( addr n w -- )` | Fisher-Yates, w bytes an element |

## Looking at things

| Word | Effect | |
|---|---|---|
| `DUMP` | `( addr n -- )` | hex and characters, eight to a line |
| `SEE` | | decompile the word named next |
| `>NAME` | `( xt -- addr len )` | which word owns that code field |
| `.S` | | the stack, without disturbing it |
| `UNUSED` | `( -- n )` | dictionary bytes left |
| `MARKER` | | `MARKER NAME` — a word that forgets back to here |

`SEE` walks the whole dictionary to name each cell, so it is slow on a long
definition. `MARKER` forgets itself along with everything after it.

## Precompiled overlays

A library compiled once, saved, and loaded back at disk speed instead of
being recompiled a token at a time.

| Word | Effect | |
|---|---|---|
| `MARK` | | remember where the dictionary is |
| `SAVEDICT` | | write everything since `MARK` as a file |
| `LOADDICT` | `( n -- )` | read one back |
| `UNMARK` | | throw away everything since `MARK` |

An overlay loads at the address it was saved from, which is why nothing needs
relocating and why it will refuse to load anywhere else.

## System variables and internals

| Word | |
|---|---|
| `STATE` | 0 interpreting, 1 compiling |
| `BASE` | number base, 10 at boot |
| `DP` | the dictionary pointer; `HERE` is `DP @` |
| `LATEST` | the most recent header |
| `NFILE` `NFREE` | files in the catalog, free sectors |
| `SECBUF` `VTOCBUF` `TSBUF` `CATBUF` | the disk buffers |
| `WORDS` | list every definition |
| `BYE` | stop |

This Forth has a single wordlist, so `WORDS` also prints about ninety names
that are the system's own working parts — the file writer's variables, the
catalog helpers, and the compiler's runtime halves (`LIT`, `BRANCH`, `(DO)`,
`(.")`). They are visible because there is nowhere to hide them, not because
they are meant to be called.

---

## What is not here

- No `EVALUATE`, and no nested input sources.
- No vocabularies or wordlists.
- No `BLOCK`/`LIST`; `LOAD` covers the need differently.
- No floating point, and there will not be any.
