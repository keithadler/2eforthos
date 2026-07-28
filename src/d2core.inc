; ---------------------------------------------------------------------------
; d2core.inc -- the Disk II driver: motor, head, read, write, 6-and-2
;
; Shared by the kernel and by the boot loader, which is why it stops short of
; defining any Forth words or fixing where its buffers live.  The includer
; must define D2NIBM and D2NIBA first, both page aligned -- LDA abs,Y costs
; five cycles instead of four when the index carries into the next page, and
; the write loop has a 32-cycle budget with nothing to spare.  The boot loader
; puts them above itself; the kernel puts them below the graphics screen.
;
; DOS 3.3's own boot is about 24 of the 30 seconds this system takes to come
; up, so the way out is not to boot DOS at all.  That means doing what RWTS
; does: stepping the head, finding a sector by its address field, and undoing
; the 6-and-2 encoding the drive stores data in.
;
; The controller is all soft switches at $C080 + slot*16 -- $C0E0 for slot 6.
; Reading one is what does the work; the value read is mostly irrelevant
; except at $C0EC, which hands over the byte currently under the head once
; its high bit is set.
;
; Data on disk is 6-and-2 encoded: a sector's 256 bytes become 342 disk bytes
; carrying six bits each, split into 86 "auxiliary" bytes holding the low two
; bits of three data bytes apiece, then 256 holding the high six bits.  Each
; is exclusive-ored with the one before, so a single misread corrupts the
; checksum at the end and the sector is rejected rather than silently wrong.
;
; The nibbles are read into a buffer first and decoded afterwards.  Decoding
; in the read loop is what real RWTS does, and it is why that code is written
; to a cycle budget -- a new byte arrives every 32 cycles and there is no
; waiting for it.  Reading first costs one buffer and removes the timing
; constraint entirely.
; ---------------------------------------------------------------------------

D2BASE  = $C0E0                 ; slot 6
D2PH0OFF = D2BASE+0
D2PH0ON  = D2BASE+1
D2MOTOFF = D2BASE+8
D2MOTON  = D2BASE+9
D2DRV1   = D2BASE+10
D2Q6L    = D2BASE+12            ; read a disk byte here
D2Q6H    = D2BASE+13
D2Q7L    = D2BASE+14            ; read mode
D2Q7H    = D2BASE+15            ; write mode

; ---------------------------------------------------------------------------
; Motor control.  The drive needs about a second to come up to speed from
; cold; once running it is left running, because spinning it up per sector
; would cost far more than it saves.
; ---------------------------------------------------------------------------
; The drive spins down on its own when nothing has touched it for a while, so
; a caller returning after a pause finds it stopped.  Reading during spin-up
; returns noise, which is what the address field guards above are for; this
; just shortens the window by always giving it a moment.
D2MotorOn:
        lda     D2DRV1
        lda     D2MOTON
        lda     D2MOTRUN
        bne     @brief
        lda     #1
        sta     D2MOTRUN
        ldy     #200                    ; ~1s from cold
@wait:  jsr     D2Delay
        dey
        bne     @wait
        rts
@brief: ldy     #40                     ; ~200ms otherwise
@wait2: jsr     D2Delay
        dey
        bne     @wait2
        rts

D2MotorOff:
        lda     D2MOTOFF
        lda     #0
        sta     D2MOTRUN
        rts

; About 5ms.
D2Delay:
        ldx     #$00
@outer: nop
        nop
@inner: dex
        bne     @inner
        rts

; ---------------------------------------------------------------------------
; Head positioning.  A phase is energised, held long enough for the head to
; arrive, then released; stepping one track at a time is slower than RWTS's
; accelerating seek but is a great deal easier to be sure of.
; ---------------------------------------------------------------------------

; The head moves half a track per phase, so positions are counted in half
; tracks throughout: one whole track is two energisations, and stepping once
; per track would leave the head at half the distance asked for.
;
; Step outward further than the disk is wide; the head stops at track 0 and
; the remaining steps simply knock against it.
D2Recal:
        jsr     D2MotorOn
        lda     #80
        sta     D2CNT
        lda     #80
        sta     D2CURH
