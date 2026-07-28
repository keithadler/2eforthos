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
; exactly two screen bytes -- no third-byte case to handle.  Those two bytes
; are adjacent columns and therefore always in *different* banks, so each is
; written through SelectBank.
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
        lda     PSH                     ; low 7 bits -> first byte column
        and     #$7F
        beq     @second
        sta     PXTMP
        lda     PCOL
        jsr     SelectBank
        ldy     HBYTE
        lda     PXTMP
        eor     (HBASE),y
        sta     (HBASE),y
@second:
        lda     PSH                     ; bits 7..13 -> the next column
        asl     a                       ; bit 7 of the low byte into carry
        lda     PSH+1
        rol     a
        and     #$7F
        beq     @next
        sta     PXTMP
        lda     PCOL
        clc
        adc     #1
        cmp     #80
        bcs     @next                   ; ran off the right edge
        jsr     SelectBank
        ldy     HBYTE
        lda     PXTMP
        eor     (HBASE),y
        sta     (HBASE),y
@next:  inc     PROW
        lda     PROW
        cmp     #PTRROWS
        bne     @row
        bit     MAINSEL                 ; never leave aux selected
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

; Keep the arrow on screen: x 0..551 leaves room for its width, y 0..183 for
; its height.  Double hi-res here is full screen, so all 192 rows are ours.
PtrClamp:
        lda     PX+1
        bmi     @zerox
        beq     @xok
        cmp     #2
        bcc     @xok                    ; high byte 0 or 1 is always in range
        bne     @maxx
        lda     PX
        cmp     #<552                   ; 551 = $0227
        bcc     @xok
@maxx:  lda     #<551
        sta     PX
        lda     #>551
        sta     PX+1
        jmp     @xok
@zerox: lda     #0
        sta     PX
        sta     PX+1
@xok:   lda     PY
        cmp     #184
        bcc     @yok
        lda     #183
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

; MREAD -- move the pointer to wherever the stick is pointing.
;
; One paddle per call, alternating.  The 558 timer in the game port shares a
; discharge between channels, so reading paddle 1 immediately after paddle 0
; returns a value skewed by the first -- worst when the second reading is the
; smaller, which is why the pointer only misbehaved low on the screen.  The
; y coordinate jittered between the true value and a corrupted one, and an
; arrow drawn and erased at two places faster than the display settles looks
; exactly like a second cursor.
;
; Alternating also halves the time a pass spends in PREAD, which the event
; loop notices: PREAD is a timing loop that can take three milliseconds.
;
; The paddle range 0..255 maps onto the 552x184 pointer area: x by 17/8,
; y by 3/4.
        prim    "MREAD", W_MREAD, 0
        lda     MAXIS
        eor     #$01
        sta     MAXIS
        beq     @yaxis

        stx     XSAV                    ; x from paddle 0
        ldx     #0
        jsr     PREAD
        ldx     XSAV
        sty     PTMP
        lda     PTMP
        cmp     PLASTX
        beq     @same
        sta     PLASTX
        jsr     PtrHide
        lda     PTMP                    ; x = 2*p + p/8
        lsr     a
        lsr     a
        lsr     a
        sta     PXTMP
        lda     PTMP
        asl     a
        sta     PX
        lda     #0
        rol     a
        sta     PX+1
        clc
        lda     PX
        adc     PXTMP
        sta     PX
        lda     PX+1
        adc     #0
        sta     PX+1
        jmp     @done

@yaxis: stx     XSAV                    ; y from paddle 1
        ldx     #1
        jsr     PREAD
        ldx     XSAV
        sty     PTMP+1
        lda     PTMP+1
        cmp     PLASTY
        beq     @same
        sta     PLASTY
        jsr     PtrHide
        lda     PTMP+1                  ; y = p/2 + p/4
        lsr     a
        sta     PY
        lda     PTMP+1
        lsr     a
        lsr     a
        clc
        adc     PY
        sta     PY

@done:  jsr     PtrClamp
        jsr     PtrShow
@same:  NEXT
