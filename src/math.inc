; ---------------------------------------------------------------------------
; math.inc -- mixed and double precision, shifts, and bulk memory
;
; These are the primitives that cannot be written in Forth without them:
; a 16x16 multiply producing 32 bits, and the 32/16 divide that undoes it.
; Everything signed -- M*, */MOD, floored / and MOD -- is built on this pair
; in system.fth, because sign fixing is cheap and unsigned arithmetic is not.
; ---------------------------------------------------------------------------

; UM* -- u1 u2 -- ud   (32-bit product, high cell on top)
;
; Shift and add: the multiplier is shifted out a bit at a time and the
; multiplicand added into the top half of a 32-bit accumulator, which is then
; rotated down.  The carry the addition leaves is exactly the bit the rotate
; needs, which is why the add and the shift are not separated.
        prim    "UM*", W_UMSTAR, 0
        lda     0,x
        sta     TMP1                    ; multiplier
        lda     1,x
        sta     TMP1+1
        lda     2,x
        sta     TMP2                    ; multiplicand
        lda     3,x
        sta     TMP2+1
        lda     #0
        sta     UTMP                    ; product, 32 bits in UTMP..UTMP2+1
        sta     UTMP+1
        sta     UTMP2
        sta     UTMP2+1
        ldy     #16
@loop:  lsr     TMP1+1
        ror     TMP1
        bcc     @noadd
        clc
        lda     UTMP2
        adc     TMP2
        sta     UTMP2
        lda     UTMP2+1
        adc     TMP2+1
        sta     UTMP2+1
@noadd: ror     UTMP2+1
        ror     UTMP2
        ror     UTMP+1
        ror     UTMP
        dey
        bne     @loop
        lda     UTMP                    ; low cell underneath
        sta     2,x
        lda     UTMP+1
        sta     3,x
        lda     UTMP2                   ; high cell on top
        sta     0,x
        lda     UTMP2+1
        sta     1,x
        NEXT

; UM/MOD -- ud u -- rem quot
;
; Restoring division, one bit at a time.  The dividend is shifted left into
; the remainder and the divisor subtracted when it fits; the bit shifted out
; of the remainder's top means the subtraction must happen whatever the
; comparison says, which is the case a 16-bit compare cannot see.
        prim    "UM/MOD", W_UMSLASHMOD, 0
        lda     0,x
        sta     TMP1                    ; divisor
        lda     1,x
        sta     TMP1+1
        lda     4,x
        sta     UTMP                    ; dividend, low cell
        lda     5,x
        sta     UTMP+1
        lda     2,x
        sta     UTMP2                   ; ...and high, which becomes the
        lda     3,x                     ; running remainder
        sta     UTMP2+1
        ldy     #16
@loop:  asl     UTMP
        rol     UTMP+1
        rol     UTMP2
        rol     UTMP2+1
        bcs     @must                   ; overflowed 16 bits: subtract anyway
        sec
        lda     UTMP2
        sbc     TMP1
        sta     TMP2
        lda     UTMP2+1
        sbc     TMP1+1
        bcc     @next                   ; did not fit
        jmp     @store
@must:  sec
        lda     UTMP2
        sbc     TMP1
        sta     TMP2
        lda     UTMP2+1
        sbc     TMP1+1
@store: sta     UTMP2+1
        lda     TMP2
        sta     UTMP2
        inc     UTMP                    ; quotient bit
@next:  dey
        bne     @loop
        inx                             ; three cells in, two out
        inx
        lda     UTMP2                   ; remainder underneath
        sta     2,x
        lda     UTMP2+1
        sta     3,x
        lda     UTMP                    ; quotient on top
        sta     0,x
        lda     UTMP+1
        sta     1,x
        NEXT

; --- shifts ----------------------------------------------------------------
; A count of 16 or more gives zero rather than a rotation, which is what the
; standard asks for and what the hardware does not do.
        prim    "LSHIFT", W_LSHIFT, 0   ; x u -- x<<u
        lda     0,x
        sta     UTMP
        lda     1,x
        sta     UTMP+1
        inx
        inx
        lda     UTMP+1
        bne     @zero
        lda     UTMP
        beq     @done
        cmp     #16
        bcs     @zero
        tay
@l:     asl     0,x
        rol     1,x
        dey
        bne     @l
@done:  NEXT
@zero:  lda     #0
        sta     0,x
        sta     1,x
        NEXT

        prim    "RSHIFT", W_RSHIFT, 0   ; x u -- x>>u  (logical)
        lda     0,x
        sta     UTMP
        lda     1,x
        sta     UTMP+1
        inx
        inx
        lda     UTMP+1
        bne     @zero
        lda     UTMP
        beq     @done
        cmp     #16
        bcs     @zero
        tay
@l:     lsr     1,x
        ror     0,x
        dey
        bne     @l
@done:  NEXT
@zero:  lda     #0
        sta     0,x
        sta     1,x
        NEXT

