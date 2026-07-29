; ---------------------------------------------------------------------------
; fill.inc -- flood fill, and drawing a stored bitmap
;
; The fill is by scanlines, not by pixels: the seed stack holds one entry per
; run rather than one per pixel, so a shape a few hundred pixels across costs
; a few hundred entries instead of tens of thousands.  Each run is drawn with
; HgrHLine, which writes whole bytes in the middle and is the only reason a
; large area finishes in a reasonable time.
;
; What it fills is the connected region of pixels that match the seed, and it
; fills them with the opposite value.  Defining it that way rather than "fill
; with HCOLOR" is what makes it terminate: a dithered pattern leaves some of
; the pixels it writes still matching the seed, and those pixels seed the fill
; again for as long as you care to wait.  Filling with black is the same word
; with the seed on a white region.
; ---------------------------------------------------------------------------

; Runs pending at once.  A rectangle pushes a seed for the row above and the
; row below every run it fills, so the stack grows with the height of the
; shape rather than its area -- but it does grow, and ninety-six was not
; enough to fill a box a hundred rows tall.  Overflowing only loses a patch;
; running out of dictionary would lose everything.
FSMAX   = 250

; The three arrays live in the spare room above the catalog rather than in
; the kernel -- every byte the kernel does not spend is a byte the
; dictionary gets.  FSXL, FSXH and FSY are defined in kernel.inc's map of
; that region, with everything else that lives there.

; Test the pixel at (FX, FY).  A := 0 or 1.  HgrPoint takes its arguments in
; HX/HY, so this is a wrapper that keeps the fill's own coordinates separate
; from the ones the drawing words are using.
FillTest:
        lda     FX
        sta     HX
        lda     FX+1
        sta     HX+1
        lda     FY
        sta     HY
        jsr     HgrPoint
        rts

; Push (FX, FY) as a pending run, quietly dropping it if the stack is full.
; A dropped seed means an unfilled patch, which is visible and harmless; the
; alternative is scribbling past the end of the array, which is neither.
FillPush:
        ldy     FSP
        cpy     #FSMAX
        bcs     @full
        lda     FX
        sta     FSXL,y
        lda     FX+1
        sta     FSXH,y
        lda     FY
        sta     FSY,y
        inc     FSP
@full:  rts

; ---------------------------------------------------------------------------
; HgrFill -- flood from (HX, HY)
; ---------------------------------------------------------------------------
HgrFill:
        CLAMPX  HX
        CLAMPY  HY
        lda     HX
        sta     FX
        lda     HX+1
        sta     FX+1
        lda     HY
        sta     FY
        jsr     FillTest
        sta     FSEED                   ; the value being replaced
        lda     #0
        sta     FSP
        jsr     FillPush

@pop:   lda     FSP
        bne     @take
        jmp     @done
@take:  dec     FSP
        ldy     FSP
        lda     FSXL,y
        sta     FX
        lda     FSXH,y
        sta     FX+1
        lda     FSY,y
        sta     FY
        jsr     FillTest                ; another run may have covered it
        cmp     FSEED
        bne     @pop

        lda     FX                      ; remember where the run started
        sta     FSAVE
        lda     FX+1
        sta     FSAVE+1

@left:  lda     FX                      ; walk left while the pixels match
        ora     FX+1
        beq     @haveleft               ; column zero: stop
        lda     FX
        bne     :+
        dec     FX+1
:       dec     FX
        jsr     FillTest
        cmp     FSEED
        beq     @left
        inc     FX                      ; stepped one too far
        bne     @haveleft
        inc     FX+1
@haveleft:
        lda     FX
        sta     FL
        lda     FX+1
        sta     FL+1

        lda     FSAVE                   ; back to the seed, then walk right
        sta     FX
        lda     FSAVE+1
        sta     FX+1
@right: lda     FX+1
        cmp     #>559
        bcc     @stepright
        lda     FX
        cmp     #<559
        bcs     @haveright              ; last column: stop
@stepright:
        inc     FX
        bne     :+
        inc     FX+1
:       jsr     FillTest
        cmp     FSEED
        beq     @right
        lda     FX                      ; stepped one too far
        bne     :+
        dec     FX+1
:       dec     FX
@haveright:
        lda     FX
        sta     FR
        lda     FX+1
        sta     FR+1

        lda     FL                      ; draw the run
        sta     HX
        lda     FL+1
        sta     HX+1
        lda     FR
        sta     HX2
        lda     FR+1
        sta     HX2+1
        lda     FY
        sta     HY
        jsr     HgrHLine

        lda     FY                      ; and look for runs above and below.
        sta     FROWSAV                 ; FillScan works through FY, so the
        beq     @below                  ; row we are on has to be kept here
        sec
        sbc     #1
        jsr     FillScan
@below: lda     FROWSAV
        cmp     #191
        bcc     @dobelow
        jmp     @pop
@dobelow:
        lda     FROWSAV
        clc
        adc     #1
        jsr     FillScan
        jmp     @pop
@done:  rts

; Walk row A between FL and FR and push one seed per run of matching pixels.
; One seed per run, not per pixel: that is what keeps the stack small.
FillScan:
        sta     FROW
        lda     FL
        sta     FX
        lda     FL+1
        sta     FX+1
        lda     #0
        sta     FRUN                    ; are we inside a run?
@l:     lda     FROW
        sta     FY
        jsr     FillTest
        cmp     FSEED
        bne     @nomatch
        lda     FRUN
        bne     @next                   ; already seeded this run
        lda     FROW
        sta     FY
        jsr     FillPush
        lda     #1
        sta     FRUN
        bne     @next
@nomatch:
        lda     #0
        sta     FRUN
@next:  lda     FX+1                    ; past the right end of the parent run?
        cmp     FR+1
        bcc     @step
        lda     FX
        cmp     FR
        bcs     @endscan
@step:  inc     FX
        bne     @l
        inc     FX+1
        jmp     @l
@endscan:
        rts

; ---------------------------------------------------------------------------
; HgrBlit -- draw the bitmap at BSRC, BW pixels by BH rows, at (BX, BY)
;
; Rows are whole bytes, eight pixels each, bit 0 leftmost, padded at the right
; end.  A set bit plots in the current colour and a clear bit leaves the
; screen alone, so a shape is drawn without a mask and without a rectangle of
; background around it.  With HXOR on, drawing it twice puts the screen back.
; ---------------------------------------------------------------------------
HgrBlit:
        lda     BSRC                    ; the row pointer has to be indirect,
        sta     UTMP                    ; so it has to be in zero page
        lda     BSRC+1
        sta     UTMP+1
        lda     BW                      ; bytes per row = (BW + 7) / 8
        clc
        adc     #7
        sta     BSTRIDE
        lda     BW+1
        adc     #0
        lsr     a
        ror     BSTRIDE
        lsr     a
        ror     BSTRIDE
        lsr     a
        ror     BSTRIDE

        lda     #0
        sta     BROW
@row:   lda     BROW
        cmp     BH
        bcc     @dorow
        jmp     @done
@dorow:

        lda     #0                      ; column within the row
        sta     BCOL
        sta     BCOL+1
@col:   lda     BCOL+1
        cmp     BW+1
        bcc     @doit
        lda     BCOL
        cmp     BW
        bcc     @doit
        jmp     @nextrow
@doit:  lda     BCOL                    ; the bit's byte and position
        and     #$07
        sta     BBIT
        lda     BCOL+1
        lsr     a
        lda     BCOL
        ror     a
        lsr     a
        lsr     a
        tay
        lda     (UTMP),y
        ldy     BBIT
        bne     @shift
        jmp     @have
@shift: lsr     a
        dey
        bne     @shift
@have:  and     #$01
        beq     @skip

        clc                             ; plot at BX+col, BY+row
        lda     BX
        adc     BCOL
        sta     HX
        lda     BX+1
        adc     BCOL+1
        sta     HX+1
        clc
        lda     BY
        adc     BROW
        sta     HY
        jsr     HgrPlot

@skip:  inc     BCOL
        bne     @col
        inc     BCOL+1
        jmp     @col

@nextrow:
        clc                             ; next row of the source
        lda     UTMP
        adc     BSTRIDE
        sta     UTMP
        lda     UTMP+1
        adc     #0
        sta     UTMP+1
        inc     BROW
        jmp     @row
@done:  rts

; ---------------------------------------------------------------------------
; Forth words
; ---------------------------------------------------------------------------
        prim    "HFILL", W_HFILL, 0     ; x y --
        lda     0,x
        sta     HY
        lda     2,x
        sta     HX
        lda     3,x
        sta     HX+1
        inx
        inx
        inx
        inx
        jsr     HgrFill
        NEXT

        prim    "BLIT", W_BLIT, 0       ; addr w h x y --
        lda     0,x
        sta     BY
        lda     2,x
        sta     BX
        lda     3,x
        sta     BX+1
        lda     4,x
        sta     BH
        lda     6,x
        sta     BW
        lda     7,x
        sta     BW+1
        lda     8,x
        sta     BSRC
        lda     9,x
        sta     BSRC+1
        txa
        clc
        adc     #10
        tax
        jsr     HgrBlit
        NEXT

; ---------------------------------------------------------------------------
        .segment "DATA"
FX:      .word  0                       ; the fill's own cursor
FY:      .byte  0
FL:      .word  0                       ; the run being drawn
FR:      .word  0
FSAVE:   .word  0
FSEED:   .byte  0                       ; the value being replaced
FSP:     .byte  0
FROW:    .byte  0
FROWSAV: .byte  0
FRUN:    .byte  0

BSRC:    .word  0
BW:      .word  0
BH:      .byte  0
BX:      .word  0
BY:      .byte  0
BROW:    .byte  0
BCOL:    .word  0
BBIT:    .byte  0
BSTRIDE: .byte  0
        .segment "CODE"
