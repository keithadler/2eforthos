; ---------------------------------------------------------------------------
; fp.inc -- floating point, by calling Applesoft's
;
; There are several kilobytes of debugged five-byte floating point in the
; ROM -- add, subtract, multiply, divide, square root, the transcendentals,
; and a formatter -- and writing any of that again would be a poor use of a
; life.  These words set up Applesoft's accumulator and call it.
;
; Two things make it awkward, and both are answered here rather than in the
; caller.
;
; The language card is banked in for the life of the session, so $D000-$FFFF
; is the dictionary, not the ROM.  Every call switches the ROM back for its
; duration -- which is why all of this is machine code in main memory and
; none of it can be a colon definition: while the ROM is in, the card and
; every word compiled into it is invisible.
;
; And Applesoft scratches zero page where we live.  FAC is $9D-$A2, ARG is
; $A5-$AA, and MOVFM, CONUPK and FCOMP all use $5E-$61 as a pointer -- which
; is the *middle* of the Forth data stack, not the top of it.  Moving the
; stack down would not have helped.  So the ranges are saved before each call
; and put back after, twenty bytes and about a hundred and twenty cycles,
; which is nothing beside the arithmetic it protects.
; ---------------------------------------------------------------------------

; --- Applesoft entry points, verified against the ROM ----------------------
GIVAYF  = $E2F2                 ; A=high Y=low, signed int -> FAC
AYINT   = $E10C                 ; FAC -> signed 16-bit in $A0/$A1
MOVFM   = $EAF9                 ; A/Y -> FAC
MOVMF   = $EB2B                 ; FAC -> A/Y  (address in X/Y, oddly)
CONUPK  = $E9E3                 ; A/Y -> ARG
FADDM   = $E7BE                 ; FAC := (A/Y) + FAC
FSUBM   = $E7A7                 ; FAC := (A/Y) - FAC
FMULM   = $E97F                 ; FAC := (A/Y) * FAC
FDIVM   = $EA66                 ; FAC := (A/Y) / FAC
FSQR    = $EE8D
FSIN    = $EFF1
FCOS    = $EFEA
FTAN    = $F03A
FATN    = $F09E
FLOG    = $E941
FEXP    = $EF09
FOUT    = $ED34                 ; FAC -> string at $0100, NUL terminated

FACEXP  = $9D                   ; FAC, five bytes plus a sign byte
FACINT  = $A0                   ; where AYINT leaves the integer
FACSGN  = $A2                   ; and the sign byte

; --- the float stack -------------------------------------------------------
; Eight five-byte floats.  Separate from the data stack, because a float does
; not fit a cell and shuffling five bytes through two-byte cells would be
; worse than keeping them apart.
FDEPTH  = 8

; A/Y := address of float N counting from the bottom; clobbers Y
FCellAY:
        tay
        lda     FOFF,y
        clc
        adc     #<FSTK
        pha
        lda     #>FSTK
        adc     #0
        tay
        pla
        rts

; Save and restore the zero page Applesoft treads on.
;
; It treads on more of it than the documented FAC and ARG: the first attempt
; saved $5E-$61 and $9D-$AC and still came back with the Forth stack full of
; rubbish, because the routines use temporaries further down as well.  Rather
; than chase which, the whole of $50-$AC goes -- the entire data stack plus
; FAC and ARG.  Ninety-three bytes and about six hundred cycles, against
; floating point arithmetic that costs thousands.
;
; The result is read out of FAC into the float stack before this puts FAC
; back, or restoring would throw the answer away.
FPSaveZ:
        ldy     #92
@l:     lda     $50,y
        sta     FZSAVE,y
        dey
        bpl     @l
        rts

FPRestoreZ:
        ldy     #92
@l:     lda     FZSAVE,y
        sta     $50,y
        dey
        bpl     @l
        rts

; Load the top float into FAC.  ROM must already be in.
FTopToFAC:
        lda     FPSP
        beq     @none
        sec
        sbc     #1
        jsr     FCellAY
        jmp     MOVFM
@none:  rts

; Store FAC into the top float slot.  ROM must already be in.
FFACToTop:
        lda     FPSP
        beq     @none
        sec
        sbc     #1
        jsr     FCellAY                 ; A = low, Y = high
        tax                             ; MOVMF wants it in X/Y: 86 5E 84 5F
        jmp     MOVMF
@none:  rts

; ---------------------------------------------------------------------------
; Forth words
; ---------------------------------------------------------------------------
        prim    "S>F", W_STOF, 0        ; n --   push it as a float
        lda     0,x
        sta     FTMP
        lda     1,x
        sta     FTMP+1
        inx
        inx
        lda     FPSP
        cmp     #FDEPTH
        bcs     :+
        inc     FPSP
