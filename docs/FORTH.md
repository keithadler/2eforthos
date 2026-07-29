# What Forth is, and where it came from

This system is a Forth. If you have not met one, that sentence explains
less than it should — Forth is unlike almost everything that came after it,
and the ways it is unlike them are the reasons it fits on a floppy disk and
still leaves room for your program.

---

## Where it came from

Charles H. Moore wrote the first version in the late 1960s, working on
his own, out of dissatisfaction with the languages he was being handed. He
wanted something he could change while it was running: an interpreter that
was also a compiler, on a machine small enough that neither could afford to
be large.

The name is *fourth*, as in fourth-generation language, with a letter
removed. Moore was working on an IBM 1130 whose file system allowed five
characters in a name.

It found its first serious use in radio astronomy. At the National Radio
Astronomy Observatory, Moore and Elizabeth Rather used it to run the 11-metre
telescope at Kitt Peak around 1971 — pointing the dish, collecting data,
and reducing it, on a minicomputer with very little memory. That is the
setting the language was shaped by, and it shows: a telescope needs a control
program you can modify at three in the morning without a compile-link-load
cycle, and it needs that program to fit.

Moore and Rather founded FORTH, Inc. in 1973. The Forth Interest Group formed
in 1978 and published a model implementation, **FIG-Forth**, which was ported
to nearly every 8-bit machine of the era — including this one. Standards
followed: Forth-79, Forth-83, ANS Forth in 1994, and Forth 2012.

It never became a mass-market language, and it never went away. It ran
instruments on spacecraft — the RTX2010, a processor designed to execute
Forth directly, flew on the Philae comet lander. **Open Firmware**, the boot
environment on Sun workstations and on Apple's PowerPC Macintoshes, is a
Forth: a PowerBook of the right vintage will drop you at an `ok` prompt that
would recognise most of what is in this system.

---

## What makes it different

Four ideas, and they compound.

### There are two stacks

One holds your data, the other holds return addresses. Because arguments are
on a stack rather than in named slots, a word does not declare parameters and
does not need a calling convention negotiated in advance. `+` takes two
numbers off and puts one back. So does every other word: the interface
between any two pieces of code is the same interface.

You write in postfix, because that is what a stack wants:

```forth
2 3 + .          \ prints 5
```

`2` and `3` push. `+` pops two and pushes their sum. `.` pops and prints.
There is no expression parser here because there is no expression — there is
a sequence of things that happen.

### There is no syntax

A Forth program is a list of words separated by spaces. That is the entire
grammar. `IF` is not a keyword; it is a word in the dictionary that happens
to run at compile time and lay down a branch. `(` is a word that skips ahead
to the `)`. You can define your own and they will be indistinguishable from
the ones that came with the system, because there is nothing to distinguish
them from.

