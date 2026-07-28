; ---------------------------------------------------------------------------
; hires.inc -- Apple II hi-res screen driver, 280x192
;
; The hi-res screen is 8K at $2000 with a famously scrambled row order: the
; address of row y is
;
;       $2000 + $400*(y mod 8) + $80*((y/8) mod 8) + $28*(y/64)
;
; so rows are looked up in a table rather than computed.  Horizontally, each
; byte holds 7 pixels in bits 0-6; bit 7 selects the colour palette for that
; byte.  x/7 and 1<<(x mod 7) are likewise table lookups, because 280 > 255
; means x is a 16-bit quantity and dividing it by 7 per pixel would be slow.
;
; Colour: a byte's pixel pattern shifts by 7 bit positions from one byte to
; the next, and 7 is odd, so a two-pixel-period colour pattern inverts every
; byte column.  Each colour therefore carries two bytes -- one for even byte
; columns, one for odd -- and the driver picks by column parity.
; ---------------------------------------------------------------------------

HGRPAGE     = $2000             ; hi-res page 1
HGRSIZE     = $2000             ; 8K

; --- soft switches ---------------------------------------------------------
TXTCLR      = $C050             ; graphics on
TXTSET      = $C051             ; text on
MIXCLR      = $C052             ; full screen
MIXSET      = $C053             ; graphics + 4 lines of text at the bottom
LOWSCR      = $C054             ; display page 1
HISCR       = $C055             ; display page 2
LORESSW     = $C056
HIRESSW     = $C057

; ---------------------------------------------------------------------------
; Bounds clamping.
;
; Every coordinate entering the driver is clamped, because the x and row
; lookups are raw table indexes: an x of 300 or a y of 200 would read past
; the end of a table and scribble on whatever the resulting address pointed
; at.  Windows dragged towards an edge rely on this.
; ---------------------------------------------------------------------------
.macro  CLAMPX addr
        .local  zero, top, done
        lda     addr+1
        bmi     zero                    ; negative
        beq     done                    ; 0..255 is always in range
        cmp     #1
        bne     top                     ; >= $200
        lda     addr
        cmp     #<280                   ; 279 = $0117
        bcc     done
top:    lda     #<279
        sta     addr
        lda     #>279
        sta     addr+1
        jmp     done
zero:   lda     #0
        sta     addr
        sta     addr+1
done:
.endmacro

.macro  CLAMPY addr
        .local  done
        lda     addr
        cmp     #192
        bcc     done
        lda     #191
        sta     addr
done:
.endmacro

; ---------------------------------------------------------------------------
; Mode control
; ---------------------------------------------------------------------------

; Hi-res page 1 with a four-line text window at the bottom -- graphics above,
; the Forth prompt below.
; Mixed mode shows only text rows 20-23, so the monitor's text window has to
; be moved down to match -- otherwise COUT happily writes to rows the display
; is not showing.
WNDTOP  = $22
CH      = $24
CV      = $25
VTAB    = $FC22                 ; recompute the line base from CV

HgrMixed:
        bit     TXTCLR
        bit     MIXSET
        bit     LOWSCR
        bit     HIRESSW
        lda     #20
        sta     WNDTOP
        sta     CV
        lda     #0
        sta     CH
        stx     XSAV
        jsr     VTAB
        ldx     XSAV
        rts

HgrFull:
        bit     TXTCLR
        bit     MIXCLR
        bit     LOWSCR
        bit     HIRESSW
        rts

HgrText:
        bit     TXTSET
        lda     #0
        sta     WNDTOP
        rts

; Select drawing colour 0..7 (see HCOLTBL at the bottom of this file).
HgrColor:
        and     #$07
        asl     a
        tay
        lda     HCOLTBL,y
        sta     HCOLE
        lda     HCOLTBL+1,y
        sta     HCOLO
        rts

; Clear the hi-res page to the byte in A (0 = black, $80 = the other black).
HgrClear:
        sta     HTMP2
        lda     #$00
        sta     HPTR
        lda     #>HGRPAGE
        sta     HPTR+1
        lda     #>HGRSIZE       ; page count
        sta     HTMP
        lda     HTMP2
        ldy     #$00
@byte:  sta     (HPTR),y
        iny
        bne     @byte
        inc     HPTR+1
        dec     HTMP
        bne     @byte
        rts

; ---------------------------------------------------------------------------
; Coordinate helpers
; ---------------------------------------------------------------------------

; HBASE := address of raster row HY
HgrRow:
        ldy     HY
        lda     HGRROWL,y
        sta     HBASE
        lda     HGRROWH,y
        sta     HBASE+1
        rts

