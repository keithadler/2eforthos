; ---------------------------------------------------------------------------
; lores.inc -- the 40x48 sixteen-colour screen
;
; Lo-res is the text page seen differently: each byte at $0400-$07FF holds
; two blocks, the low nibble above the high one, so 24 text rows become 48
; rows of colour.  There is no separate memory and no shifting -- a plot is
; a read, a mask and a write -- which makes it enormously faster than double
; hi-res for anything blocky.  A bar chart wants this, not 560 pixels.
;
; The catch on this machine is the console.  Eighty-column text keeps its
; even columns in auxiliary memory and needs 80STORE, and lo-res wants
; neither: forty columns, one bank, page one.  GR therefore puts the video
; back the way Applesoft would have it, and TEXT undoes that with the
; firmware's own Ctrl-R.
; ---------------------------------------------------------------------------

LORES   = $C056                 ; hi-res off
HIRESON = $C057

; --- mode ------------------------------------------------------------------
GrMode:
        sta     CLR80COL                ; forty columns
        sta     CLR80STORE              ; and one bank, so $0400 is main
        bit     MAINSEL                 ; page one
        bit     TXTCLR                  ; graphics
        bit     LORES
        rts

; The text window has to move, or the console scrolls straight over the
; picture: every line echoed and every OK printed lands in the same memory
; the blocks are in.  Applesoft's GR reserves the bottom four rows for text
; and this does the same.  TEXT puts the window back.
        prim    "GR", W_GR, 0           ; graphics with four lines of text
        jsr     GrMode
        bit     MIXSET
        lda     #20
        sta     WNDTOP
        lda     #0
        jsr     GrClear
        NEXT

        prim    "GR-FULL", W_GRFULL, 0
        jsr     GrMode
        bit     MIXCLR
        lda     #20                     ; still, so output cannot land on it
        sta     WNDTOP
        lda     #0
        jsr     GrClear
        NEXT

; Fill every block with the colour in A.  Both nibbles, so one byte covers
; the two rows it stands for.
GrClear:
        and     #$0F
        sta     GRT
        asl     a
        asl     a
        asl     a
        asl     a
        ora     GRT
        sta     GTMP2
        ldy     #0
@row:   lda     GRROWL,y
        sta     GPTR
        lda     GRROWH,y
        sta     GPTR+1
        sty     GRT
        ldy     #39
        lda     GTMP2
@col:   sta     (GPTR),y
        dey
        bpl     @col
        ldy     GRT
        iny
        cpy     #24
        bne     @row
        rts

        prim    "GCLS", W_GCLS, 0       ; n --
        lda     0,x
        inx
        inx
        jsr     GrClear
        NEXT

        prim    "GCOLOR!", W_GCOLOR, 0  ; n --
        lda     0,x
        and     #$0F
        sta     GCOL
        inx
        inx
        NEXT

; --- plotting --------------------------------------------------------------
; GPTR := the row holding lo-res row GLY, and A := which nibble of it.
; Out of range is dropped rather than wrapped: a chart drawn one row too far
; should lose a bar, not scribble on the row above.
GrAddr:
        lda     GLY
        cmp     #48
        bcs     @off
        lda     GLX
        cmp     #40
        bcs     @off
        lda     GLY
        lsr     a
        tay
        lda     GRROWL,y
        sta     GPTR
        lda     GRROWH,y
        sta     GPTR+1
        lda     GLY
        and     #$01
        clc                             ; carry clear: on screen
        rts
@off:   sec
        rts

GrPlot:
        jsr     GrAddr
        bcs     @done
        beq     @low
        ldy     GLX                     ; the lower block of the pair
        lda     (GPTR),y
        and     #$0F
        sta     GRT
        lda     GCOL
        asl     a
        asl     a
        asl     a
        asl     a
        ora     GRT
        sta     (GPTR),y
        rts
@low:   ldy     GLX
        lda     (GPTR),y
        and     #$F0
        sta     GRT
        lda     GCOL
        ora     GRT
        sta     (GPTR),y
@done:  rts

        prim    "GPLOT", W_GPLOT, 0     ; x y --
        lda     0,x
        sta     GLY
        lda     2,x
        sta     GLX
        inx
        inx
        inx
        inx
        jsr     GrPlot
        NEXT

        prim    "GSCRN", W_GSCRN, 0     ; x y -- n
        lda     0,x
        sta     GLY
        lda     2,x
        sta     GLX
        inx
        inx
        jsr     GrAddr
        bcs     @off
        beq     @low
        ldy     GLX
        lda     (GPTR),y
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        jmp     @put
@low:   ldy     GLX
        lda     (GPTR),y
        and     #$0F
        jmp     @put
@off:   lda     #0
@put:   sta     0,x
        lda     #0
        sta     1,x
        NEXT

; GHLIN and GVLIN are in system.fth, three lines each on top of GPLOT.  They
; were here in assembly and drew the wrong spans; a lo-res row is forty
; blocks and a column forty-eight, so the loop is not worth being clever
; about and certainly not worth being wrong about.

; ---------------------------------------------------------------------------
        .segment "RODATA"
; Lo-res rows come in pairs, so there are 24 of them and they are the text
; screen's own scrambled order.
GRROWL:
        .repeat 24, r
        .byte   <($0400 + (r - (r/8)*8)*$80 + (r/8)*$28)
        .endrep
GRROWH:
        .repeat 24, r
        .byte   >($0400 + (r - (r/8)*8)*$80 + (r/8)*$28)
        .endrep

        .segment "DATA"
GCOL:    .byte  15
GLX:     .byte  0
GLY:     .byte  0
GRT:    .byte  0
GTMP2:   .byte  0
        .segment "CODE"