@out:   dec     D2CURH
        jsr     D2StepPhase
        dec     D2CNT
        bne     @out
        lda     #0
        sta     D2CURH
        rts

; Energise the phase for the half track D2CURH now names, then release it.
;
; The index is kept in memory, not in X: D2Delay counts down in X, so holding
; the phase there meant switching on the right magnet and switching off phase
; zero, leaving magnets latched and the head parked between tracks.  Reads at
; the position the head happened to start in worked, which is what made this
; look like a seek problem rather than a register problem.
D2StepPhase:
        lda     D2CURH
        and     #$03
        asl     a
        sta     D2PHIDX
        tax
        lda     D2PH0ON,x
        jsr     D2StepDelay
        ldx     D2PHIDX
        lda     D2PH0OFF,x
        jsr     D2StepDelay
        rts

; About 13ms per half track, comfortably longer than the head needs.
D2StepDelay:
        lda     #5
        sta     D2DLY
@l:     jsr     D2Delay
        dec     D2DLY
        bne     @l
        rts

; Seek to D2TRK.
D2Seek:
        lda     D2TRK
        asl     a
        sta     D2DSTH
@loop:  lda     D2CURH
        cmp     D2DSTH
        beq     @done
        bcc     @inward
        dec     D2CURH
        jmp     @step
@inward:
        inc     D2CURH
@step:  jsr     D2StepPhase
        jmp     @loop
@done:  rts

; ---------------------------------------------------------------------------
; Reading
; ---------------------------------------------------------------------------

; Wait for the next disk byte.
D2Read1:
        lda     D2Q6L
        bpl     D2Read1
        rts

; Two disk bytes in 4-and-4 form carry one value: odd bits in the first with
; ones between them, even bits in the second.
;
; The waits are inlined.  A new disk byte arrives every 32 cycles and there is
; no waiting for it, so a JSR/RTS pair per byte -- twelve cycles of the
; thirty-two -- is enough to miss one and land in the gap after the field.
; Buffering the nibbles removed the pressure to *decode* in time; it did not
; remove the deadline to *sample* in time.
D2Read44:
@w1:    lda     D2Q6L
        bpl     @w1
        sec
        rol     a
        sta     D2T44
@w2:    lda     D2Q6L
        bpl     @w2
        and     D2T44
        rts

; D2ReadSector -- D2TRK/D2SEC into the 256 bytes at D2PTR.
; Returns A = 0 on success, non-zero if it could not be read.
D2ReadSector:
        jsr     D2MotorOn
        lda     D2READY                 ; the head is wherever whatever ran
        bne     :+                      ; before us left it, so find track 0
        jsr     D2Recal                 ; once before trusting D2CURTRK
        lda     #1
        sta     D2READY
:       jsr     D2Seek
        lda     D2Q7L                   ; make sure we are in read mode
        lda     D2Q6L
        lda     #<32000                 ; a few revolutions' worth of bytes
        sta     D2BUDGET                ; before concluding the sector is not
        lda     #>32000                 ; there.  Counting *retries* rather
        sta     D2BUDGET+1              ; than bytes would give up in a
                                        ; fraction of a track, since most
                                        ; bytes are not a prologue.
@find:                                  ; address field prologue D5 AA 96
@f1:    lda     D2Q6L
        bpl     @f1
        cmp     #$D5
        bne     @spent
@f2:    lda     D2Q6L
        bpl     @f2
        cmp     #$AA
        bne     @spent
