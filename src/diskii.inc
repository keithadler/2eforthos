; ---------------------------------------------------------------------------
; diskii.inc -- the Disk II driver as Forth words
;
; The driver itself is d2core.inc, shared with the boot loader.  This file
; only places its buffers and wraps it for the dictionary.
; ---------------------------------------------------------------------------

D2NIBM  = $0B00                 ; page aligned; see d2core.inc
D2NIBA  = $0C00

.include "d2core.inc"

; ---------------------------------------------------------------------------
; Forth words, for checking this against RWTS before anything depends on it.
; ---------------------------------------------------------------------------

; DBYTES -- the six raw disk bytes after an address prologue, undecoded.
; If the volume decodes but the sector does not, the fault is either in the
; 4-and-4 decode or in what is actually on the disk, and only the raw bytes
; tell the two apart.
        prim    "DBYTES", W_DBYTES, 0   ; -- b1 b2 b3 b4 b5 b6
        stx     XSAV
        jsr     D2MotorOn
        lda     D2Q7L
        lda     D2Q6L
        lda     #<32000
        sta     D2BUDGET
        lda     #>32000
        sta     D2BUDGET+1
@scan:
@s1:    lda     D2Q6L
        bpl     @s1
        cmp     #$D5
        bne     @next
@s2:    lda     D2Q6L
        bpl     @s2
        cmp     #$AA
        bne     @next
@s3:    lda     D2Q6L
        bpl     @s3
        cmp     #$96
        bne     @next
        ldy     #0
@grab:  lda     D2Q6L
        bpl     @grab
        sta     D2NIBA,y
        iny
        cpy     #6
        bne     @grab
        jmp     @done
@next:  lda     D2BUDGET
        bne     :+
        dec     D2BUDGET+1
:       dec     D2BUDGET
        lda     D2BUDGET
        ora     D2BUDGET+1
        bne     @scan
        lda     #0                      ; nothing found: report six zeroes
        ldy     #0
@zero:  sta     D2NIBA,y
        iny
        cpy     #6
        bne     @zero
@done:  ldx     XSAV
        ldy     #6
@push:  dey
        dex
        dex
        lda     D2NIBA,y
        sta     0,x
        lda     #0
        sta     1,x
        tya
        bne     @push
        NEXT

; DRECAL -- recalibrate to track 0 and say so.  Split out from DSEEK so the
; two halves of the positioning can be blamed separately.
        prim    "DRECAL", W_DRECAL, 0
        stx     XSAV
        jsr     D2Recal
        lda     #1
        sta     D2READY
        ldx     XSAV
        NEXT

; DSEEK -- move to a track without reading anything.
        prim    "DSEEK", W_DSEEK, 0     ; track --
        lda     0,x
        sta     D2TRK
        inx
        inx
        stx     XSAV
        jsr     D2MotorOn
        jsr     D2Seek
        ldx     XSAV
        NEXT

; DSTEP -- move n half tracks by incrementing the phase index, without
; recalibrating.  Which way the head actually goes is the thing being
; measured: read an address field before and after.
        prim    "DSTEP", W_DSTEP, 0     ; n --
        lda     0,x
        sta     D2CNT
        inx
        inx
        stx     XSAV
        jsr     D2MotorOn
@l:     inc     D2CURH
        jsr     D2StepPhase
        dec     D2CNT
        bne     @l
        ldx     XSAV
        NEXT

; DHALF -- where does the driver believe the head is, in half tracks?
        prim    "DHALF", W_DHALF, 0     ; -- n
        dex
        dex
        lda     D2CURH
        sta     0,x
        lda     #0
        sta     1,x
        NEXT

; DADDR -- report the first address field that goes past, as ( track sector ).
; 255 255 means no prologue was seen at all, which points at the drive rather
; than at the matching logic.
        prim    "DADDR", W_DADDR, 0
        stx     XSAV
        jsr     D2MotorOn
        lda     D2Q7L
        lda     D2Q6L
        lda     #<32000
        sta     D2BUDGET
        lda     #>32000
        sta     D2BUDGET+1
        lda     #$FF
        sta     D2GOTTRK
        sta     D2TMP
@scan:  jsr     D2Read1
        cmp     #$D5
        bne     @next
        jsr     D2Read1
        cmp     #$AA
        bne     @next
        jsr     D2Read1
        cmp     #$96
        bne     @next
        jsr     D2Read44
        sta     D2VOL
        jsr     D2Read44
        cmp     #35                     ; reject noise from a drive that has
        bcs     @next                   ; not come up to speed
        sta     D2GOTTRK
        jsr     D2Read44
        cmp     #16
        bcs     @next
        sta     D2TMP
        jmp     @done
@next:  lda     D2BUDGET
        bne     :+
        dec     D2BUDGET+1
:       dec     D2BUDGET
        lda     D2BUDGET
        ora     D2BUDGET+1
        bne     @scan
@done:  ldx     XSAV
        dex
        dex
        lda     D2VOL
        sta     0,x
        lda     #0
        sta     1,x
        dex
        dex
        lda     D2GOTTRK
        sta     0,x
        lda     #0
        sta     1,x
        dex
        dex
        lda     D2TMP
        sta     0,x
        lda     #0
        sta     1,x
        NEXT

        prim    "DWRITE", W_DWRITE, 0   ; track sector addr -- err
        lda     0,x
        sta     D2PTR
        lda     1,x
        sta     D2PTR+1
        lda     2,x
        and     #$0F
        tay
        lda     LOG2PHYS,y
        sta     D2SEC
        lda     4,x
        sta     D2TRK
        inx
        inx
        inx
        inx
        stx     XSAV
        jsr     D2WriteSector
        ldx     XSAV
        sta     0,x
        lda     #0
        sta     1,x
        NEXT

; DOS numbers sectors in a different order from the one they are laid down
; in: physical sector P of a track holds DOS sector 0,7,14,6,13,5,12,4,11,3,
; 10,2,9,1,8,15 respectively.  Everything above this layer -- the VTOC, the
; catalog, a file's track/sector list -- speaks DOS numbers, so they are
; translated here and D2ReadSector keeps speaking physical ones, which is
; what the boot loader needs.
;
; 0 and 15 are the two fixed points of that permutation, and for a long time
; they were the only sectors this system ever asked for: the VTOC is sector 0
; and the first catalog sector is 15.  Everything worked until the first file
; was read.
LOG2PHYS:
        .byte   0, 13, 11, 9, 7, 5, 3, 1, 14, 12, 10, 8, 6, 4, 2, 15

        prim    "DREAD", W_DREAD, 0     ; track sector addr -- err
        lda     0,x
        sta     D2PTR
        lda     1,x
        sta     D2PTR+1
        lda     2,x
        and     #$0F
        tay
        lda     LOG2PHYS,y
        sta     D2SEC
        lda     4,x
        sta     D2TRK
        inx
        inx
        inx
        inx
        stx     XSAV
        jsr     D2ReadSector
        ldx     XSAV
        sta     0,x
        lda     #0
        sta     1,x
        NEXT

; ---------------------------------------------------------------------------