; A := DIV7[HX]  -- the byte column holding pixel HX
Div7:
        clc
        lda     #<DIV7TBL
        adc     HX
        sta     HPTR
        lda     #>DIV7TBL
        adc     HX+1
        sta     HPTR+1
        ldy     #$00
        lda     (HPTR),y
        rts

; A := MOD7[HX]  -- 1 << (HX mod 7), the bit within that byte
Mod7:
        clc
        lda     #<MOD7TBL
        adc     HX
        sta     HPTR
        lda     #>MOD7TBL
        adc     HX+1
        sta     HPTR+1
        ldy     #$00
        lda     (HPTR),y
        rts

; A := HX mod 7 -- how far the pixel sits into its byte.  The pointer needs
; the shift count itself, not the 1<<k mask that Mod7 returns.
Mod7K:
        clc
        lda     #<MOD7KTBL
        adc     HX
        sta     HPTR
        lda     #>MOD7KTBL
        adc     HX+1
        sta     HPTR+1
        ldy     #$00
        lda     (HPTR),y
        rts

; ---------------------------------------------------------------------------
; MergeByte -- write HMASK's worth of the current colour into (HBASE),Y
;
; Only the masked bits change:  new = old XOR ((old XOR colour) AND mask).
; Bit 7 is not a pixel, so it is replaced wholesale from the colour byte.
; ---------------------------------------------------------------------------
MergeByte:
        tya                     ; column parity picks the colour byte
        lsr     a
        bcc     @even
        lda     HCOLO
        bcs     @have           ; carry is set here -- unconditional
@even:  lda     HCOLE
@have:  sta     HCOLB
        lda     (HBASE),y
        eor     HCOLB
        and     HMASK
        eor     (HBASE),y
        and     #$7F
        sta     HTMP2
        lda     HCOLB
        and     #$80            ; palette bit comes from the colour
        ora     HTMP2
        sta     (HBASE),y
        rts

; ---------------------------------------------------------------------------
; HgrPlot -- set the pixel at (HX, HY)
; ---------------------------------------------------------------------------
HgrPlot:
        CLAMPX  HX
        CLAMPY  HY
        jsr     HgrRow
        jsr     Div7
        sta     HTMP
        jsr     Mod7
        sta     HMASK
        ldy     HTMP
        jmp     MergeByte

; ---------------------------------------------------------------------------
; HgrHLine -- horizontal span from HX to HX2 inclusive on row HY.
;
; Whole bytes in the middle are stored outright; only the two end bytes need
; read-modify-write.  That is what makes filling fast enough to be useful.
; Caller guarantees HX <= HX2.
; ---------------------------------------------------------------------------
HgrHLine:
        CLAMPX  HX
        CLAMPX  HX2
        CLAMPY  HY
        lda     HX2+1                   ; put the endpoints in order first: a
        cmp     HX+1                    ; reversed span would send the middle
        bcc     @swap                   ; fill loop off the end of the row
        bne     @ordered
        lda     HX2
        cmp     HX
        bcs     @ordered
@swap:  lda     HX
        ldy     HX2
        sty     HX
        sta     HX2
        lda     HX+1
        ldy     HX2+1
        sty     HX+1
        sta     HX2+1
@ordered:
        jsr     HgrRow
        jsr     Div7
        sta     HB1
        jsr     Mod7            ; bit k at the left edge
        sec
        sbc     #$01            ; (1<<k)-1 = bits below k
        eor     #$FF            ; ~that       = bits k..7
        and     #$7F
        sta     HLM             ; left mask: k..6

        lda     HX2             ; now do the right edge
        sta     HX
        lda     HX2+1
        sta     HX+1
        jsr     Div7
        sta     HB2
        jsr     Mod7            ; bit j at the right edge
        asl     a               ; 1<<(j+1)
        sec
        sbc     #$01            ; bits 0..j
        and     #$7F
        sta     HRM             ; right mask

        lda     HB1
        cmp     HB2
        bne     @multi
        lda     HLM             ; span lives inside one byte
        and     HRM
        sta     HMASK
        ldy     HB1
        jmp     MergeByte

@multi: ldy     HB1             ; left partial byte
        lda     HLM
        sta     HMASK
        jsr     MergeByte

        ldy     HB1             ; solid bytes in between
        iny
@mid:   cpy     HB2
        beq     @right
        tya
        lsr     a
        bcc     @mideven
        lda     HCOLO
        bcs     @midput
