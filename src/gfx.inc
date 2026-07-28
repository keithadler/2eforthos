; ---------------------------------------------------------------------------
; gfx.inc -- the drawing toolbox
;
; hires.inc knows how to put a pixel or a horizontal run on the screen and
; nothing else.  This is the layer above: arbitrary lines, circles, discs and
; reading a pixel back, all in terms of those primitives so that none of the
; aux/main bank juggling leaks upwards.
;
; Everything here is a Forth word as well as a subroutine, because the point
; of the toolbox is that the language gains the capability -- an application
; draws with the same vocabulary the desktop does.
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; HgrPoint -- is the pixel at (HX, HY) set?  Returns A = 0 or 1.
; ---------------------------------------------------------------------------
HgrPoint:
        CLAMPX  HX
        CLAMPY  HY
        jsr     HgrRow
        jsr     Div7
        sta     HCOLN
        jsr     Mod7
        sta     HMASK
        lda     HCOLN
        lsr     a
        sta     HBYTE
        bcs     @main
        bit     AUXSEL
        bcc     @go
@main:  bit     MAINSEL
@go:    ldy     HBYTE
        lda     (HBASE),y
        and     HMASK
        beq     @clear
        lda     #1
@clear: bit     MAINSEL                 ; BIT leaves A alone
        rts

; ---------------------------------------------------------------------------
; HgrLine -- a line of any slope from (HX,HY) to (HX2,HY2), by Bresenham.
;
; x is 16-bit and y is not, but the error term is kept 16-bit throughout so
; that the two axes can be treated the same way.  The loop plots first and
; tests for the end point afterwards, so a zero-length line still puts down
; its single pixel.
; ---------------------------------------------------------------------------
HgrLine:
        CLAMPX  HX
        CLAMPX  HX2
        CLAMPY  HY
        CLAMPY  HY2

        sec                             ; dx = |x2 - x1|, sx = direction
        lda     HX2
        sbc     HX
        sta     GDX
        lda     HX2+1
        sbc     HX+1
        sta     GDX+1
        bpl     @xpos
        sec                             ; negative: negate and step left
        lda     #0
        sbc     GDX
        sta     GDX
        lda     #0
        sbc     GDX+1
        sta     GDX+1
        lda     #$FF
        sta     GSX
        bne     @dy
@xpos:  lda     #1
        sta     GSX

@dy:    sec                             ; dy = |y2 - y1|, sy = direction
        lda     HY2
        sbc     HY
        bcs     @ypos
        eor     #$FF                    ; negate an 8-bit difference
        adc     #1
        sta     GDY
        lda     #$FF
        sta     GSY
        bne     @err
@ypos:  sta     GDY
        lda     #1
        sta     GSY
@err:   lda     #0
        sta     GDY+1

        sec                             ; err = dx - dy
        lda     GDX
        sbc     GDY
        sta     GERR
        lda     GDX+1
        sbc     GDY+1
        sta     GERR+1

@plot:  jsr     HgrPlot
        lda     HX                      ; reached the end point?
        cmp     HX2
        bne     @step
        lda     HX+1
        cmp     HX2+1
        bne     @step
        lda     HY
        cmp     HY2
        bne     @step
        bit     MAINSEL
        rts

@step:  lda     GERR                    ; e2 = 2 * err
        asl     a
        sta     GE2
        lda     GERR+1
        rol     a
        sta     GE2+1

        sec                             ; if e2 > -dy then x += sx
        lda     GE2
        adc     GDY                     ; e2 + dy, carry set adds nothing
        lda     GE2+1
        adc     GDY+1
        bmi     @ystep                  ; e2 + dy <= 0, skip the x step
        sec
        lda     GERR
        sbc     GDY
        sta     GERR
        lda     GERR+1
        sbc     GDY+1
        sta     GERR+1
        lda     GSX
        bmi     @xdec
        inc     HX
        bne     @ystep
        inc     HX+1
        jmp     @ystep
@xdec:  lda     HX
        bne     :+
        dec     HX+1
:       dec     HX

