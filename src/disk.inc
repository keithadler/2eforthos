; ---------------------------------------------------------------------------
; disk.inc -- raw sector access through DOS 3.3's RWTS
;
; DOS is still resident at $9600, so rather than driving the Disk II by hand
; we borrow its Read/Write Track Sector routine.  Two entry points matter:
;
;   $03E3  returns the address of DOS's own IOB in A (high) and Y (low),
;          already filled in with slot, drive, and the device table pointer
;   $03D9  performs the operation described by the IOB at A/Y
;
; RWTS works entirely below $0050 in zero page, which is exactly the region
; this Forth was built to keep its hands off -- see zp.inc.  That earlier
; decision is what makes calling it safe now.
;
; The catalog is parsed in Forth on top of these two words; nothing here
; knows what a file is.
; ---------------------------------------------------------------------------

DOSIOB  = $03E3
DOSRWTS = $03D9

; Fill in DOS's IOB from RTRK/RSEC/RBUF/RCMD and call RWTS.
; Returns A = 0 on success, or RWTS's error code.
DiskOp:
        stx     XSAV
        jsr     DOSIOB
        sta     IOBP+1
        sty     IOBP
        ldy     #3
        lda     #0
        sta     (IOBP),y        ; volume 0 -- accept whatever is in the drive
        ldy     #4
        lda     RTRK
        sta     (IOBP),y
        iny
        lda     RSEC
        sta     (IOBP),y
        ldy     #8
        lda     RBUF
        sta     (IOBP),y
        iny
        lda     RBUF+1
        sta     (IOBP),y
        ldy     #12
        lda     RCMD            ; 1 = read, 2 = write
        sta     (IOBP),y
        lda     IOBP+1
        ldy     IOBP
        jsr     DOSRWTS
        bcs     @err
        ldx     XSAV
        lda     #0
        rts
@err:   jsr     DOSIOB          ; re-fetch: RWTS may have moved on
        sta     IOBP+1
        sty     IOBP
        ldy     #13
        lda     (IOBP),y
        ldx     XSAV
        rts

; ---------------------------------------------------------------------------
; Forth words
; ---------------------------------------------------------------------------
        prim    "RSECT", W_RSECT, 0     ; track sector addr -- err
        lda     #1
        sta     RCMD
        jmp     DoSector

        prim    "WSECT", W_WSECT, 0     ; track sector addr -- err
        lda     #2
        sta     RCMD
DoSector:
        lda     0,x
        sta     RBUF
        lda     1,x
        sta     RBUF+1
        lda     2,x
        sta     RSEC
        lda     4,x
        sta     RTRK
        inx
        inx
        inx
        inx
        jsr     DiskOp
        sta     0,x
        lda     #0
        sta     1,x
        NEXT