@mideven:
        lda     HCOLE
@midput:
        sta     (HBASE),y
        iny
        bne     @mid

@right: ldy     HB2             ; right partial byte
        lda     HRM
        sta     HMASK
        jmp     MergeByte

; ---------------------------------------------------------------------------
; HgrVLine -- vertical span at HX from HY to HY2 inclusive.
; x is fixed, so the byte column and bit mask are computed once.
; Caller guarantees HY <= HY2.
; ---------------------------------------------------------------------------
HgrVLine:
        CLAMPX  HX
        CLAMPY  HY
        CLAMPY  HY2
        lda     HY                      ; order the endpoints
        cmp     HY2
        bcc     @ordered
        beq     @ordered
        ldy     HY2
        sta     HY2
        sty     HY
@ordered:
        jsr     Div7
        sta     HTMP
        jsr     Mod7
        sta     HMASK
@loop:  jsr     HgrRow
        ldy     HTMP
        jsr     MergeByte
        lda     HY
        cmp     HY2
        bcs     @done                   ; >= rather than =, so a stray HY
        inc     HY                      ; cannot run past the row table
        bne     @loop
@done:  rts

; ---------------------------------------------------------------------------
; HgrFillRect -- solid rectangle HX..HX2 by HY..HY2.
;
; Filling row by row from Forth costs a few hundred cycles of threading per
; row; doing the whole rectangle here makes a full-screen repaint fast enough
; to drag a window against.  HgrHLine consumes HX, so the span is restored
; from a copy on every row.
; ---------------------------------------------------------------------------
HgrFillRect:
        CLAMPY  HY
        CLAMPY  HY2
        lda     HY                      ; order the rows
        cmp     HY2
        bcc     @ordered
        beq     @ordered
        ldy     HY2
        sta     HY2
        sty     HY
@ordered:
        lda     HX
        sta     HFX1
        lda     HX+1
        sta     HFX1+1
        lda     HX2
        sta     HFX2
        lda     HX2+1
        sta     HFX2+1
@row:   lda     HFX1
        sta     HX
        lda     HFX1+1
        sta     HX+1
        lda     HFX2
        sta     HX2
        lda     HFX2+1
        sta     HX2+1
        jsr     HgrHLine
        lda     HY
        cmp     HY2
        bcs     @done
        inc     HY
        bne     @row
@done:  rts

; ---------------------------------------------------------------------------
; Tables
; ---------------------------------------------------------------------------

; Row -> screen address.  Written as integer arithmetic rather than shifts and
; masks so the decomposition stays readable: row = 8a+b, a = 8c+d, giving
; base + $400*b + $80*d + $28*c.  (The loop variable cannot be called `y` --
; ca65 reserves that as a register name.)
HGRROWL:
        .repeat 192, row
        .byte   <(HGRPAGE + (row - (row/8)*8)*$400 + ((row/8) - (row/64)*8)*$80 + (row/64)*$28)
        .endrep
HGRROWH:
        .repeat 192, row
        .byte   >(HGRPAGE + (row - (row/8)*8)*$400 + ((row/8) - (row/64)*8)*$80 + (row/64)*$28)
        .endrep

; 280 pixels is exactly 40 bytes of 7, so both tables are one 7-entry pattern
; repeated 40 times -- x/7 is the byte column, 1<<(x mod 7) is the bit in it.
DIV7TBL:
        .repeat 40, col
        .byte   col, col, col, col, col, col, col
        .endrep
MOD7TBL:
        .repeat 40
        .byte   $01, $02, $04, $08, $10, $20, $40
        .endrep
MOD7KTBL:
        .repeat 40
        .byte   0, 1, 2, 3, 4, 5, 6
        .endrep

; Applesoft's eight colours, as (even column, odd column) byte pairs.
;   0 black   1 green   2 violet  3 white
;   4 black2  5 orange  6 blue    7 white2
; Span endpoints held across the rows of a rectangle fill.  Kept here rather
; than in the caller so that hires.inc stands on its own -- test/hirestest.s
; includes it without any of the Forth system.
        .segment "DATA"
HFX1:   .word   0
HFX2:   .word   0
        .segment "CODE"

HCOLTBL:
        .byte   $00,$00         ; black
        .byte   $2A,$55         ; green
        .byte   $55,$2A         ; violet
        .byte   $7F,$7F         ; white
        .byte   $80,$80         ; black (palette 2)
        .byte   $AA,$D5         ; orange
        .byte   $D5,$AA         ; blue
        .byte   $FF,$FF         ; white (palette 2)