@ystep: sec                             ; if e2 < dx then y += sy
        lda     GE2
        sbc     GDX
        lda     GE2+1
        sbc     GDX+1
        bpl     @plot                   ; e2 >= dx, no y step
        clc
        lda     GERR
        adc     GDX
        sta     GERR
        lda     GERR+1
        adc     GDX+1
        sta     GERR+1
        lda     GSY
        bmi     @ydec
        inc     HY
        jmp     @plot
@ydec:  dec     HY
        jmp     @plot

; ---------------------------------------------------------------------------
; Circles, by the midpoint algorithm.  GFILL selects between an outline and a
; solid disc: the loop is identical, only the eight points become four spans.
;
; Centre is (GCX, GCY), radius GR.
; ---------------------------------------------------------------------------
HgrCircleOutline:
        lda     #0
        sta     GFILL
        beq     HgrCircleGo             ; always
HgrDisc:
        lda     #1
        sta     GFILL
HgrCircleGo:
        lda     #0
        sta     GPX                     ; x = 0
        sta     GPX+1
        lda     GR                      ; y = r
        sta     GPY
        sec                             ; d = 1 - r
        lda     #1
        sbc     GR
        sta     GD
        lda     #0
        sbc     #0
        sta     GD+1

@loop:  lda     GPX+1                   ; while x <= y
        beq     @check
        jmp     @done
@check: lda     GPX
        cmp     GPY
        beq     @draw
        bcc     @draw
        jmp     @done
@draw:  jsr     GfxOctants
        lda     GD+1                    ; d < 0 ?
        bmi     @dneg
        dec     GPY                     ; d += 2*(x-y)+5, y--
        clc
        lda     GD
        adc     GPX
        sta     GD
        lda     GD+1
        adc     GPX+1
        sta     GD+1
        sec
        lda     GD
        sbc     GPY
        sta     GD
        lda     GD+1
        sbc     #0
        sta     GD+1
        clc                             ; the doubling and the constant
        lda     GD                      ; folded together
        adc     GPX
        sta     GD
        lda     GD+1
        adc     GPX+1
        sta     GD+1
        sec
        lda     GD
        sbc     GPY
        sta     GD
        lda     GD+1
        sbc     #0
        sta     GD+1
        clc
        lda     GD
        adc     #5
        sta     GD
        lda     GD+1
        adc     #0
        sta     GD+1
        jmp     @next
@dneg:  clc                             ; d += 2x + 3
        lda     GD
        adc     GPX
        sta     GD
        lda     GD+1
        adc     GPX+1
        sta     GD+1
        clc
        lda     GD
        adc     GPX
        sta     GD
        lda     GD+1
        adc     GPX+1
        sta     GD+1
        clc
        lda     GD
        adc     #3
        sta     GD
        lda     GD+1
        adc     #0
        sta     GD+1
@next:  inc     GPX
        bne     :+
        inc     GPX+1
:       jmp     @loop
@done:  bit     MAINSEL
        rts

; The eight symmetric points, or the four spans that join them.
GfxOctants:
        lda     GFILL
        bne     @spans

        lda     GPX                     ; (cx+x, cy+y) and friends
        sta     GAX
        lda     GPX+1
        sta     GAX+1
        lda     GPY
        sta     GAY
        jsr     GfxFourPoints
        lda     GPY                     ; swap x and y for the other four
        sta     GAX
        lda     #0
        sta     GAX+1
        lda     GPX
        sta     GAY
        jmp     GfxFourPoints

@spans: lda     GPY                     ; solid: one span per quadrant pair
        sta     GAY
        lda     GPX
        sta     GAX
        lda     GPX+1
        sta     GAX+1
        jsr     GfxTwoSpans
        lda     GPX
        sta     GAY
        lda     GPY
        sta     GAX
        lda     #0
        sta     GAX+1
        jmp     GfxTwoSpans

