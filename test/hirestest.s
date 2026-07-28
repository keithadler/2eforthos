; ---------------------------------------------------------------------------
; hirestest.s -- exercise the hi-res driver from plain assembly, before any
; Forth exists to call it.  Draws a border, two filled colour boxes, and a
; diagonal, then parks.  Everything here is a straight subroutine call into
; hires.inc.
; ---------------------------------------------------------------------------

.include "zp.inc"

.macro  setx  v
        lda     #<(v)
        sta     HX
        lda     #>(v)
        sta     HX+1
.endmacro

.macro  setx2 v
        lda     #<(v)
        sta     HX2
        lda     #>(v)
        sta     HX2+1
.endmacro

        .segment "STARTUP"
start:
        jsr     HgrFull
        lda     #$00
        jsr     HgrClear

; --- white border ----------------------------------------------------------
        lda     #3
        jsr     HgrColor
        setx    0
        setx2   279
        lda     #0
        sta     HY
        jsr     HgrHLine
        lda     #191
        sta     HY
        jsr     HgrHLine

        setx    0
        lda     #0
        sta     HY
        lda     #191
        sta     HY2
        jsr     HgrVLine
        setx    279
        lda     #0
        sta     HY
        lda     #191
        sta     HY2
        jsr     HgrVLine

; --- filled green box ------------------------------------------------------
        lda     #1
        jsr     HgrColor
        lda     #20
        sta     HY
@green: setx    20
        setx2   120
        jsr     HgrHLine
        inc     HY
        lda     HY
        cmp     #80
        bne     @green

; --- filled violet box -----------------------------------------------------
        lda     #2
        jsr     HgrColor
        lda     #100
        sta     HY
@viol:  setx    150
        setx2   260
        jsr     HgrHLine
        inc     HY
        lda     HY
        cmp     #170
        bne     @viol

; --- diagonal, one pixel at a time (exercises HgrPlot and 16-bit x) --------
        lda     #3
        jsr     HgrColor
        lda     #0
        sta     ctr
@diag:  lda     ctr
        sta     HX
        lda     #0
        sta     HX+1
        lda     ctr
        sta     HY
        jsr     HgrPlot
        inc     ctr
        lda     ctr
        cmp     #191
        bne     @diag

@halt:  jmp     @halt

        .segment "DATA"
ctr:    .byte   0

.include "hires.inc"