:       stx     XSAV
        jsr     FPSaveZ
        ROMIN
        lda     FTMP+1
        ldy     FTMP
        jsr     GIVAYF
        jsr     FFACToTop
        ROMOUT
        jsr     FPRestoreZ
        ldx     XSAV
        NEXT

        prim    "F>S", W_FTOS, 0        ; -- n   pop it as an integer
        stx     XSAV
        jsr     FPSaveZ
        ROMIN
        jsr     FTopToFAC
        ; AYINT does not merely fail on a number too big for a cell -- it
        ; jumps into Applesoft's error handler, which on a machine with no
        ; Applesoft under it goes somewhere unrecoverable.  Its own range
        ; check is the exponent against $90, so do that first and saturate.
        lda     FACEXP
        cmp     #$90
        bcs     @big
        jsr     AYINT
        lda     FACINT
        sta     FTMP+1
        lda     FACINT+1
        sta     FTMP
        jmp     @out
@big:   lda     FACSGN
        bmi     @neg
        lda     #$FF
        sta     FTMP
        lda     #$7F
        sta     FTMP+1
        jmp     @out
@neg:   lda     #$00
        sta     FTMP
        lda     #$80
        sta     FTMP+1
@out:   ROMOUT
        jsr     FPRestoreZ
        ldx     XSAV
        lda     FPSP
        beq     :+
        dec     FPSP
:       dex
        dex
        lda     FTMP
        sta     0,x
        lda     FTMP+1
        sta     1,x
        NEXT

        prim    "FDROP", W_FDROP, 0
        lda     FPSP
        beq     :+
        dec     FPSP
:       NEXT

        prim    "FDEPTH", W_FDEPTHW, 0
        dex
        dex
        lda     FPSP
        sta     0,x
        lda     #0
        sta     1,x
        NEXT

; --- shuffling floats about ------------------------------------------------
; Without these the arithmetic words are unusable for anything with a shape:
; a formula needs its operands more than once.  A float is five bytes, so
; these move bytes rather than cells and do not touch the ROM at all.

; TMP1 := the address of float A
FSlot1:
        tay
        lda     FOFF,y
        clc
        adc     #<FSTK
        sta     TMP1
        lda     #>FSTK
        adc     #0
        sta     TMP1+1
        rts

; TMP2 := the address of float A
FSlot2:
        tay
        lda     FOFF,y
        clc
        adc     #<FSTK
        sta     TMP2
        lda     #>FSTK
        adc     #0
        sta     TMP2+1
        rts

FCopy:                                  ; (TMP1) -> (TMP2), five bytes
        ldy     #4
@l:     lda     (TMP1),y
        sta     (TMP2),y
        dey
        bpl     @l
        rts

        prim    "FDUP", W_FDUP, 0
        lda     FPSP
        beq     @none
        cmp     #FDEPTH
        bcs     @none
        sec
        sbc     #1
        jsr     FSlot1
        lda     FPSP
        jsr     FSlot2
        jsr     FCopy
        inc     FPSP
@none:  NEXT

        prim    "FSWAP", W_FSWAP, 0
        lda     FPSP
        cmp     #2
        bcc     @none
        sec                             ; the top into the scratch slot
        sbc     #1
        jsr     FSlot1
        lda     #FDEPTH
        jsr     FSlot2
        jsr     FCopy
        lda     FPSP                    ; the one under it to the top
        sec
        sbc     #2
        jsr     FSlot1
        lda     FPSP
        sec
        sbc     #1
        jsr     FSlot2
        jsr     FCopy
        lda     #FDEPTH                 ; and the scratch down
        jsr     FSlot1
        lda     FPSP
        sec
        sbc     #2
        jsr     FSlot2
        jsr     FCopy
@none:  NEXT

        prim    "FOVER", W_FOVER, 0
        lda     FPSP
        cmp     #2
        bcc     @none
        cmp     #FDEPTH
        bcs     @none
        sec
        sbc     #2
        jsr     FSlot1
        lda     FPSP
        jsr     FSlot2
        jsr     FCopy
        inc     FPSP
@none:  NEXT

; A unary ROM operation on the top float.  The address to call is patched in.
FUnary:
        stx     XSAV
        jsr     FPSaveZ
        ROMIN
        jsr     FTopToFAC
        jsr     FCALL
        jsr     FFACToTop
        ROMOUT
        jsr     FPRestoreZ
        ldx     XSAV
        rts

.macro  FUNARY nm, lbl, target
        prim    nm, lbl, 0
        lda     #<target
        sta     FCALL+1
        lda     #>target
        sta     FCALL+2
        jsr     FUnary
        NEXT
.endmacro

        FUNARY  "FSQRT", W_FSQRT, FSQR
        FUNARY  "FSIN",  W_FSIN,  FSIN
        FUNARY  "FCOS",  W_FCOS,  FCOS
        FUNARY  "FTAN",  W_FTAN,  FTAN
        FUNARY  "FATN",  W_FATN,  FATN
        FUNARY  "FLN",   W_FLN,   FLOG
        FUNARY  "FEXP",  W_FEXP,  FEXP