; Plot (cx±ax, cy±ay), four points.
GfxFourPoints:
        jsr     GfxSetX1                ; cx + ax
        lda     GCY
        clc
        adc     GAY
        sta     HY
        jsr     GfxPlotIf
        lda     GCY
        sec
        sbc     GAY
        sta     HY
        jsr     GfxPlotIf
        jsr     GfxSetX2                ; cx - ax
        lda     GCY
        clc
        adc     GAY
        sta     HY
        jsr     GfxPlotIf
        lda     GCY
        sec
        sbc     GAY
        sta     HY
        jmp     GfxPlotIf

; Fill from (cx-ax) to (cx+ax) on the two rows cy±ay.
GfxTwoSpans:
        jsr     GfxSetX2
        lda     HX
        sta     HX2
        lda     HX+1
        sta     HX2+1
        jsr     GfxSetX1
        lda     HX
        ldy     HX+1
        sta     GTMP
        sty     GTMP+1
        lda     HX2                     ; span runs low..high
        sta     HX
        lda     HX2+1
        sta     HX+1
        lda     GTMP
        sta     HX2
        lda     GTMP+1
        sta     HX2+1
        lda     GCY
        clc
        adc     GAY
        sta     HY
        jsr     GfxSpanIf
        lda     GCY
        sec
        sbc     GAY
        sta     HY
        jmp     GfxSpanIf

GfxSetX1:                               ; HX := cx + ax
        clc
        lda     GCX
        adc     GAX
        sta     HX
        lda     GCX+1
        adc     GAX+1
        sta     HX+1
        rts

GfxSetX2:                               ; HX := cx - ax
        sec
        lda     GCX
        sbc     GAX
        sta     HX
        lda     GCX+1
        sbc     GAX+1
        sta     HX+1
        rts

; The clamping in hires.inc would drag an off-screen point to the edge and
; draw a false line there, so anything off the top or bottom is dropped.
GfxPlotIf:
        lda     HY
        cmp     #192
        bcs     @skip
        jmp     HgrPlot
@skip:  rts

GfxSpanIf:
        lda     HY
        cmp     #192
        bcs     @skip
        jmp     HgrHLine
@skip:  rts

; ---------------------------------------------------------------------------
; Forth words
; ---------------------------------------------------------------------------
        prim    "HPOINT", W_HPOINT, 0   ; x y -- flag
        lda     0,x
        sta     HY
        lda     2,x
        sta     HX
        lda     3,x
        sta     HX+1
        inx
        inx
        jsr     HgrPoint
        beq     @clear
        lda     #$FF
        sta     0,x
        sta     1,x
        NEXT
@clear: lda     #0
        sta     0,x
        sta     1,x
        NEXT

        prim    "HLINE2", W_HLINE2, 0   ; x1 y1 x2 y2 --
        lda     0,x
        sta     HY2
        lda     2,x
        sta     HX2
        lda     3,x
        sta     HX2+1
        lda     4,x
        sta     HY
        lda     6,x
        sta     HX
        lda     7,x
        sta     HX+1
        txa
        clc
        adc     #8
        tax
        jsr     HgrLine
        NEXT

        prim    "HCIRCLE", W_HCIRCLE, 0 ; xc yc r --
        jsr     GfxArgs
        jsr     HgrCircleOutline
        NEXT

        prim    "HDISC", W_HDISC, 0     ; xc yc r --
        jsr     GfxArgs
        jsr     HgrDisc
        NEXT

; Shared argument shuffle for the circle words: ( xc yc r -- )
GfxArgs:
        lda     0,x
        sta     GR
        lda     2,x
        sta     GCY
        lda     4,x
        sta     GCX
        lda     5,x
        sta     GCX+1
        txa
        clc
        adc     #6
        tax
        rts

; ---------------------------------------------------------------------------
        .segment "DATA"
GDX:    .word   0                       ; Bresenham
GDY:    .word   0
GERR:   .word   0
GE2:    .word   0
GSX:    .byte   0
GSY:    .byte   0
GCX:    .word   0                       ; circles
GCY:    .byte   0
GR:     .byte   0
GPX:    .word   0
GPY:    .byte   0
GD:     .word   0
GAX:    .word   0
GAY:    .byte   0
GFILL:  .byte   0
GTMP:   .word   0
        .segment "CODE"