@f3:    lda     D2Q6L
        bpl     @f3
        cmp     #$96
        bne     @spent
        jsr     D2Read44                ; volume, ignored
        jsr     D2Read44
        sta     D2GOTTRK
        jsr     D2Read44
        cmp     #16                     ; a sector is 0..15 and a track 0..34.
        bcs     @spent                  ; Anything else means the drive is not
        pha                             ; yet at speed and we are reading
        lda     D2GOTTRK                ; noise -- believing it once sent the
        cmp     #35                     ; head off the end of the disk, because
        bcs     @nope                   ; @wrongtrack trusted the track number.
        pla
        cmp     D2SEC
        bne     @spent
        lda     D2GOTTRK
        cmp     D2TRK
        beq     @found
        jmp     @wrongtrack
@nope:  pla
        jmp     @spent

@spent: lda     D2BUDGET                ; 16-bit decrement and test
        bne     :+
        dec     D2BUDGET+1
:       dec     D2BUDGET
        lda     D2BUDGET
        ora     D2BUDGET+1
        bne     @find
        lda     #1                      ; not found
        rts

@found:
        ldy     #40                     ; the data field follows within a few
        sty     D2CNT                   ; bytes; D5 AA AD
@data:  dec     D2CNT
        beq     @spent
@d1:    lda     D2Q6L
        bpl     @d1
        cmp     #$D5
        bne     @data
@d2:    lda     D2Q6L
        bpl     @d2
        cmp     #$AA
        bne     @data
@d3:    lda     D2Q6L
        bpl     @d3
        cmp     #$AD
        bne     @data

        ; Straight into the buffers.  Each iteration is well inside the 32
        ; cycles between disk bytes, so nothing is missed.
        ldy     #0
@aux:   lda     D2Q6L
        bpl     @aux
        sta     D2NIBA,y
        iny
        cpy     #86
        bcc     @aux
        ldy     #0
@main:  lda     D2Q6L
        bpl     @main
        sta     D2NIBM,y
        iny
        bne     @main
@ck:    lda     D2Q6L
        bpl     @ck
        sta     D2NIBC
        jmp     D2Decode

@wrongtrack:
        lda     D2GOTTRK                ; the head is not where we thought;
        asl     a                       ; believe the disk and seek again
        sta     D2CURH
        jmp     D2ReadSector

; ---------------------------------------------------------------------------
; D2Decode -- undo the 6-and-2 encoding in the buffers into D2PTR.
; No timing pressure here: the sector has already been read.
; ---------------------------------------------------------------------------
D2Decode:
        jmp     D2DecGo
D2DecFail:                              ; kept up here so every check below
        lda     #2                      ; is within branch range of it
        rts
D2DecGo:
        lda     #0
        sta     D2CHK
        ldy     #0
@auxdec:
        ldx     D2NIBA,y
        lda     D2NIBDEC,x
        cmp     #$FF
        beq     D2DecFail
        eor     D2CHK
        sta     D2CHK
        sta     D2NIBA,y                ; decoded in place
        iny
        cpy     #86
        bcc     @auxdec

        ldy     #0
@maindec:
        ldx     D2NIBM,y
        lda     D2NIBDEC,x
        cmp     #$FF
        beq     D2DecFail
        eor     D2CHK
        sta     D2CHK
        sta     D2NIBM,y
        iny
        bne     @maindec

        ldx     D2NIBC                  ; the running exclusive-or must come
        lda     D2NIBDEC,x              ; out equal to the trailing byte
        cmp     #$FF
        beq     D2DecFail
        eor     D2CHK
        bne     D2DecFail

        ; Each auxiliary byte carries the low two bits of three data bytes,
        ; and carries each pair the other way round, so a four-entry table
        ; puts them back.  The three groups are unpicked separately because
        ; their destinations are 86 apart.
        lda     #0
        sta     D2IDX
@join1: ldy     D2IDX
        lda     D2NIBM,y
        asl     a
        asl     a
        sta     D2TMP
        lda     D2NIBA,y
        and     #$03
        tax
        lda     D2SWAP2,x
        ora     D2TMP
        sta     (D2PTR),y
        inc     D2IDX
        lda     D2IDX
        cmp     #86
        bcc     @join1

        lda     #0
        sta     D2IDX