; A binary operation: FAC takes the top float, A/Y points at the one under
; it, and Applesoft's routines are all of the form FAC := (A/Y) op FAC.
; All of it inside one ROM window.  Restoring zero page puts FAC back to what
; it was before the call, so the result has to be stored away first -- which
; was worth finding out here rather than from a wrong answer.
FBinary:
        lda     FPSP
        cmp     #2
        bcc     @none
        stx     XSAV
        jsr     FPSaveZ
        ROMIN
        jsr     FTopToFAC               ; FAC := top
        lda     FPSP
        sec
        sbc     #2
        jsr     FCellAY                 ; A/Y := the one under it
        jsr     FCALL                   ; FAC := (A/Y) op FAC
        dec     FPSP                    ; two in, one out
        jsr     FFACToTop
        ROMOUT
        jsr     FPRestoreZ
        ldx     XSAV
@none:  rts

.macro  FBINARY nm, lbl, target
        prim    nm, lbl, 0
        lda     #<target
        sta     FCALL+1
        lda     #>target
        sta     FCALL+2
        jsr     FBinary
        NEXT
.endmacro

        FBINARY "F+", W_FADD, FADDM
        FBINARY "F-", W_FSUB, FSUBM
        FBINARY "F*", W_FMUL, FMULM
        FBINARY "F/", W_FDIV, FDIVM

; Print the top float and drop it.  FOUT leaves a NUL-terminated string at
; $0100, which is the bottom of the return stack -- safe here because
; nothing is pushed between the call and reading it back.
        prim    "F.", W_FDOT, 0
        stx     XSAV
        jsr     FPSaveZ
        ROMIN
        jsr     FTopToFAC
        jsr     FOUT
        ROMOUT
        jsr     FPRestoreZ
        ldx     XSAV
        ldy     #0
@l:     lda     $0100,y
        beq     @done
        sty     YSAV
        jsr     PutChar
        ldy     YSAV
        iny
        bne     @l
@done:  lda     #' '
        jsr     PutChar
        lda     FPSP
        beq     :+
        dec     FPSP
:       NEXT

; --- calling anything -----------------------------------------------------
; CALL runs a subroutine with the machine as it stands.  ROMCALL switches the
; ROM back first, which is what anything at $D000-$FFFF needs -- and saves
; the zero page Applesoft treads on, because that is the usual reason to want
; it.  X is the Forth stack pointer and is parked across both.
        prim    "CALL", W_CALL, 0       ; addr --
        lda     0,x
        sta     CALLV+1
        lda     1,x
        sta     CALLV+2
        inx
        inx
        stx     XSAV
        jsr     CALLV
        ldx     XSAV
        NEXT

        prim    "ROMCALL", W_ROMCALL, 0 ; addr --
        lda     0,x
        sta     CALLV+1
        lda     1,x
        sta     CALLV+2
        inx
        inx
        stx     XSAV
        jsr     FPSaveZ
        ROMIN
        jsr     CALLV
        ROMOUT
        jsr     FPRestoreZ
        ldx     XSAV
        NEXT

; CALL-A passes a byte in the accumulator and brings back whatever comes out,
; which is how most of the monitor's entry points are spoken to.
        prim    "CALL-A", W_CALLA, 0    ; n addr -- n
        lda     0,x
        sta     CALLV+1
        lda     1,x
        sta     CALLV+2
        inx
        inx
        lda     0,x
        stx     XSAV
        jsr     CALLV
        ldx     XSAV
        sta     0,x
        lda     #0
        sta     1,x
        NEXT

; --- random ---------------------------------------------------------------
; A sixteen-bit xorshift.  Applesoft's RND is in the ROM and would need the
; card switched out for every call; this is a dozen instructions and gives
; the same period without leaving main memory.  Seeded to something non-zero,
; because xorshift from zero stays there.
        prim    "RND", W_RND, 0         ; -- u
        lda     RSEED                   ; x ^= x << 7
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        eor     RSEED+1
        sta     RSEED+1
        lda     RSEED+1                 ; x ^= x >> 9
        lsr     a
        eor     RSEED
        sta     RSEED
        lda     RSEED                   ; x ^= x << 8
        eor     RSEED+1
        sta     RSEED+1
        dex
        dex
        lda     RSEED
        sta     0,x
        lda     RSEED+1
        sta     1,x
        NEXT

        prim    "RND-SEED!", W_RNDSEED, 0
        lda     0,x
        ora     1,x
        bne     :+
        lda     #$A5                    ; zero would stick
        sta     0,x
:       lda     0,x
        sta     RSEED
        lda     1,x
        sta     RSEED+1
        inx
        inx
        NEXT

; ---------------------------------------------------------------------------
        .segment "DATA"
RSEED:   .word  $A5C3
CALLV:   jmp    $0000                    ; patched, then called
FPSP:     .byte  0                        ; floats on the stack
FTMP:    .word  0
; FZSAVE and FSTK are above the catalog with the other buffers: kernel.inc
FOFF:    .byte  0, 5, 10, 15, 20, 25, 30, 35, 40
FCALL:   jmp    $0000                    ; patched, then called
        .segment "CODE"
