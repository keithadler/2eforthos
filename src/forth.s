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
;   $0800-$0CFF   sector buffers: raw sector, VTOC, T/S list, disk nibbles
;   $0D00-$0FFF   one sector of boot source while booting; scratch after
;   $1000-$186F   the parsed catalog, 36 bytes per file
;   $1870-$1FFF   uninitialized buffers, kept out of this image -- the one
;                 map of that region is in kernel.inc
;   $2000-$3FFF   hi-res page 1 -- in BOTH banks: aux and main interleave
;                 byte by byte to make 560 pixels per row
;   $4000-$BFFF   this kernel, then the dictionary growing upward
;
; The kernel is direct-threaded: a thread cell is a code field address and
; the inner interpreter ends in JMP (W).  See dict.inc for the layout.
; ---------------------------------------------------------------------------

.include "lc.inc"
.include "zp.inc"
.include "srcsecs.inc"       ; SRCSECS, SRCTRACK -- where the source lives
.include "dict.inc"

        .segment "STARTUP"
ColdStart:
        cld
        ldx     #$FF                    ; return stack
        txs
        ; Bring the language card in.  The CPU takes its reset and interrupt
        ; vectors from $FFFA-$FFFF whatever is banked there, so those six
        ; bytes are copied out of the ROM first -- reading ROM and writing
        ; the card at the same time, which is exactly what $C089 is for.
        bit     LCWRITE
        bit     LCWRITE
        ldy     #5
@vec:   lda     $FFFA,y
        sta     $FFFA,y
        dey
        bpl     @vec
        bit     LCRAM
        bit     LCRAM
        ldx     #DSTACK_TOP             ; data stack
        stx     XSAV
        jsr     HgrText
        ; The //e has an 80-column driver in ROM: it scrolls both banks, keeps
        ; the cursor, and understands the monitor's control codes.  Entering it
        ; costs two calls and nothing in the image.  It takes over CSW and KSW,
        ; so nothing here may set those afterwards -- COUT and GETLN reach it
        ; through them.
        ROMIN
        jsr     SETTXT
        jsr     C3INIT
        jsr     HOME
        ROMOUT
        ldx     XSAV
        ; Count the auxiliary banks, so the banner can say what the machine
        ; actually has instead of asserting 128K at everyone.  The two
        ; ten-byte accessors run from the stack page -- RAMRD banks every
        ; read from $0200 up, instruction fetches included -- and the loop
        ; stamps a canary in bank 0 beside each candidate: the first stamp
        ; that kills the canary is the first bank that is not real.  On a
        ; machine with no card the register is ignored, bank 1 IS bank 0,
        ; and the count stays 1: the stock 128K.
        ldy     #AUXPROBE_LEN-1
@cpau:  lda     AUXPROBE,y
        sta     $0100,y
        dey
        bpl     @cpau
        lda     #1
        sta     CARDBK
@bank:  lda     #0                      ; canary into bank 0
        sta     $C073
        lda     #$A5
        jsr     $0100                   ; write A to aux $0200
        lda     CARDBK                  ; candidate bank gets its number
        sta     $C073
        jsr     $0100
        lda     #0                      ; is the canary still alive?
        sta     $C073
        jsr     $010A                   ; read aux $0200 into A
        cmp     #$A5
        bne     @bdone
        inc     CARDBK
        lda     CARDBK
        cmp     #128
        bcc     @bank
@bdone: lda     #0
        sta     $C073

        lda     #<BANNER
        sta     TMP2
        lda     #>BANNER
        sta     TMP2+1
        jsr     PutStr
        jsr     BuildIndex              ; hash the built-in dictionary
        jsr     D2BuildTable            ; invert the 6-and-2 nibble table
        ; The system compiles itself into the language card, and the
        ; dictionary pointer comes back to main memory when it has finished.
        ; Nothing of the system is in the user's way afterwards: they get the
        ; whole of KERNEL_END to $BFFF, contiguous, instead of what was left
        ; over.  Doing it this way rather than letting the dictionary run
        ; across the $C000 hole means no definition can ever straddle it.
        lda     #<LCDICT
        sta     DPV
        lda     #>LCDICT
        sta     DPV+1
        lda     #0                      ; the system's own source is on the
        sta     SRCIDX                  ; disk; read the first sector of it
        sta     DPSWTCH                 ; and let the interpreter compile
        stx     XSAV                    ; itself before the keyboard is read
        jsr     NextSrcSector
        ldx     XSAV
        jmp     Quit

        .segment "CODE"
.include "kernel.inc"
.include "interp.inc"
.include "gwords.inc"
.include "input.inc"
.include "math.inc"
.include "compile.inc"
.include "fast.inc"
.include "fp.inc"
.include "diskii.inc"
.include "hires.inc"
.include "text.inc"
.include "gfx.inc"
.include "fill.inc"
.include "lores.inc"
.include "sound.inc"

; ---------------------------------------------------------------------------
        .segment "RODATA"

; The stack-page accessors the bank probe copies to $0100: write A to
; auxiliary $0200, and read it back.  Ten bytes each, position-fixed.
AUXPROBE:
        sta     $C005                   ; $0100: writes go aux
        sta     $0200
        sta     $C004
        rts                             ; ten bytes exactly: next is $010A
        sta     $C003                   ; $010A: reads come from aux
        lda     $0200
        sta     $C002
        rts
AUXPROBE_LEN = * - AUXPROBE

; The system's own banner is printed from Forth once the dictionary is up.
; This is only what the kernel says while it is still building it.
BANNER: .byte   "INITIALIZING...", $0D, $00
DICTFULL: .byte "DICTIONARY FULL", $0D, $00
INLINE:   .byte " IN LINE ", $00


; ---------------------------------------------------------------------------
        .segment "DATA"

SRCIDX:  .byte  0                       ; which source sector comes next
DPSWTCH: .byte  0                       ; has the dictionary come back to main?
LNX:     .byte  0                       ; ReadLine's parked stack pointer
LNLEN:   .byte  0

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

; The hash buckets (BUCKETS, BTAILS) and the numeric output buffer (NUMBUF)
; live at absolute addresses above the catalog -- see the map in kernel.inc.
; Nothing uninitialized belongs in this segment: a .res here would ship as
; zeros in the image and cost the same bytes again in dictionary headroom.
; NBKT, NEWHDR, STRLEN, CFLO and CFHI are above the catalog: kernel.inc

; $80 makes the drawing words XOR what they draw instead of replacing it, so
; the same call both draws and erases: drawing a shape twice leaves the screen
; as it was found.
HXORF:   .byte  0

; INBUF is above the catalog: kernel.inc has the map

; The two-cell thread DoRun executes: the word asked for, then the primitive
; that restores IP and returns to the assembly caller.
RunSlot: .word  0
         .word  RetToAsm

; Dictionary head and free space, both resolved after every word is defined.
FINAL_LATEST = LASTHDR
KERNEL_END:
