; ---------------------------------------------------------------------------
; forth.s -- a Forth system for the Apple //e, with a 560x192 monochrome
; double hi-res screen driver.
;
; Memory map once BRUN from DOS 3.3:
;
;   $0800-$0FFF   one raw disk sector
;   $1000-$1FFF   the parsed catalog, 36 bytes per file
;   $2000-$3FFF   hi-res page 1 -- in BOTH banks: aux and main interleave
;                 byte by byte to make 560 pixels per row
;   $4000-....    this kernel, then the dictionary growing upward.  Page 2
;                 of hi-res used to live at $4000; the OS needs the room
;                 more than it needs a back buffer.
;   $9300-$95FF   DOS 3.3 file buffer (the greeting sets MAXFILES 1, which
;                 hands about 2K back to the dictionary)
;   $9600-$BFFF   DOS 3.3
;
; The kernel is direct-threaded: a thread cell is a code field address and
; the inner interpreter ends in JMP (W).  See dict.inc for the layout.
; ---------------------------------------------------------------------------

.include "zp.inc"
.include "dict.inc"

        .segment "STARTUP"
ColdStart:
        cld
        ldx     #$FF                    ; return stack
        txs
        ldx     #DSTACK_TOP             ; data stack
        jsr     HgrText
        stx     XSAV
        jsr     HOME
        ldx     XSAV
        lda     #<BANNER
        sta     TMP2
        lda     #>BANNER
        sta     TMP2+1
        jsr     PutStr
        ; DOS hooks the monitor's character vectors, so every COUT call runs
        ; through its code at $9600.  Nothing hooks them now -- DOS is not on
        ; the disk at all -- but setting them explicitly costs four stores and
        ; means the kernel does not depend on what happened to be there.
        lda     #<COUT1
        sta     CSW
        lda     #>COUT1
        sta     CSW+1
        lda     #<KEYIN
        sta     KSW
        lda     #>KEYIN
        sta     KSW+1
        jsr     BuildIndex              ; hash the built-in dictionary
        jsr     D2BuildTable            ; invert the 6-and-2 nibble table
        lda     #<BOOTSRC               ; the interpreter reads this first,
        sta     SRC                     ; then switches to the keyboard
        lda     #>BOOTSRC
        sta     SRC+1
        jmp     Quit

        .segment "CODE"
.include "kernel.inc"
.include "interp.inc"
.include "gwords.inc"
.include "pointer.inc"
.include "disk.inc"
.include "diskii.inc"
.include "hires.inc"
.include "text.inc"
.include "gfx.inc"
.include "icon.inc"

; ---------------------------------------------------------------------------
        .segment "RODATA"

; Nothing but this until the graphics come up: the identity of the machine
; belongs on the splash screen, not scrolling past on the text screen.
BANNER: .byte   "INITIALIZING...", $0D, $00

; The system's own source, interpreted at boot before the keyboard is read.
; Written as real Forth in src/system.fth and converted by tools/mkboot.py.
.include "bootsrc.inc"

; ---------------------------------------------------------------------------
        .segment "DATA"

TIBLEN:  .byte  0                       ; characters in the terminal buffer
TOIN:    .byte  0                       ; parse offset into it
WORDLEN: .byte  0                       ; length of the word just parsed
PIDX:    .byte  0                       ; general character index
NBASE:   .byte  10
NDIG:    .byte  0
NCNT:    .byte  0
NNEG:    .byte  0
FFLAGS:  .byte  0                       ; flags byte of the header being tested
FCHR:    .byte  0
NBKT:    .byte  0                       ; bucket of the header being created

; Sixteen hash buckets, two bytes each.  BUCKETS holds each chain's head and
; is live for the life of the system; BTAILS is scratch that BuildIndex uses
; once at cold start to append in definition order.
BUCKETS: .res   32
BTAILS:  .res   32
NEWHDR:  .word  0                       ; header being built
STRLEN:  .word  0                       ; count byte of a compiling string
CFLO:    .byte  0
CFHI:    .byte  0
NUMBUF:  .res   8                       ; digits, emitted in reverse

PX:      .word  140                     ; pointer position
PY:      .byte  80
PVIS:    .byte  0                       ; is the arrow currently XORed in?
PCOL:    .byte  0                       ; byte column it lands in
PSHIFT:  .byte  0                       ; and how far into that byte
PROW:    .byte  0
PSH:     .word  0                       ; one shape row, shifted into place
PTMP:    .word  0
PXTMP:   .word  0                       ; pointer byte being merged
PLASTX:  .byte  128                     ; last analog reading, so MREAD can
PLASTY:  .byte  128
MAXIS:   .byte  0                       ; which paddle MREAD reads next
PSETTLE: .byte  0                       ; which paddle MREAD reads next                     ; tell a real movement from an idle one

RBUF:    .word  0                       ; sector buffer address for RWTS

INBUFSZ = 32                            ; a DOS 3.3 name is 30 characters
INBUF:   .res   INBUFSZ                 ; ASKLN's private copy of a typed line

; The two-cell thread DoRun executes: the word asked for, then the primitive
; that restores IP and returns to the assembly caller.
RunSlot: .word  0
         .word  RetToAsm

; Dictionary head and free space, both resolved after every word is defined.
FINAL_LATEST = LASTHDR
KERNEL_END:
