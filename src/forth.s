; ---------------------------------------------------------------------------
; forth.s -- a Forth system for the Apple //e: an 80-column console, and a
; 560x192 monochrome double hi-res screen the language can draw on.
;
; The system boots to an 80-column console.  The graphics screen is a thing
; the language can turn on, not the interface: HGR, TEXT and the drawing
; words are ordinary Forth words.
;
; Memory map:
;
;   $0400-$07FF   the text screen, in both banks -- the 80-column firmware
;                 puts even columns in aux and odd ones in main
;   $0800-$0FFF   one raw disk sector
;   $1000-$1FFF   the parsed catalog, 36 bytes per file
;   $2000-$3FFF   hi-res page 1 -- in BOTH banks: aux and main interleave
;                 byte by byte to make 560 pixels per row
;   $4000-$BEFF   this kernel, then the dictionary growing upward
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
        stx     XSAV
        jsr     HgrText
        ; The //e has an 80-column driver in ROM: it scrolls both banks, keeps
        ; the cursor, and understands the monitor's control codes.  Entering it
        ; costs two calls and nothing in the image.  It takes over CSW and KSW,
        ; so nothing here may set those afterwards -- COUT and GETLN reach it
        ; through them.
        jsr     SETTXT
        jsr     C3INIT
        jsr     HOME
        ldx     XSAV
        lda     #<BANNER
        sta     TMP2
        lda     #>BANNER
        sta     TMP2+1
        jsr     PutStr
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
.include "input.inc"
.include "math.inc"
.include "compile.inc"
.include "diskii.inc"
.include "hires.inc"
.include "text.inc"
.include "gfx.inc"
.include "fill.inc"
.include "sound.inc"

; ---------------------------------------------------------------------------
        .segment "RODATA"

; The system's own banner is printed from Forth once the dictionary is up.
; This is only what the kernel says while it is still building it.
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

; $80 makes the drawing words XOR what they draw instead of replacing it, so
; the same call both draws and erases: drawing a shape twice leaves the screen
; as it was found.
HXORF:   .byte  0

INBUF   = $1C60                          ; ASKLN's copy of a typed line, also
                                         ; up above the catalog

; The two-cell thread DoRun executes: the word asked for, then the primitive
; that restores IP and returns to the assembly caller.
RunSlot: .word  0
         .word  RetToAsm

; Dictionary head and free space, both resolved after every word is defined.
FINAL_LATEST = LASTHDR
KERNEL_END:
