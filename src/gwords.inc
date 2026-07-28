; ---------------------------------------------------------------------------
; gwords.inc -- Forth bindings for the hi-res driver
;
; Every routine in hires.inc leaves X alone, so these are just argument
; shuffles from the data stack into the driver's zero-page parameters.
; Coordinates are 0..559 by 0..191.
; ---------------------------------------------------------------------------

        prim    "HGR", W_HGR, 0         ; full-screen double hi-res, cleared
        jsr     HgrOn
        lda     #$00
        jsr     HgrClear
        NEXT

        prim    "TEXT", W_TEXTMODE, 0
        jsr     HgrText
        NEXT

        prim    "HCLS", W_HCLS, 0
        lda     #$00
        jsr     HgrClear
        NEXT

        prim    "HCOLOR", W_HCOLOR, 0   ; n --
        lda     0,x
        inx
        inx
        jsr     HgrColor
        NEXT

        prim    "HXOR", W_HXOR, 0       ; flag --
        lda     0,x                     ; any non-zero flag turns it on; the
        ora     1,x                     ; driver tests bit 7
        beq     @off
        lda     #$80
@off:   sta     HXORF
        inx
        inx
        NEXT

        prim    "HPLOT", W_HPLOT, 0     ; x y --
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
        jsr     HgrPlot
        NEXT

        prim    "HLINE", W_HLINE, 0     ; x1 x2 y --
        lda     0,x
        sta     HY
        lda     2,x
        sta     HX2
        lda     3,x
        sta     HX2+1
        lda     4,x
        sta     HX
        lda     5,x
        sta     HX+1
        txa
        clc
        adc     #6
        tax
        jsr     HgrHLine
        NEXT

        prim    "HBOX", W_HBOX, 0       ; x1 x2 y1 y2 -- (filled rectangle)
        lda     0,x
        sta     HY2
        lda     2,x
        sta     HY
        lda     4,x
        sta     HX2
        lda     5,x
        sta     HX2+1
        lda     6,x
        sta     HX
        lda     7,x
        sta     HX+1
        txa
        clc
        adc     #8
        tax
        jsr     HgrFillRect
        NEXT

        prim    "HVLINE", W_HVLINE, 0   ; x y1 y2 --
        lda     0,x
        sta     HY2
        lda     2,x
        sta     HY
        lda     4,x
        sta     HX
        lda     5,x
        sta     HX+1
        txa
        clc
        adc     #6
        tax
        jsr     HgrVLine
        NEXT
