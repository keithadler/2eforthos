; ---------------------------------------------------------------------------
; loader.s -- load the kernel off the disk without DOS's file manager
;
; DOS 3.3's BLOAD manages a file buffer, tracks a position, and re-enters the
; file manager for every sector.  All of that takes longer than the gap
; between two sectors, so it misses the interleave and waits most of a
; revolution per sector: measured, the 15K kernel took about nine seconds to
; load, or roughly seven sectors a second.
;
; RWTS itself is not the problem, so this walks the catalog and the file's
; track/sector list by hand and reads the data sectors straight into place.
; The only work between one sector and the next is a 256-byte copy, which
; fits comfortably inside the gap, so consecutive sectors are caught on the
; same revolution.
;
; DOS stays resident: the kernel still calls RWTS for the catalog, and this
; only replaces the layer above it.
;
; BRUN at $0800 by the disk's greeting program, which it then overwrites --
; that is safe because it never returns, it jumps to the kernel.
; ---------------------------------------------------------------------------

BUF     = $0C00                 ; one raw sector
PAIRS   = $0D00                 ; a track/sector list's 122 pairs, copied out
                                ; of BUF before data reads overwrite it

DOSIOB  = $03E3                 ; -> A/Y = high/low of DOS's own IOB
DOSRWTS = $03D9                 ; perform the operation the IOB describes

; Zero page.  $50 upward is what the kernel will eventually use for its data
; stack, so it is free while the loader runs.
IOBP    = $50                   ; 2
LTRK    = $52
LSEC    = $53
DEST    = $54                   ; 2
CTRK    = $56
CSEC    = $57
TSTRK   = $58
TSSEC   = $59
NTRK    = $5A
NSEC    = $5B
LPTR    = $5C                   ; 2
IDX     = $5E
CNT     = $5F
FIRST   = $60
ENTRY   = $61                   ; 2

        .segment "STARTUP"

Start:
        lda     #17                     ; the VTOC names the first catalog
        sta     LTRK                    ; sector
        lda     #0
        sta     LSEC
        jsr     ReadSector
        lda     BUF+1
        sta     CTRK
        lda     BUF+2
        sta     CSEC

; --- find the kernel in the catalog ---------------------------------------
@catalog:
        lda     CTRK
        bne     @havecat
        jmp     Fail                    ; ran out of catalog: no such file
@havecat:
        sta     LTRK
        lda     CSEC
        sta     LSEC
        jsr     ReadSector
        lda     BUF+1                   ; remember the next catalog sector
        sta     CTRK                    ; before anything overwrites BUF
        lda     BUF+2
        sta     CSEC

        lda     #<(BUF+11)              ; seven 35-byte entries per sector
        sta     LPTR
        lda     #>(BUF+11)
        sta     LPTR+1
        lda     #7
        sta     CNT
@entry:
        ldy     #0
        lda     (LPTR),y
        beq     @next                   ; never used
        cmp     #$FF
        beq     @next                   ; deleted
        ldy     #3                      ; names are 30 bytes, high bit set
        ldx     #0
@compare:
        lda     (LPTR),y
        cmp     NAME,x
        bne     @next
        inx
        iny
        cpy     #33
        bne     @compare
        ldy     #0                      ; matched: take its T/S list
        lda     (LPTR),y
        sta     TSTRK
        iny
        lda     (LPTR),y
        sta     TSSEC
        jmp     LoadFile
@next:  clc
        lda     LPTR
        adc     #35
        sta     LPTR
        bcc     :+
        inc     LPTR+1
:       dec     CNT
        bne     @entry
        jmp     @catalog

; --- read the data sectors ------------------------------------------------
LoadFile:
        lda     #1
        sta     FIRST
@list:  lda     TSTRK
        beq     Done
        sta     LTRK
        lda     TSSEC
        sta     LSEC
        jsr     ReadSector
        lda     BUF+1                   ; the list may chain
        sta     NTRK
        lda     BUF+2
        sta     NSEC
        ldy     #0                      ; copy the pairs out: the data reads
@save:  lda     BUF+$0C,y               ; below reuse BUF
        sta     PAIRS,y
        iny
        cpy     #244
        bne     @save

        lda     #0
        sta     IDX
@pair:  ldx     IDX
        lda     PAIRS,x
        beq     @listnext               ; track 0 marks an unused slot
        sta     LTRK
        lda     PAIRS+1,x
        sta     LSEC
        jsr     ReadSector
        jsr     CopyOut
        lda     IDX
        clc
        adc     #2
        sta     IDX
        cmp     #244
        bne     @pair
@listnext:
        lda     NTRK
        sta     TSTRK
        lda     NSEC
        sta     TSSEC
        jmp     @list

Done:   jmp     (ENTRY)

Fail:   jmp     $03D0                   ; hand back to DOS with an empty screen

; ---------------------------------------------------------------------------
; CopyOut -- move BUF into place.
;
; A DOS binary file starts with two bytes of load address and two of length,
; so the first sector carries only 252 bytes of program and sets where the
; rest goes.  After that the destination is no longer page aligned, which
; costs nothing: the copy is indexed either way.
; ---------------------------------------------------------------------------
CopyOut:
        lda     FIRST
        beq     @body
        lda     BUF+0
        sta     DEST
        sta     ENTRY
        lda     BUF+1
        sta     DEST+1
        sta     ENTRY+1
        lda     #0
        sta     FIRST
        ldy     #0
@head:  lda     BUF+4,y
        sta     (DEST),y
        iny
        cpy     #252
        bne     @head
        clc
        lda     DEST
        adc     #252
        sta     DEST
        bcc     :+
        inc     DEST+1
:       rts
@body:  ldy     #0
@copy:  lda     BUF,y
        sta     (DEST),y
        iny
        bne     @copy
        inc     DEST+1
        rts

; ---------------------------------------------------------------------------
; ReadSector -- LTRK/LSEC into BUF, through DOS's own IOB
; ---------------------------------------------------------------------------
ReadSector:
        jsr     DOSIOB
        sta     IOBP+1
        sty     IOBP
        ldy     #3
        lda     #0
        sta     (IOBP),y                ; volume 0: accept what is in the drive
        ldy     #4
        lda     LTRK
        sta     (IOBP),y
        iny
        lda     LSEC
        sta     (IOBP),y
        ldy     #8
        lda     #<BUF
        sta     (IOBP),y
        iny
        lda     #>BUF
        sta     (IOBP),y
        ldy     #12
        lda     #1                      ; read
        sta     (IOBP),y
        lda     IOBP+1
        ldy     IOBP
        jmp     DOSRWTS

; The name as DOS stores it: 30 characters, high bit set, space padded.
NAME:
        .byte   'F'|$80, 'O'|$80, 'R'|$80, 'T'|$80, 'H'|$80
        .byte   '.'|$80, 'B'|$80, 'I'|$80, 'N'|$80
        .res    21, $A0
