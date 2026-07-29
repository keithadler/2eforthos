; ---------------------------------------------------------------------------
; sound.inc -- the speaker, and the two ways this machine can tell the time
;
; The speaker is one soft switch: reading $C030 moves the cone one way, and
; reading it again moves it back.  A tone is that pair of reads repeated at
; the pitch you want, which means the CPU has to sit in a delay loop for the
; whole note -- there is no timer to hand it off to.
;
; Nor is there a clock.  What there is is the video counter: $C019 changes
; state once per frame, so waiting for it to change is a sixtieth of a second
; measured by the same crystal that drives everything else.  MS is a counted
; loop instead, and is only as accurate as the 1.023 MHz it assumes.
; ---------------------------------------------------------------------------

SPKR    = $C030                 ; read to toggle
RDVBL   = $C019                 ; bit 7 flips once a frame

        prim    "CLICK", W_CLICK, 0     ; --
        lda     SPKR
        NEXT

; TONE -- period cycles --
; The period is a delay count, not a frequency: bigger is lower.  About 90 is
; middle A, and the note lasts cycles/frequency seconds.
        prim    "TONE", W_TONE, 0
        lda     0,x
        sta     UTMP                    ; how many half-cycles
        lda     1,x
        sta     UTMP+1
        lda     2,x
        sta     UTMP2                   ; the delay between them
        txa
        clc
        adc     #4
        tax
@l:     lda     UTMP
        ora     UTMP+1
        beq     @done
        lda     SPKR
        ldy     UTMP2
        beq     @nodelay
@d:     dey
        bne     @d
@nodelay:
        lda     UTMP
        bne     :+
        dec     UTMP+1
:       dec     UTMP
        jmp     @l
@done:  NEXT

; MS -- n --
; 1023 cycles to the millisecond, and the inner loop is five of them.
        prim    "MS", W_MS, 0
        lda     0,x
        sta     UTMP
        lda     1,x
        sta     UTMP+1
        inx
        inx
@l:     lda     UTMP
        ora     UTMP+1
        beq     @done
        ldy     #204
@i:     dey
        bne     @i
        lda     UTMP
        bne     :+
        dec     UTMP+1
:       dec     UTMP
        jmp     @l
@done:  NEXT

; VBL -- wait for the video counter to change state.
; Which way round bit 7 runs is not worth depending on: waiting for it to
; differ from whatever it is now gives one frame either way.
        prim    "VBL", W_VBL, 0
        lda     RDVBL
        and     #$80
        sta     UTMP
@w:     lda     RDVBL
        and     #$80
        cmp     UTMP
        beq     @w
        NEXT
