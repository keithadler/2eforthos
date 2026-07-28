; ---------------------------------------------------------------------------
; input.inc -- the keyboard and game port, as Forth words
;
; What is left of the old pointer module.  The arrow, and the code that moved
; it from the game port, went with the windowing environment; reading the
; keyboard and the stick is worth keeping, because a program written at the
; console still wants them.
; ---------------------------------------------------------------------------

KBD     = $C000                 ; bit 7 set when a key is waiting
KBDSTRB = $C010                 ; read to clear the strobe
BUTN0   = $C061                 ; bit 7 set while button 0 is down
PREAD   = $FB1E                 ; X = paddle number -> Y = 0..255

; PREAD returns the moment its capacitor has discharged, so a small reading
; returns early and leaves the game port's shared timer still charged.  The
; next channel read then comes back skewed by the first.  Waiting out the
; worst case afterwards costs a few milliseconds and makes the channels
; independent of each other.
PdlSettle:
        lda     #3
        sta     PSETTLE
@outer: ldy     #$00
@inner: dey
        bne     @inner
        dec     PSETTLE
        bne     @outer
        rts

; ---------------------------------------------------------------------------
; Forth words
; ---------------------------------------------------------------------------
        prim    "KEY?", W_KEYQ, 0       ; -- flag, without consuming it
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

        prim    "KEYC", W_KEYC, 0       ; -- c, read and consume the waiting key
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

        prim    "BTN", W_BTN, 0         ; -- flag, game port button 0
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
        pha
        jsr     PdlSettle
        pla
        sta     0,x
        lda     #0
        sta     1,x
        NEXT

; ---------------------------------------------------------------------------
        .segment "DATA"
PSETTLE: .byte  0
        .segment "CODE"
