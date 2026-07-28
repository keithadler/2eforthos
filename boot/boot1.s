; ---------------------------------------------------------------------------
; boot1.s -- the boot loader, in place of DOS
;
; The Disk II controller's PROM turns the motor on, recalibrates the head to
; track 0, reads track 0 sector 0 to $0800, and jumps to $0801.  It also does
; something more useful, which this depends on: after each sector it advances
; the buffer a page, advances the sector number, and loops while that number
; is below the byte at $0800.  So the first byte of this sector is a count,
; and the PROM loads that many sectors of track 0 for us before it jumps.
;
;       $C6F1  CMP $0800
;       $C6F6  BCC (read another)
;       $C6F8  JMP $0801
;
; That buys enough room at $0800 for the whole driver, which then reads the
; kernel off the tracks after it and jumps there.  DOS is never involved: it
; is not on the disk at all, and its ten and a half kilobytes belong to the
; dictionary now.
;
; The kernel is not a file.  It lives at fixed sectors from track 1, and the
; VTOC marks those tracks in use so the catalog cannot allocate over them --
; the same arrangement DOS used for itself on tracks 0 to 2.
; ---------------------------------------------------------------------------

.include "kernsecs.inc"         ; KERNSECS, from the linked kernel's size

BOOTSECS  = 10                  ; sectors of track 0 the PROM loads for us
KERNTRK   = 1                   ; the kernel starts here
KERNADDR  = $4000

; The driver's buffers go above what the PROM loads, since that is us.
D2NIBM  = $1000
D2NIBA  = $1100

; The driver expects these in zero page.  The kernel gets them from zp.inc;
; here they are declared directly, since none of the rest of that map applies.
XSAV    = $F8
D2PTR   = $FA

; Scratch, in the region the kernel will later use for its own buffers.
LTRK    = $F0
LSEC    = $F1
LCNT    = $F2                   ; 2, sectors still to load
LDEST   = $F4                   ; 2

        .segment "STARTUP"

; $0800 is the count the PROM reads.  Execution starts at $0801.
        .byte   BOOTSECS
Start:
        cld
        ldx     #$FF
        txs
        jsr     D2BuildTable            ; invert the 6-and-2 table

        lda     #<KERNADDR              ; where the kernel goes
        sta     LDEST
        lda     #>KERNADDR
        sta     LDEST+1
        lda     #KERNTRK
        sta     LTRK
        lda     #0
        sta     LSEC

        lda     #<KERNSECS              ; how many sectors to move
        sta     LCNT
        lda     #>KERNSECS
        sta     LCNT+1

        ; Establish the head position rather than inheriting the PROM's.
        ; It does recalibrate before reading, but it also leaves the phase
        ; magnets in a state of its own choosing, and the driver's stepping
        ; assumes it knows which one is energised.
        lda     #1
        sta     D2MOTRUN                ; the motor is already running
        jsr     D2Recal
        lda     #1
        sta     D2READY

@next:  lda     LTRK
        sta     D2TRK
        lda     LSEC
        sta     D2SEC
        lda     LDEST
        sta     D2PTR
        lda     LDEST+1
        sta     D2PTR+1
        jsr     D2ReadSector
        cmp     #0
        bne     Failed

        inc     LDEST+1                 ; one sector is one page
        inc     LSEC
        lda     LSEC
        cmp     #16
        bcc     @count
        lda     #0
        sta     LSEC
        inc     LTRK

@count: lda     LCNT                    ; 16-bit decrement and test
        bne     :+
        dec     LCNT+1
:       dec     LCNT
        lda     LCNT
        ora     LCNT+1
        bne     @next

        jmp     KERNADDR

; Nothing to report to and nowhere to go: sit on the drive light so the
; failure is at least visible.
Failed:
        jmp     Failed

.include "d2core.inc"
