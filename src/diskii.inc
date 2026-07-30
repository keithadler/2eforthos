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

; DBYTES, DSTEP, DHALF and DADDR -- the head diagnostics -- were retired
; to pay for the autoload hook: nearly two hundred bytes of main memory
; that existed for one test.  The harness's pcs step is the hang-finder
; now, and git remembers the code should the head ever need questioning
; again.

; DRVSEL -- choose which drive the controller talks to.  1 or 2; anything
; else is treated as 1, because a wrong drive number must not become a
; wrong latch address.  Switching forgets the motor and the head position:
; the other drive's platter is not up to speed and its head is wherever
; the last session on it left it, so the next operation pays one spin-up
; and one recalibration.  DRIVE in system.fth wraps this and reloads the
; catalog, which is almost always what switching is for.
        prim    "DRVSEL", W_DRVSEL, 0   ; n --
        lda     0,x
        inx
        inx
        cmp     #2
        beq     :+
        lda     #1
:       sec
        sbc     #1
        cmp     D2DRVN
        beq     @same                   ; reselecting costs nothing
        sta     D2DRVN
        lda     #0
        sta     D2MOTRUN
        sta     D2READY
@same:  NEXT

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
