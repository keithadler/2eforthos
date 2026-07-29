; ---------------------------------------------------------------------------
; fast.inc -- the words that were one-liners in Forth
;
; Each of these was a colon definition of one or two tokens.  Entering a
; definition costs a JSR DOCOL, a NEXT for every token in it and an EXIT --
; sixty or eighty cycles wrapped around, in some cases, a single instruction.
; That is affordable once; it is not affordable in MIN, which was
; `2DUP > IF SWAP THEN DROP` and therefore three colon calls deep before it
; compared anything -- and MIN, ABS and > are all on the path of every signed
; division in the system.
;
; They are also, mostly, smaller this way: a header plus JSR DOCOL plus a
; thread plus EXIT is rarely less than the machine code it stands for.
; ---------------------------------------------------------------------------

        prim    "2DUP", W_2DUP, 0       ; a b -- a b a b
        dex
        dex
        dex
        dex
        lda     4,x
        sta     0,x
        lda     5,x
        sta     1,x
        lda     6,x
        sta     2,x
        lda     7,x
        sta     3,x
        NEXT

        prim    "2DROP", W_2DROP, 0     ; a b --
        inx
        inx
        inx
        inx
        NEXT

        prim    "-ROT", W_NROT, 0       ; a b c -- c a b
        lda     0,x
        pha
        lda     1,x
        pha
        lda     2,x
        sta     0,x
        lda     3,x
        sta     1,x
        lda     4,x
        sta     2,x
        lda     5,x
        sta     3,x
        pla
        sta     5,x
        pla
        sta     4,x
        NEXT

        prim    "TUCK", W_TUCK, 0       ; a b -- b a b
        dex
        dex
        lda     2,x
        sta     0,x
        lda     3,x
        sta     1,x
        lda     4,x
        sta     2,x
        lda     5,x
        sta     3,x
        lda     0,x
        sta     4,x
        lda     1,x
        sta     5,x
        NEXT

; --- comparison ------------------------------------------------------------
; The same shape as < and U<, with the operands the other way round.
        prim    ">", W_GT, 0            ; signed
        sec
        lda     0,x
        sbc     2,x
        lda     1,x
        sbc     3,x
        bvc     @nov
        eor     #$80                    ; overflow flips the sense of the sign
@nov:   bmi     @true
        lda     #0
        beq     @st
@true:  lda     #$FF
@st:    inx
        inx
        sta     0,x
        sta     1,x
        NEXT

        prim    "U>", W_UGT, 0          ; unsigned
        lda     0,x
        cmp     2,x
        lda     1,x
        sbc     3,x
        bcc     @true
        lda     #0
        beq     @st
@true:  lda     #$FF
@st:    inx
        inx
        sta     0,x
        sta     1,x
        NEXT

        prim    "<>", W_NE, 0
        lda     0,x
        cmp     2,x
        bne     @true
        lda     1,x
        cmp     3,x
        bne     @true
        lda     #0
        beq     @st
@true:  lda     #$FF
@st:    inx
        inx
        sta     0,x
        sta     1,x
        NEXT

        prim    "0<>", W_ZNE, 0
        lda     0,x
        ora     1,x
        beq     @false
        lda     #$FF
        bne     @st
@false: lda     #0
@st:    sta     0,x
        sta     1,x
        NEXT

        prim    "0>", W_ZGT, 0          ; positive and not zero
        lda     1,x
        bmi     @false
        ora     0,x
        beq     @false
        lda     #$FF
        bne     @st
@false: lda     #0
@st:    sta     0,x
        sta     1,x
        NEXT

; --- arithmetic ------------------------------------------------------------
        prim    "ABS", W_ABS, 0
        lda     1,x
        bpl     @done
        sec
        lda     #0
        sbc     0,x
        sta     0,x
        lda     #0
        sbc     1,x
        sta     1,x
@done:  NEXT

; MIN and MAX drop whichever they do not want rather than swapping and
; dropping: the compare is the same either way and the shuffling is not.
        prim    "MIN", W_MIN, 0
        sec
        lda     2,x
        sbc     0,x
        lda     3,x
        sbc     1,x
        bvc     @nov
        eor     #$80
@nov:   bmi     @keep                   ; the deeper one is smaller
        lda     0,x                     ; the top one is: move it down
        sta     2,x
        lda     1,x
        sta     3,x
@keep:  inx
        inx
        NEXT

        prim    "MAX", W_MAX, 0
        sec
        lda     2,x
        sbc     0,x
        lda     3,x
        sbc     1,x
        bvc     @nov
        eor     #$80
@nov:   bpl     @keep                   ; the deeper one is bigger
        lda     0,x
        sta     2,x
        lda     1,x
        sta     3,x
@keep:  inx
        inx
        NEXT

; --- how much room is left -------------------------------------------------
; There was no honest way to ask.  The ceiling depends on which of the two
; regions the dictionary pointer is in: the system's own words are compiled
; into the language card and the user's into main memory.
        prim    "UNUSED", W_UNUSED, 0   ; -- u
        dex
        dex
        lda     DPV+1
        cmp     #$C0
        bcs     @card
        sec
        lda     #$00
        sbc     DPV
        sta     0,x
        lda     #$C0
        sbc     DPV+1
        sta     1,x
        NEXT
@card:  sec
        lda     #<LCTOP
        sbc     DPV
        sta     0,x
        lda     #>LCTOP
        sbc     DPV+1
        sta     1,x
        NEXT

; --- the stacks themselves -------------------------------------------------
; CATCH and THROW are written in Forth on top of these four.  The data stack
; is in zero page and indexed by X, so its pointer fits in a byte; the return
; stack is the 6502's own and lives on page one.
        prim    "SP@", W_SPFETCH, 0
        txa
        dex
        dex
        sta     0,x
        lda     #0
        sta     1,x
        NEXT

        prim    "SP!", W_SPSTORE, 0
        lda     0,x
        tax
        NEXT

        prim    "RP@", W_RPFETCH, 0
        stx     XSAV
        tsx
        txa
        ldx     XSAV
        dex
        dex
        sta     0,x
        lda     #1
        sta     1,x
        NEXT

        prim    "RP!", W_RPSTORE, 0
        lda     0,x
        inx
        inx
        stx     XSAV
        tax
        txs
        ldx     XSAV
        NEXT