@join2: ldy     D2IDX
        lda     D2NIBM+86,y
        asl     a
        asl     a
        sta     D2TMP
        lda     D2NIBA,y
        lsr     a
        lsr     a
        and     #$03
        tax
        lda     D2SWAP2,x
        ora     D2TMP
        pha
        lda     D2IDX
        clc
        adc     #86
        tay
        pla
        sta     (D2PTR),y
        inc     D2IDX
        lda     D2IDX
        cmp     #86
        bcc     @join2

        lda     #0
        sta     D2IDX
@join3: ldy     D2IDX
        lda     D2NIBM+172,y
        asl     a
        asl     a
        sta     D2TMP
        lda     D2NIBA,y
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        and     #$03
        tax
        lda     D2SWAP2,x
        ora     D2TMP
        pha
        lda     D2IDX
        clc
        adc     #172
        tay
        pla
        sta     (D2PTR),y
        inc     D2IDX
        lda     D2IDX
        cmp     #84                     ; 172+84 = 256; the last two auxiliary
        bcc     @join3                  ; slots have no third byte to fill
        lda     #0
        rts

; The two bits arrive reversed.
D2SWAP2:
        .byte   0, 2, 1, 3

; ---------------------------------------------------------------------------
; Writing
;
; The reverse of reading, with one asymmetry that matters: a byte must be
; handed to the latch every 32 cycles exactly, and unlike reading there is no
; way to buffer your way out of it -- the shift register will emit something
; whether or not you supplied it.  So the 256 bytes are encoded into the 343
; disk bytes first, with no clock running, and the write loops then do nothing
; but stream them, padded to 32 cycles apiece.
; ---------------------------------------------------------------------------

; D2Nibblize -- the 256 bytes at D2PTR into 6-bit values in D2NIBA/D2NIBM.
; Each auxiliary byte carries the low two bits of three data bytes, each pair
; reversed, which is the same packing the read side undoes.
D2Nibblize:
        ldy     #0
@main:  lda     (D2PTR),y               ; high six bits
        lsr     a
        lsr     a
        sta     D2NIBM,y
        iny
        bne     @main

        lda     #0
        sta     D2IDX
@aux:   ldy     D2IDX
        lda     (D2PTR),y
        and     #$03
        tax
        lda     D2SWAP2,x
        sta     D2TMP
        lda     D2IDX
        clc
        adc     #86
        tay
        lda     (D2PTR),y
        and     #$03
        tax
        lda     D2SWAP2,x
        asl     a
        asl     a
        ora     D2TMP
        sta     D2TMP
        lda     D2IDX                   ; the last two slots have no third
        cmp     #84                     ; byte: 172+84 is already 256
        bcs     @put
        clc
        adc     #172
        tay
        lda     (D2PTR),y
        and     #$03
        tax
        lda     D2SWAP2,x
        asl     a
        asl     a
        asl     a
        asl     a
        ora     D2TMP
        sta     D2TMP
@put:   ldy     D2IDX
        lda     D2TMP
        sta     D2NIBA,y
        inc     D2IDX
        lda     D2IDX
        cmp     #86
        bcc     @aux
        rts

; D2Encode -- 6-bit values to disk bytes, in place.  Each is exclusive-ored
; with the one before so a single bad byte fails the checksum at the end
; rather than passing as good data.
D2Encode:
        lda     #0
        sta     D2CHK
        ldy     #0
@e1:    lda     D2NIBA,y
        sta     D2TMP
        eor     D2CHK
        tax
        lda     D2NIBENC,x
        sta     D2NIBA,y
        lda     D2TMP
        sta     D2CHK
        iny
        cpy     #86
        bcc     @e1
        ldy     #0
@e2:    lda     D2NIBM,y
        sta     D2TMP
        eor     D2CHK
        tax
        lda     D2NIBENC,x
        sta     D2NIBM,y
        lda     D2TMP
        sta     D2CHK
        iny
        bne     @e2
        ldx     D2CHK
        lda     D2NIBENC,x
        sta     D2NIBC
        rts

; ---------------------------------------------------------------------------
; D2WriteSector -- D2TRK/D2SEC written from the 256 bytes at D2PTR.
; Returns A = 0 ok, 1 sector not found, 3 write protected.
;
; Cycle counts are in the margin.  The interval that matters is between one
; STA to the latch and the next: the shift register wants a byte every 32,
; and self-sync bytes are written at 40 so they carry the extra zero bits
; that let a reader find byte boundaries again.
; ---------------------------------------------------------------------------
D2WriteSector:
        jsr     D2Nibblize              ; no clock running yet
        jsr     D2Encode
        jsr     D2MotorOn
        lda     D2READY
        bne     :+
        jsr     D2Recal
        lda     #1
        sta     D2READY
:       jsr     D2Seek
        lda     D2Q7L                   ; read mode while we look
        lda     D2Q6L
        lda     #<32000
        sta     D2BUDGET
        lda     #>32000
        sta     D2BUDGET+1

@find:                                  ; the same search the read path uses
@f1:    lda     D2Q6L
        bpl     @f1
        cmp     #$D5
        bne     @spent
@f2:    lda     D2Q6L
        bpl     @f2
        cmp     #$AA
        bne     @spent
@f3:    lda     D2Q6L
        bpl     @f3
        cmp     #$96
        bne     @spent
        jsr     D2Read44                ; volume
        jsr     D2Read44
        sta     D2GOTTRK
        jsr     D2Read44
        cmp     #16
        bcs     @spent
        pha
        lda     D2GOTTRK
        cmp     #35
        bcs     @nope
        pla
        cmp     D2SEC
        bne     @spent
        lda     D2GOTTRK
        cmp     D2TRK
        beq     @found
        asl     a                       ; head is not where we thought
        sta     D2CURH
        jmp     D2WriteSector
@nope:  pla
@spent: lda     D2BUDGET
        bne     :+
        dec     D2BUDGET+1
:       dec     D2BUDGET
        lda     D2BUDGET
        ora     D2BUDGET+1
        bne     @find
        lda     #1
        rts

@found: jsr     D2Read44                ; the address checksum
        ldy     #3                      ; and its epilogue, DE AA EB
@epi:   lda     D2Q6L
        bpl     @epi
        dey
        bne     @epi

        lda     D2Q6H                   ; is the disk write protected?
        lda     D2Q7L
        bpl     :+
        jmp     @protected
:
        lda     #$FF                    ; into write mode, latching a sync byte
        sta     D2Q7H
        ora     D2Q6L

        ldy     #5                      ; five self-sync bytes, 40 cycles each
@sync:  lda     #$FF                    ; 2
        sta     D2Q6H                   ; 4
        ora     D2Q6L                   ; 4
        nop                             ; 2
        nop                             ; 2
        nop                             ; 2
        nop                             ; 2
        nop                             ; 2
        nop                             ; 2
        nop                             ; 2
        nop                             ; 2
        nop                             ; 2
        nop                             ; 2
        nop                             ; 2
        bit     $00                     ; 3
        dey                             ; 2
        bne     @sync                   ; 3   = 40

        lda     #$D5                    ; data field prologue
        sta     D2Q6H
        ora     D2Q6L
        .repeat 11
        nop
        .endrep
        lda     #$AA
        sta     D2Q6H
        ora     D2Q6L
        .repeat 11
        nop
        .endrep
        lda     #$AD
        sta     D2Q6H
        ora     D2Q6L
        .repeat 9
        nop
        .endrep
        ldy     #0                      ; 2

@waux:  lda     D2NIBA,y                ; 4
        sta     D2Q6H                   ; 4
        ora     D2Q6L                   ; 4
        iny                             ; 2
        cpy     #86                     ; 2
        nop                             ; 2
        nop                             ; 2
        nop                             ; 2
        nop                             ; 2
        nop                             ; 2
        bit     $00                     ; 3
        bcc     @waux                   ; 3   = 32

        ldy     #0                      ; 2
        nop                             ; 2
        nop                             ; 2
        ; BIT is the only 3-cycle filler to hand, and it clobbers Z -- so the
        ; increment goes after it, not before, or BNE tests BIT's result
        ; instead of the loop counter.