This is why `CASE` in this system is written *in Forth*, in four lines, out
of `IF` and `ELSE` and `THEN` — see [LANGUAGE.md](LANGUAGE.md#control-flow).
A language where control structures are library code is a different kind of
thing from one where they are grammar.

### The compiler is available at run time

`STATE` says whether the system is interpreting or compiling, and you can
change it. `[` and `]` step out of a definition and back into it, so a
constant expression can be computed while compiling and the *answer*
compiled in:

```forth
: SIX [ 2 3 * ] LITERAL ;
```

`SIX` contains a 6, not a multiply. And `CREATE ... DOES>` lets you write
words that make words — a defining word, with its own idea of what the
things it defines should do. That is the mechanism the rest of the language
is built from; `VARIABLE` and `CONSTANT` are just the two that shipped.

### The dictionary is the program

Everything — your definitions, the system's, the compiler's own working
parts — lives in one linked list of headers. `WORDS` walks it. `FORGET`
cuts it. There is no separate symbol table, no link step, and no distinction
between the system and what you added to it.

The cost of that honesty is that this system has exactly one namespace: a
name you define twice shadows the first, and `WORDS` shows you the plumbing
alongside your own work.

---

## Threaded code, and which kind this is

A compiled Forth word is not machine code. It is a list of addresses, each
naming another word, walked by a small loop called the **inner interpreter**.
That indirection is why a Forth image is so much smaller than the equivalent
compiled program: a call costs two bytes, not five.

There are several ways to arrange it.

| | a thread cell holds | the inner interpreter |
|---|---|---|
| **Indirect threaded** (ITC) | the address of a code field, which holds the address of the code | two indirections; classic FIG-Forth |
| **Direct threaded** (DTC) | the address of executable code | one indirection, ends in `JMP (W)` |
| **Subroutine threaded** (STC) | nothing — the thread *is* `JSR` instructions | the CPU's own return stack does the work |
| **Token threaded** | a small index into a table | slowest, smallest |

**This system is direct threaded.** A thread cell is a code field address,
and the inner interpreter ends in `JMP (W)`:

```asm
DoNext: ldy #1
        lda (IP),y      ; fetch the next cell
        sta W+1
        dey
        lda (IP),y
        sta W
        clc             ; step over it
        lda IP
        adc #2
        sta IP
        bcc :+
        inc IP+1
:       jmp (W)         ; and go
```

The code field of a primitive **is** its machine code, so a primitive costs
nothing beyond its own body. The code field of a colon definition is
`JSR DOCOL` followed by the thread. On a 6502, DTC is usually the right
trade: it is meaningfully faster than ITC and only a little larger.

The data stack lives in zero page and is indexed by X, so the top of stack is
`(0,X)` and pushing is `DEX DEX`. X is therefore sacred — every routine that
calls into the monitor ROM parks it first. The return stack is the 6502's own
hardware stack, which is why `>R` has to be a primitive: a colon definition
that pushed something there would return into it.

---

## Why it suits a 1 MHz machine with 128K

Because everything above is *cheap*, and because the alternative was worse.

- The compiler is a few hundred bytes, because a word lookup and a two-byte
  append is the whole of it.
- There is no linker, so there is no link step to sit through.
- The system is interactive from the moment it boots, on a machine where a
  compile-run-crash cycle costs a floppy seek each way.
- Adding a feature to the language costs the same as adding a subroutine,
  so the language grows toward the problem instead of the program growing
  away from the language.

That last point is the one that matters most here. The graphics words in
this system are not a library bolted onto a general-purpose language; they
are words, indistinguishable from `+`, and a program that draws is written
in a dialect that has drawing in it.

---

## How this system relates to the standards

It is **not** an ANS Forth, and does not claim to be. It implements a large
and deliberately chosen part of the ANS CORE word set, with the same names
and stack effects, so code written against it will mostly read as ordinary
Forth. The full list is in [LANGUAGE.md](LANGUAGE.md).

Where it follows the standard:

- The CORE stack, arithmetic, memory, comparison and control words.
- `CREATE ... DOES>`, `POSTPONE`, `[`, `]`, `LITERAL`, `[']`, `RECURSE`.
- Pictured numeric output — `<# # #S #> HOLD SIGN`.
- Floored division, which is what ANS recommends where it allows a choice.
  `SM/REM` is there for truncation.

Where it does not:

- **No `EVALUATE`** and no nested input sources. `LOAD` sets the
  interpreter's one source pointer at a file; a load inside a load would move
  the ground under the first.
- **No vocabularies or wordlists.** One namespace.
- **No `BLOCK`/`LIST`.** Forth traditionally stored source in 1024-byte
  blocks addressed by number, with its own editor. This system reads DOS 3.3
  text files instead, because the disk already had a filesystem on it and
  the host can edit them.
- **No floating point**, and no double-cell `2VARIABLE`/`2CONSTANT`.
- **No `ENVIRONMENT?`**, no exception words, no `[IF]`.

And two additions the standard has no opinion about, because they are this
machine: the graphics word set, and the file words.

---

## Further reading

- **Leo Brodie, _Starting Forth_.** The book to read first. It teaches the
  stack and the dictionary rather than a particular system's word list, so
  it transfers here almost intact — skip the `BLOCK`/editor chapters, which
  this system replaces with `LOAD` and `SAVE`.
- **Leo Brodie, _Thinking Forth_.** Not about the language at all: about how
  to factor a program into words. It is the better book and the one people
  keep coming back to.
- **The FIG-Forth model listings**, if you want to see how a whole Forth was
  described in a few dozen pages of assembly.
- **ANS Forth (X3.215-1994)** and **Forth 2012**, for what a word is
  supposed to do when you are not sure.

For this system specifically: [LANGUAGE.md](LANGUAGE.md) is the reference,
[TUTORIAL.md](TUTORIAL.md) walks from the prompt to a program on disk, and
the [README](../README.md) explains how the machine underneath it works.
