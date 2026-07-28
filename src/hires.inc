; ---------------------------------------------------------------------------
; hires.inc -- Apple //e double hi-res driver, 560x192 monochrome
;
; Double hi-res doubles the horizontal resolution by fetching two bytes per
; position, one from auxiliary memory and one from main.  A row of 80 byte
; columns is interleaved
;
;       aux[0] main[0] aux[1] main[1] ... aux[39] main[39]
;
; so byte column c lives at HGRROW[y] + (c >> 1), in aux when c is even and
; main when it is odd.  Each byte still carries 7 pixels in bits 0-6; in
; monochrome double hi-res bit 7 is not a palette bit and is simply unused,
; which makes this driver simpler than the ][+ one it replaces.
;
; Choosing the bank is a soft switch, not an address: with 80STORE set, $C055
; points $2000-$3FFF at aux and $C054 at main.  Every routine here leaves main
; selected on the way out, because 80STORE also makes that switch control the
; text page at $0400-$07FF -- leaving aux selected would send the monitor's
; output somewhere the display never looks.
;
; The row order is still the scrambled hi-res one:
;       $2000 + $400*(y mod 8) + $80*((y/8) mod 8) + $28*(y/64)
; and x/7, 1<<(x mod 7) and x mod 7 are still table lookups, now 560 entries
; each -- 560 is exactly 80*7, so each is one 7-entry pattern repeated.
; ---------------------------------------------------------------------------

HGRPAGE     = $2000             ; hi-res page 1, in both banks
HGRSIZE     = $2000             ; 8K per bank

; --- soft switches ---------------------------------------------------------
TXTCLR      = $C050             ; graphics on
TXTSET      = $C051             ; text on
MIXCLR      = $C052             ; full screen
MIXSET      = $C053             ; graphics + 4 text lines
MAINSEL     = $C054             ; with 80STORE: $2000-$3FFF from main
AUXSEL      = $C055             ; ...from auxiliary memory
HIRESSW     = $C057
CLR80STORE  = $C000
SET80STORE  = $C001
CLR80COL    = $C00C
SET80COL    = $C00D
SETDHIRES   = $C05E
CLRDHIRES   = $C05F

WNDTOP      = $22
CH          = $24
CV          = $25

; ---------------------------------------------------------------------------
; Bounds clamping.  Coordinates index tables directly, so an x of 600 or a y
; of 200 would read past the end and scribble on whatever that addressed.
; ---------------------------------------------------------------------------
.macro  CLAMPX addr
        .local  zero, top, done
        lda     addr+1
        bmi     zero                    ; negative
        cmp     #2
        bcc     done                    ; high byte 0 or 1: always in range
        bne     top
        lda     addr
        cmp     #<560                   ; 559 = $022F
        bcc     done
top:    lda     #<559
        sta     addr
        lda     #>559
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

; Full-screen monochrome double hi-res.  80COL and 80STORE must both be set:
; the first makes the video hardware fetch aux bytes, the second makes the
; page switch decide which bank the CPU writes to.
HgrOn:
        bit     TXTCLR
        bit     MIXCLR
        bit     HIRESSW
        sta     SET80COL
        sta     SET80STORE
        bit     SETDHIRES
        bit     MAINSEL
        rts

; Out of graphics and back to the console, which is 80 columns.  80COL and
; 80STORE stay set: the first is what makes the video hardware fetch the aux
; half of each text row, the second is what lets the firmware write it.
; Clearing them left the screen showing main memory alone -- every other
; character of the line, which is what an 80-column screen displayed 40
; columns wide looks like.
HgrText:
        bit     TXTSET
        bit     CLRDHIRES
        sta     SET80COL
        sta     SET80STORE
        bit     MAINSEL
        lda     #0
        sta     WNDTOP
        rts

; Select the dither pattern, 0..7 (see HCOLTBL at the bottom of this file).
HgrColor:
        and     #$07
        asl     a
        tay
        lda     HCOLTBL,y
        sta     HCOLE
        lda     HCOLTBL+1,y
        sta     HCOLO
        rts

; Clear both banks to the byte in A.
HgrClear:
        sta     HTMP2
        bit     AUXSEL
        jsr     ClearBank
        bit     MAINSEL
        jmp     ClearBank

ClearBank:
        lda     #$00
        sta     HPTR
        lda     #>HGRPAGE
        sta     HPTR+1
        lda     #>HGRSIZE               ; page count
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

; HBASE := address of raster row HY (the same in both banks)
HgrRow:
        ldy     HY
        lda     HGRROWL,y
        sta     HBASE
        lda     HGRROWH,y
        sta     HBASE+1
        rts

; A := DIV7[HX] -- the byte column, 0..79
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

; A := MOD7[HX] -- 1 << (HX mod 7)
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

; A := HX mod 7 -- the shift count, which the pointer needs
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

; Point the CPU at the bank holding byte column A and leave that byte's index
; within the row in HBYTE.
SelectBank:
        lsr     a
        sta     HBYTE
        bcs     @main
        bit     AUXSEL
        rts
@main:  bit     MAINSEL
        rts

; ---------------------------------------------------------------------------
; MergeByte -- write HMASK's worth of the dither pattern into byte column
; HCOLN of the current row.  Only the masked bits change:
;       new = old XOR ((old XOR pattern) AND mask)
; ---------------------------------------------------------------------------
MergeByte:
        lda     HCOLN
        lsr     a
        sta     HBYTE
        lda     HCOLN                   ; dither phase alternates along BOTH
        eor     HY                      ; axes, or a 50% pattern comes out as
        lsr     a                       ; vertical stripes instead of grey
        bcs     @phaseB
        lda     HCOLE
        bcc     @have                   ; carry is clear here -- unconditional
@phaseB:
        lda     HCOLO
@have:  sta     HCOLB
        lda     HCOLN                   ; the bank, though, is column parity
        lsr     a
        bcs     @main
        bit     AUXSEL
        bcc     @go
@main:  bit     MAINSEL
@go:    ldy     HBYTE
        bit     HXORF                   ; XOR mode leaves out the read, so the
        bmi     @xorm                   ; masked bits flip rather than take
        lda     (HBASE),y               ; the pattern
        eor     HCOLB
        jmp     @merge
@xorm:  lda     HCOLB
@merge: and     HMASK
        eor     (HBASE),y
        and     #$7F                    ; bit 7 is not a pixel
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
        sta     HCOLN
        jsr     Mod7
        sta     HMASK
        jsr     MergeByte
        bit     MAINSEL
        rts

; ---------------------------------------------------------------------------
; HgrHLine -- horizontal span from HX to HX2 inclusive on row HY.
; Whole bytes in the middle are stored outright; only the two end bytes need
; read-modify-write.  Every store still has to pick its bank.
; ---------------------------------------------------------------------------
HgrHLine:
        CLAMPX  HX
        CLAMPX  HX2
        CLAMPY  HY
        lda     HX2+1                   ; put the endpoints in order
        cmp     HX+1
        bcc     @swap
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
        jsr     Mod7                    ; bit k at the left edge
        sec
        sbc     #$01                    ; (1<<k)-1 = bits below k
        eor     #$FF
        and     #$7F
        sta     HLM                     ; left mask: bits k..6

        lda     HX2                     ; now the right edge
        sta     HX
        lda     HX2+1
        sta     HX+1
        jsr     Div7
        sta     HB2
        jsr     Mod7
        asl     a
        sec
        sbc     #$01
        and     #$7F
        sta     HRM

        lda     HB1
        cmp     HB2
        bne     @multi
        lda     HLM                     ; the span lives inside one byte
        and     HRM
        sta     HMASK
        lda     HB1
        sta     HCOLN
        jsr     MergeByte
        bit     MAINSEL
        rts

@multi: lda     HB1                     ; left partial byte
        sta     HCOLN
        lda     HLM
        sta     HMASK
        jsr     MergeByte

        lda     HB1                     ; solid bytes in between
        clc
        adc     #1
        sta     HCOLN
@mid:   lda     HCOLN
        cmp     HB2
        beq     @right
        lsr     a
        sta     HBYTE
        bcs     @midmain
        bit     AUXSEL
        bcc     @midphase
@midmain:
        bit     MAINSEL
@midphase:
        lda     HCOLN
        eor     HY
        lsr     a
        bcs     @midB
        lda     HCOLE
        bcc     @midput
@midB:  lda     HCOLO
@midput:
        ldy     HBYTE
        bit     HXORF                   ; the whole bytes in the middle of a
        bpl     @midset                 ; span skip MergeByte, so XOR mode has
        eor     (HBASE),y               ; to be honoured here as well
        and     #$7F
@midset:
        sta     (HBASE),y
        inc     HCOLN
        bne     @mid

@right: lda     HB2                     ; right partial byte
        sta     HCOLN
        lda     HRM
        sta     HMASK
        jsr     MergeByte
        bit     MAINSEL
        rts

; ---------------------------------------------------------------------------
; HgrVLine -- vertical span at HX from HY to HY2 inclusive.
; x is fixed, so the byte column, its bank and the bit mask are found once.
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
        sta     HCOLN
        jsr     Mod7
        sta     HMASK
@loop:  jsr     HgrRow
        jsr     MergeByte
        lda     HY
        cmp     HY2
        bcs     @done
        inc     HY
        bne     @loop
@done:  bit     MAINSEL
        rts

; ---------------------------------------------------------------------------
; HgrFillRect -- solid rectangle HX..HX2 by HY..HY2.  Filling row by row from
; Forth costs a few hundred cycles of threading per row; doing the whole
; rectangle here keeps a full repaint fast enough to drag a window against.
; HgrHLine consumes HX, so the span is restored on every row.
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
@done:  bit     MAINSEL
        rts

; ---------------------------------------------------------------------------
; Tables
; ---------------------------------------------------------------------------

; Row -> screen address, the same in both banks.  Written as integer
; arithmetic rather than shifts so the decomposition stays readable:
; row = 8a+b, a = 8c+d, giving base + $400*b + $80*d + $28*c.  (The loop
; variable cannot be called `y` -- ca65 reserves that as a register name.)
HGRROWL:
        .repeat 192, row
        .byte   <(HGRPAGE + (row - (row/8)*8)*$400 + ((row/8) - (row/64)*8)*$80 + (row/64)*$28)
        .endrep
HGRROWH:
        .repeat 192, row
        .byte   >(HGRPAGE + (row - (row/8)*8)*$400 + ((row/8) - (row/64)*8)*$80 + (row/64)*$28)
        .endrep

; 560 pixels is exactly 80 bytes of 7, so each table is one 7-entry pattern
; repeated 80 times: the byte column, the bit within it, and the shift count.
DIV7TBL:
        .repeat 80, col
        .byte   col, col, col, col, col, col, col
        .endrep
MOD7TBL:
        .repeat 80
        .byte   $01, $02, $04, $08, $10, $20, $40
        .endrep
MOD7KTBL:
        .repeat 80
        .byte   0, 1, 2, 3, 4, 5, 6
        .endrep

; Monochrome, so these are dither patterns rather than colours: one byte for
; even byte columns and one for odd, which is what lets a checkerboard come
; out even though a byte spans an odd number of pixels.
HCOLTBL:
        .byte   $00,$00         ; 0 black
        .byte   $11,$44         ; 1 dark grey
        .byte   $2A,$55         ; 2 50% grey
        .byte   $7F,$7F         ; 3 white
        .byte   $00,$00         ; 4 black
        .byte   $44,$11         ; 5 dark grey, opposite phase
        .byte   $55,$2A         ; 6 50% grey, opposite phase
        .byte   $7F,$7F         ; 7 white

; Span endpoints held across the rows of a rectangle fill.  Kept here so that
; hires.inc stands on its own for test/hirestest.s.
        .segment "DATA"
HFX1:   .word   0
HFX2:   .word   0
        .segment "CODE"