@wmain: lda     D2NIBM,y                ; 4
        sta     D2Q6H                   ; 4
        ora     D2Q6L                   ; 4
        nop                             ; 2
        nop                             ; 2
        nop                             ; 2
        nop                             ; 2
        nop                             ; 2
        nop                             ; 2
        bit     $00                     ; 3
        iny                             ; 2
        bne     @wmain                  ; 3   = 32

        lda     D2NIBC                  ; the trailing checksum
        sta     D2Q6H
        ora     D2Q6L
        .repeat 11
        nop
        .endrep
        lda     #$DE                    ; epilogue
        sta     D2Q6H
        ora     D2Q6L
        .repeat 11
        nop
        .endrep
        lda     #$AA
        sta     D2Q6H
        ora     D2Q6L
        .repeat 11
        nop
        .endrep
        lda     #$EB
        sta     D2Q6H
        ora     D2Q6L
        .repeat 11
        nop
        .endrep
        lda     #$FF
        sta     D2Q6H
        ora     D2Q6L

        lda     D2Q6L                   ; back to reading
        lda     D2Q7L
        lda     #0
        rts

@protected:
        lda     D2Q6L
        lda     D2Q7L
        lda     #3
        rts

; ---------------------------------------------------------------------------
; The decode table is the inverse of the 64 legal disk bytes, built once at
; cold start rather than stored: it is 256 bytes either way, and this way the
; only thing in the image is the 64-byte forward table.
; ---------------------------------------------------------------------------
; X is the Forth data stack pointer everywhere else in this system, so every
; entry point here parks it first -- the decode and the phase stepping both
; use X as an index.
D2BuildTable:
        stx     XSAV
        lda     #$FF
        ldy     #0
@clear: sta     D2NIBDEC,y
        iny
        bne     @clear
        ldy     #0
@fill:  ldx     D2NIBENC,y
        tya
        sta     D2NIBDEC,x
        iny
        cpy     #64
        bne     @fill
        ldx     XSAV
        rts

D2NIBENC:
        .byte   $96,$97,$9A,$9B,$9D,$9E,$9F,$A6
        .byte   $A7,$AB,$AC,$AD,$AE,$AF,$B2,$B3
        .byte   $B4,$B5,$B6,$B7,$B9,$BA,$BB,$BC
        .byte   $BD,$BE,$BF,$CB,$CD,$CE,$CF,$D3
        .byte   $D6,$D7,$D9,$DA,$DB,$DC,$DD,$DE
        .byte   $DF,$E5,$E6,$E7,$E9,$EA,$EB,$EC
        .byte   $ED,$EE,$EF,$F2,$F3,$F4,$F5,$F6
        .byte   $F7,$F9,$FA,$FB,$FC,$FD,$FE,$FF

; ---------------------------------------------------------------------------
        .segment "DATA"
D2TRK:   .byte  0
D2SEC:   .byte  0
D2CURH:  .byte  0                       ; head position, in half tracks
D2DSTH:  .byte  0                       ; where it is going
D2GOTTRK:.byte  0                       ; where the disk says it is
D2READY: .byte  0                       ; has the head been recalibrated?
D2MOTRUN:.byte  0
D2BUDGET:.word  0
D2CNT:   .byte  0
D2DLY:   .byte  0
D2PHIDX: .byte  0
D2CHK:   .byte  0
D2T44:   .byte  0
D2TMP:   .byte  0
D2IDX:   .byte  0
D2VOL:   .byte  0
D2NIBC:  .byte  0                       ; the trailing checksum byte
D2NIBDEC:.res   256                     ; built at cold start from D2NIBENC
        .segment "CODE"
