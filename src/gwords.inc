; ---------------------------------------------------------------------------
; gwords.inc -- Forth bindings for the hi-res driver
;
; Every routine in hires.inc leaves X alone, so these are just argument
; shuffles from the data stack into the driver's zero-page parameters.
; ---------------------------------------------------------------------------

        prim    "HGR", W_HGR, 0         ; graphics + 4 text lines, cleared
        jsr     HgrMixed
        lda     #$00
        jsr     HgrClear
        NEXT

        prim    "HGRFULL", W_HGRFULL, 0 ; all 192 rows, no text window
        jsr     HgrFull
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