; --- double-cell helpers ---------------------------------------------------
        prim    "DNEGATE", W_DNEGATE, 0 ; d -- -d
        sec
        lda     #0
        sbc     2,x
        sta     2,x
        lda     #0
        sbc     3,x
        sta     3,x
        lda     #0
        sbc     0,x
        sta     0,x
        lda     #0
        sbc     1,x
        sta     1,x
        NEXT

        prim    "D+", W_DPLUS, 0        ; d1 d2 -- d3
        clc
        lda     6,x                     ; low cells
        adc     2,x
        sta     6,x
        lda     7,x
        adc     3,x
        sta     7,x
        lda     4,x                     ; high cells, with the carry
        adc     0,x
        sta     4,x
        lda     5,x
        adc     1,x
        sta     5,x
        inx
        inx
        inx
        inx
        NEXT

; --- stack reach -----------------------------------------------------------
; The data stack is in zero page and indexed by X, so a cell's address is a
; single byte -- which means it can go in Y and be reached with absolute
; indexed addressing into page zero.  That is the only way to get at a cell
; whose depth is not known until run time.
        prim    "PICK", W_PICK, 0       ; xu..x0 u -- xu..x0 xu
        lda     0,x
        asl     a                       ; two bytes per cell
        clc
        adc     #2                      ; and past the count cell itself
        sta     UTMP
        txa
        clc
        adc     UTMP
        tay
        lda     $0000,y
        sta     UTMP
        lda     $0001,y
        sta     UTMP+1
        lda     UTMP
        sta     0,x
        lda     UTMP+1
        sta     1,x
        NEXT

; ROLL -- lift the u-th cell out and put it on top, closing the gap.  The
; stack grows downward, so "closing the gap" copies each cell to the address
; two higher than itself, working from the picked cell back to the top.
        prim    "ROLL", W_ROLL, 0       ; xu..x0 u -- xu-1..x0 xu
        lda     0,x
        sta     UTMP
        inx
        inx
        lda     UTMP
        bne     @go
        NEXT                            ; 0 ROLL is a no-op
@go:    asl     a
        sta     UTMP2
        txa
        clc
        adc     UTMP2
        tay                             ; Y = address of the cell to lift
        lda     $0000,y
        sta     TMP1
        lda     $0001,y
        sta     TMP1+1
@l:     dey
        dey
        lda     $0000,y
        sta     $0002,y
        lda     $0001,y
        sta     $0003,y
        dec     UTMP
        bne     @l
        lda     TMP1
        sta     0,x
        lda     TMP1+1
        sta     1,x
        NEXT

; --- bulk memory -----------------------------------------------------------
        prim    "FILL", W_FILL, 0       ; addr u char --
        lda     0,x
        sta     UTMP2                   ; the byte
        lda     2,x
        sta     UTMP                    ; the count
        lda     3,x
        sta     UTMP+1
        lda     4,x
        sta     TMP1                    ; the address
        lda     5,x
        sta     TMP1+1
        txa
        clc
        adc     #6
        tax
        ldy     #0
@l:     lda     UTMP
        ora     UTMP+1
        beq     @done
        lda     UTMP2
        sta     (TMP1),y
        inc     TMP1
        bne     :+
        inc     TMP1+1
:       lda     UTMP
        bne     :+
        dec     UTMP+1
:       dec     UTMP
        jmp     @l
@done:  NEXT

; MOVE -- src dst u --
; Overlapping ranges have to be copied in the direction that reads a byte
; before it is written over: upward when the destination is below the source,
; downward when it is above.
        prim    "MOVE", W_MOVE, 0
        lda     0,x
        sta     UTMP                    ; count
        lda     1,x
        sta     UTMP+1
        lda     2,x
        sta     TMP2                    ; destination
        lda     3,x
        sta     TMP2+1
        lda     4,x
        sta     TMP1                    ; source
        lda     5,x
        sta     TMP1+1
        txa
        clc
        adc     #6
        tax
        lda     UTMP
        ora     UTMP+1
        beq     @done
        lda     TMP2                    ; dst < src?  copy upward
        cmp     TMP1
        lda     TMP2+1
        sbc     TMP1+1
        bcc     @up
        ; downward: start both pointers at the far end
        clc
        lda     TMP1
        adc     UTMP
        sta     TMP1
        lda     TMP1+1
        adc     UTMP+1
        sta     TMP1+1
        clc
        lda     TMP2
        adc     UTMP
        sta     TMP2
        lda     TMP2+1
        adc     UTMP+1
        sta     TMP2+1
@dl:    lda     TMP1                    ; pre-decrement both
        bne     :+
        dec     TMP1+1
:       dec     TMP1
        lda     TMP2
        bne     :+
        dec     TMP2+1
:       dec     TMP2
        ldy     #0
        lda     (TMP1),y
        sta     (TMP2),y
        lda     UTMP
        bne     :+
        dec     UTMP+1
:       dec     UTMP
        lda     UTMP
        ora     UTMP+1
        bne     @dl
@done:  NEXT
@up:    ldy     #0
@ul:    lda     (TMP1),y
        sta     (TMP2),y
        inc     TMP1
        bne     :+
        inc     TMP1+1
:       inc     TMP2
        bne     :+
        inc     TMP2+1
:       lda     UTMP
        bne     :+
        dec     UTMP+1
:       dec     UTMP
        lda     UTMP
        ora     UTMP+1
        bne     @ul
        NEXT
