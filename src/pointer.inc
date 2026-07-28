; ---------------------------------------------------------------------------
; pointer.inc -- the mouse pointer, and the devices that move it
;
; The pointer is drawn by XORing an arrow into the screen and erased by XORing
; it again in the same place.  XOR is self-inverse, so there is no backing
; store to save and restore, and the pointer stays legible over both the dark
; window interiors and the white title bars because it inverts whatever it
; covers.
;
; A screen byte holds 7 pixels in bits 0-6, bit 0 leftmost.  An 8-pixel-wide
; shape shifted by 0..6 occupies at most 14 bits, so it always lands in
; exactly two screen bytes -- no third-byte case to handle.
;
; Input: the Apple ][+ has no mouse.  Its pointing device is the analog game
; port, read through the monitor's PREAD, and that is what MREAD uses.  The
; keyboard arrows (I/J/K/L) drive the same pointer, which is what the demo
; and the automated tests use.
; ---------------------------------------------------------------------------

KBD     = $C000                 ; bit 7 set when a key is waiting
KBDSTRB = $C010                 ; read to clear the strobe
BUTN0   = $C061                 ; bit 7 set while button 0 is down
PREAD   = $FB1E                 ; X = paddle number -> Y = 0..255

PTRROWS = 8

; Arrow, one byte per row, bit 0 = leftmost pixel.
PtrShape:
        .byte   %00000001
        .byte   %00000011
        .byte   %00000111
        .byte   %00001111
        .byte   %00011111
        .byte   %00111111
        .byte   %00000111
        .byte   %00000110

; ---------------------------------------------------------------------------
; PtrXor -- draw or erase, they are the same operation
; ---------------------------------------------------------------------------
PtrXor:
        lda     PX
        sta     HX
        lda     PX+1
        sta     HX+1
        jsr     Div7
        sta     PCOL                    ; byte column
        jsr     Mod7K
        sta     PSHIFT                  ; bits into that byte
        lda     #0
        sta     PROW
@row:   lda     PY
        clc
        adc     PROW
        cmp     #192
        bcs     @next                   ; past the bottom of the screen
        sta     HY
        jsr     HgrRow
        ldy     PROW
        lda     PtrShape,y
        sta     PSH
        lda     #0
        sta     PSH+1
        ldy     PSHIFT
        beq     @placed
@shift: asl     PSH
        rol     PSH+1
        dey
        bne     @shift
@placed:
        ldy     PCOL
        lda     PSH                     ; low 7 bits -> first screen byte
        and     #$7F
        beq     @second
        eor     (HBASE),y
        sta     (HBASE),y
@second:
        iny
        cpy     #40
        bcs     @next                   ; ran off the right edge
        lda     PSH                     ; bits 7..13 -> second screen byte
        asl     a                       ; bit 7 of the low byte into carry
        lda     PSH+1
        rol     a
        and     #$7F
        beq     @next
        eor     (HBASE),y
        sta     (HBASE),y
@next:  inc     PROW
        lda     PROW
        cmp     #PTRROWS
        bne     @row
        rts

PtrShow:
        lda     PVIS
        bne     @done
        jsr     PtrXor
        lda     #1
        sta     PVIS
@done:  rts

PtrHide:
        lda     PVIS
        beq     @done
        jsr     PtrXor
        lda     #0
        sta     PVIS
@done:  rts

; Keep the arrow inside the graphics area: x 0..271 leaves room for its width,
; y 0..151 keeps it clear of the four text lines that start at row 160.
PtrClamp:
        lda     PX+1
        bmi     @zerox
        beq     @xok
        cmp     #1
        bne     @maxx
        lda     PX
        cmp     #<272                   ; 271 = $010F
        bcc     @xok
@maxx:  lda     #<271
        sta     PX
        lda     #>271
        sta     PX+1
        jmp     @xok
@zerox: lda     #0
        sta     PX
        sta     PX+1
@xok:   lda     PY
        cmp     #152
        bcc     @yok
        lda     #151
        sta     PY
@yok:   rts

; ---------------------------------------------------------------------------
; Forth words
; ---------------------------------------------------------------------------
        prim    "PTRSHOW", W_PTRSHOW, 0
        jsr     PtrShow
        NEXT

        prim    "PTRHIDE", W_PTRHIDE, 0
        jsr     PtrHide
        NEXT

        prim    "PTRAT", W_PTRAT, 0     ; x y --
        jsr     PtrHide
        lda     0,x
        sta     PY
        lda     2,x
        sta     PX
        lda     3,x
        sta     PX+1
        inx
        inx
        inx
        inx
        jsr     PtrClamp
        jsr     PtrShow
        NEXT

        prim    "PTRX", W_PTRX, 0
        dex
        dex
        lda     PX
        sta     0,x
        lda     PX+1
        sta     1,x
        NEXT

        prim    "PTRY", W_PTRY, 0
        dex
        dex
        lda     PY
        sta     0,x
        lda     #0
        sta     1,x
        NEXT

; --- input -----------------------------------------------------------------
        prim    "KEY?", W_KEYQ, 0
        dex
        dex
        lda     #0
        sta     0,x
        sta     1,x
        lda     KBD
        bpl     :+
        lda     #$FF
        sta     0,x
        sta     1,x
:       NEXT

        prim    "KEYC", W_KEYC, 0       ; read and consume the waiting key
        lda     KBD
        and     #$7F
        pha
        lda     KBDSTRB
        dex
        dex
        pla
        sta     0,x
        lda     #0
        sta     1,x
        NEXT

        prim    "BTN", W_BTN, 0         ; game port button 0
        dex
        dex
        lda     #0
        sta     0,x
        sta     1,x
        lda     BUTN0
        bpl     :+
        lda     #$FF
        sta     0,x
        sta     1,x
:       NEXT

        prim    "PADDLE", W_PADDLE, 0   ; n -- 0..255
        lda     0,x
        stx     XSAV
        tax
        jsr     PREAD                   ; timing loop; returns the count in Y
        tya
        ldx     XSAV
        sta     0,x
        lda     #0
        sta     1,x
        NEXT

; MREAD -- move the pointer to wherever the joystick is pointing.  The paddle
; range 0..255 is mapped onto the 272x152 pointer area: x scales by 17/16,
; y by 19/32.
        prim    "MREAD", W_MREAD, 0
        jsr     PtrHide
        stx     XSAV
        ldx     #0
        jsr     PREAD
        sty     PTMP                    ; paddle 0 -> x
        ldx     #1
        jsr     PREAD
        sty     PTMP+1                  ; paddle 1 -> y
        ldx     XSAV
        lda     PTMP                    ; x = p0 + p0/16
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        clc
        adc     PTMP
        sta     PX
        lda     #0
        adc     #0
        sta     PX+1
        lda     PTMP+1                  ; y = p1/2 + p1/16 + p1/32, i.e. 19/32,
        lsr     a                       ; which takes 0..255 to 0..149
        sta     PY
        lda     PTMP+1
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        clc
        adc     PY
        sta     PY
        lda     PTMP+1
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        clc
        adc     PY
        sta     PY
        jsr     PtrClamp
        jsr     PtrShow
        NEXT
