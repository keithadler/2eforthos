; ---------------------------------------------------------------------------
; kernel.inc -- inner interpreter and the primitive word set
;
; Register conventions, held to everywhere:
;   X       data stack pointer.  Sacred.  Any routine that needs X for its
;           own purposes parks it in XSAV first.
;   IP      points at the next thread cell to execute.
;   W       the code field address of the word currently being entered.
;   S       the 6502 hardware stack doubles as Forth's return stack.
; ---------------------------------------------------------------------------

; --- monitor ROM entry points ---------------------------------------------
COUT    = $FDED                 ; print A (high bit set) to the text screen
RDKEY   = $FD0C                 ; wait for a keypress, returns it in A
GETLN   = $FD6A                 ; read a line into $0200, length back in X
CROUT   = $FD8E                 ; carriage return
HOME    = $FC58                 ; clear the text screen
MONITOR = $FF69                 ; the monitor prompt; there is no DOS now
COUT1   = $FDF0                 ; the ROM's own character output
KEYIN   = $FD1B                 ; and its key input
CSW     = $36                   ; the monitor's output vector
KSW     = $38                   ; and its input vector
SETTXT  = $FB2F                 ; text mode, full window
C3INIT  = $C300                 ; the //e's own 80-column firmware
TIB     = $0200                 ; GETLN's line buffer is our terminal buffer
SRCBUF  = $0D00               ; one sector of the boot source, while booting

PROMPT  = $33                   ; GETLN's prompt character
INBUFSZ = 96                  ; a quoted string, or a typed line

; --- $1870-$1FFF: buffers above the catalog --------------------------------
; The catalog ends at $1870 (CATBUF at $1000, sixty 36-byte records) and the
; hi-res screen starts at $2000, and the room between belongs to nobody.
; Every buffer that ships as zeros in the kernel image goes here instead: a
; .res in a loaded segment costs its size in image bytes and in dictionary
; headroom, and headroom is what PICSAVE was 412 bytes short of.  Nothing
; here needs an initial value -- each is filled at cold start or in use.
;
; This block is the WHOLE map of the region, every occupant, one place.  It
; was not always: the fill's seed stacks were allocated here from fill.inc
; and the disk decode table was later allocated on top of them from another
; file, so a flood fill would have quietly destroyed every disk read until
; the next boot.  Allocate from this list, never around it.
BUCKETS  = $1870                ; 32: hash chain heads, built at cold start
BTAILS   = $1890                ; 32: BuildIndex's tails, dead after boot
NUMBUF   = $18B0                ; 20: digits, emitted in reverse
LVSTK    = $18C4                ; 32: pending LEAVEs while compiling
                                ; $18E4-$18FF spare
FSXL     = $1900                ; 256: flood fill seed stack, x low bytes
FSXH     = $1A00                ; 256: seed stack, x high bytes
FSY      = $1B00                ; 256: seed stack, y
SQBUF    = $1C00                ; 96 (INBUFSZ): a quoted string
INBUF    = $1C60                ; 96 (INBUFSZ): ASKLN's copy of a typed line
                                ; $1CC0-$1CFF spare
D2NIBDEC = $1D00                ; 256: 6-and-2 decode, built at cold start.
                                ; Page aligned like D2NIBM/D2NIBA, though
                                ; only the encode side is cycle-critical.
FZSAVE   = $1E00                ; 93: the whole of $50-$AC, around FP calls
FSTK     = $1E60                ; 45: eight floats and a spare for FSWAP
; Scratch bytes, every one written before it is read.  They were .byte 0
; in the DATA segment, which made each of them cost an image byte and a
; dictionary byte for no reason.  Only state that must SURVIVE from one
; use to the next -- D2READY, D2MOTRUN, D2DRVN, HXORF, GCOL, RSEED --
; stays in the image, because those need their boot value.
D2TRK    = $1E90                ; the disk driver's working state
D2SEC    = $1E91
D2CURH   = $1E92                ; head position; recal writes it first
D2DSTH   = $1E93
D2GOTTRK = $1E94
D2BUDGET = $1E95                ; 2
D2CNT    = $1E97
D2DLY    = $1E98
D2PHIDX  = $1E99
D2CHK    = $1E9A
D2T44    = $1E9B
D2TMP    = $1E9C
D2IDX    = $1E9D
D2VOL    = $1E9E
D2NIBC   = $1E9F
NBKT     = $1EA0                ; the compiler's
NEWHDR   = $1EA1                ; 2
STRLEN   = $1EA3                ; 2
CFLO     = $1EA5
CFHI     = $1EA6
FTMP     = $1EA7                ; 2: the FP words'
GLX      = $1EA9                ; the lo-res driver's
GLY      = $1EAA
GRT      = $1EAB
GTMP2    = $1EAC
GRMIX    = $1EAE                ; lo-res: are the bottom four rows text?
CARDBK   = $1EAD                ; how many aux banks the cold-start probe
                                ; counted: 1 = stock 128K, 128 = an 8MB card
FDI      = $1EAF                ; 2: the decimal reader's whole part
FDF      = $1EB1                ; 2: and its fraction
FDN      = $1EB3                ; how many places that fraction has
FDS      = $1EB4                ; was there a minus
FDDOT    = $1EB5                ; has the point been seen
FDANY    = $1EB6                ; has any digit been seen
NFSAV    = $1EB7                ; 3: the unknown word, kept across the hook
PAGE2ON  = $C055                ; with 80STORE, which bank $0400-$07FF is
PAGE2OFF = $C054
CINVF    = $1EBA                ; console writes: inverse video?
COFF     = $1EBB                ; and the byte offset within the row
                                ; $1EBC-$1FFF spare

.macro  NEXT
        jmp     DoNext
.endmacro

; ---------------------------------------------------------------------------
; The inner interpreter: fetch the next code field address, advance, jump.
; ---------------------------------------------------------------------------
DoNext:
        ldy     #1
        lda     (IP),y
        sta     W+1
        dey
        lda     (IP),y
        sta     W
        clc
        lda     IP
        adc     #2
        sta     IP
        bcc     :+
        inc     IP+1
:       jmp     (W)

; --- entering a colon definition ------------------------------------------
; Reached by the JSR in the code field, so the hardware stack holds PFA-1.
DOCOL:
        pla
        sta     W
        pla
        sta     W+1
        lda     IP+1                    ; caller's IP onto the return stack
        pha
        lda     IP
        pha
        clc
        lda     W
        adc     #1
        sta     IP
        lda     W+1
        adc     #0
        sta     IP+1
        NEXT

; --- a variable pushes the address of its parameter field ------------------
DOVAR:
        pla
        sta     W
        pla
        sta     W+1
        clc
        lda     W
        adc     #1
        sta     W
        lda     W+1
        adc     #0
        sta     W+1
        dex
        dex
        lda     W
        sta     0,x
        lda     W+1
        sta     1,x
        NEXT

; --- a constant pushes the contents of its parameter field -----------------
DOCON:
        pla
        sta     W
        pla
        sta     W+1
        clc
        lda     W
        adc     #1
        sta     W
        lda     W+1
        adc     #0
        sta     W+1
        ldy     #0
        lda     (W),y
        sta     TMP1
        iny
        lda     (W),y
        dex
        dex
        sta     1,x
        lda     TMP1
        sta     0,x
        NEXT

; ---------------------------------------------------------------------------
; DoRun -- run the Forth word whose code field address is in TMP2, then
; return to the assembly caller.  This is the bridge the outer interpreter
; uses to execute a word it has just looked up.
;
; The trick is a two-cell thread: the word itself, then RetToAsm, whose code
; restores IP and RTSes past the JSR that got us here.
; ---------------------------------------------------------------------------
DoRun:
        lda     TMP2
        sta     RunSlot
        lda     TMP2+1
        sta     RunSlot+1
        lda     IP+1
        pha
        lda     IP
        pha
        lda     #<RunSlot
        sta     IP
        lda     #>RunSlot
        sta     IP+1
        NEXT

RetToAsm:
        pla
        sta     IP
        pla
        sta     IP+1
        rts                             ; back to whoever JSR'd DoRun

; ---------------------------------------------------------------------------
; Stack manipulation
; ---------------------------------------------------------------------------
        prim    "DUP", W_DUP, 0
        dex
        dex
        lda     2,x
        sta     0,x
        lda     3,x
        sta     1,x
        NEXT

        prim    "DROP", W_DROP, 0
        inx
        inx
        NEXT

        prim    "SWAP", W_SWAP, 0
        lda     0,x
        ldy     2,x
        sty     0,x
        sta     2,x
        lda     1,x
        ldy     3,x
        sty     1,x
        sta     3,x
        NEXT

        prim    "OVER", W_OVER, 0
        dex
        dex
        lda     4,x
        sta     0,x
        lda     5,x
        sta     1,x
        NEXT

        prim    "ROT", W_ROT, 0         ; a b c -- b c a
        lda     4,x
        sta     TMP1
        lda     5,x
        sta     TMP1+1
        lda     2,x
        sta     4,x
        lda     3,x
        sta     5,x
        lda     0,x
        sta     2,x
        lda     1,x
        sta     3,x
        lda     TMP1
        sta     0,x
        lda     TMP1+1
        sta     1,x
        NEXT

        prim    "NIP", W_NIP, 0         ; a b -- b
        lda     0,x
        sta     2,x
        lda     1,x
        sta     3,x
        inx
        inx
        NEXT

        prim    "?DUP", W_QDUP, 0
        lda     0,x
        ora     1,x
        beq     :+
        dex
        dex
        lda     2,x
        sta     0,x
        lda     3,x
        sta     1,x
:       NEXT

        prim    "DEPTH", W_DEPTH, 0
        lda     #DSTACK_TOP
        stx     TMP1
        sec
        sbc     TMP1
        lsr     a                       ; cells, not bytes
        dex
        dex
        sta     0,x
        lda     #0
        sta     1,x
        NEXT

; --- return stack ----------------------------------------------------------
        prim    ">R", W_TOR, 0
        lda     1,x
        pha
        lda     0,x
        pha
        inx
        inx
        NEXT

        prim    "R>", W_FROMR, 0
        dex
        dex
        pla
        sta     0,x
        pla
        sta     1,x
        NEXT

        prim    "R@", W_RFETCH, 0
        pla
        sta     TMP1
        pla
        sta     TMP1+1
        lda     TMP1+1
        pha
        lda     TMP1
        pha
        dex
        dex
        lda     TMP1
        sta     0,x
        lda     TMP1+1
        sta     1,x
        NEXT

; ---------------------------------------------------------------------------
; Arithmetic and logic
; ---------------------------------------------------------------------------
        prim    "+", W_ADD, 0
        clc
        lda     0,x
        adc     2,x
        sta     2,x
        lda     1,x
        adc     3,x
        sta     3,x
        inx
        inx
        NEXT

        prim    "-", W_SUB, 0
        sec
        lda     2,x
        sbc     0,x
        sta     2,x
        lda     3,x
        sbc     1,x
        sta     3,x
        inx
        inx
        NEXT

        prim    "1+", W_INCR, 0
        inc     0,x
        bne     :+
        inc     1,x
:       NEXT

        prim    "1-", W_DECR, 0
        lda     0,x
        bne     :+
        dec     1,x
:       dec     0,x
        NEXT

        prim    "2*", W_TWOMUL, 0
        asl     0,x
        rol     1,x
        NEXT

        prim    "2/", W_TWODIV, 0       ; arithmetic: sign preserved
        lda     1,x
        cmp     #$80
        ror     1,x
        ror     0,x
        NEXT

        prim    "NEGATE", W_NEGATE, 0
        sec
        lda     #0
        sbc     0,x
        sta     0,x
        lda     #0
        sbc     1,x
        sta     1,x
        NEXT

        prim    "AND", W_AND, 0
        lda     0,x
        and     2,x
        sta     2,x
        lda     1,x
        and     3,x
        sta     3,x
        inx
        inx
        NEXT

        prim    "OR", W_OR, 0
        lda     0,x
        ora     2,x
        sta     2,x
        lda     1,x
        ora     3,x
        sta     3,x
        inx
        inx
        NEXT

        prim    "XOR", W_XOR, 0
        lda     0,x
        eor     2,x
        sta     2,x
        lda     1,x
        eor     3,x
        sta     3,x
        inx
        inx
        NEXT

        prim    "INVERT", W_INVERT, 0
        lda     0,x
        eor     #$FF
        sta     0,x
        lda     1,x
        eor     #$FF
        sta     1,x
        NEXT

; Shift-and-add, low 16 bits of the product -- correct for signed operands
; too, since the low half of a product does not depend on sign.
        prim    "*", W_MUL, 0
        lda     #0
        sta     TMP1
        sta     TMP1+1
        ldy     #16
@mul:   lsr     1,x                     ; multiplier >>= 1
        ror     0,x
        bcc     @noadd
        clc
        lda     TMP1
        adc     2,x
        sta     TMP1
        lda     TMP1+1
        adc     3,x
        sta     TMP1+1
@noadd: asl     2,x                     ; multiplicand <<= 1
        rol     3,x
        dey
        bne     @mul
        lda     TMP1
        sta     2,x
        lda     TMP1+1
        sta     3,x
        inx
        inx
        NEXT

; Restoring division, unsigned.  ( u1 u2 -- rem quot )
        prim    "U/MOD", W_UDIVMOD, 0
        lda     #0
        sta     TMP1
        sta     TMP1+1
        ldy     #16
@div:   asl     2,x                     ; dividend <<= 1, top bit into rem
        rol     3,x
        rol     TMP1
        rol     TMP1+1
        sec                             ; try rem -= divisor
        lda     TMP1
        sbc     0,x
        sta     TMP2
        lda     TMP1+1
        sbc     1,x
        bcc     @skip                   ; went negative: leave rem alone
        sta     TMP1+1
        lda     TMP2
        sta     TMP1
        inc     2,x                     ; and set this quotient bit
@skip:  dey
        bne     @div
        lda     2,x                     ; quotient to TOS, remainder to NOS
        sta     TMP2
        lda     3,x
        sta     TMP2+1
        lda     TMP1
        sta     2,x
        lda     TMP1+1
        sta     3,x
        lda     TMP2
        sta     0,x
        lda     TMP2+1
        sta     1,x
        NEXT

; ---------------------------------------------------------------------------
; Comparison.  True is -1, false is 0, as Forth expects.
; ---------------------------------------------------------------------------
        prim    "0=", W_ZEQ, 0
        lda     0,x
        ora     1,x
        beq     @true
        lda     #0
        beq     @st
@true:  lda     #$FF
@st:    sta     0,x
        sta     1,x
        NEXT

        prim    "0<", W_ZLT, 0
        lda     1,x
        bmi     @true
        lda     #0
        beq     @st
@true:  lda     #$FF
@st:    sta     0,x
        sta     1,x
        NEXT

        prim    "=", W_EQ, 0
        lda     0,x
        cmp     2,x
        bne     @false
        lda     1,x
        cmp     3,x
        bne     @false
        lda     #$FF
        bne     @st
@false: lda     #0
@st:    inx
        inx
        sta     0,x
        sta     1,x
        NEXT

        prim    "<", W_LT, 0            ; signed
        sec
        lda     2,x
        sbc     0,x
        lda     3,x
        sbc     1,x
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

        prim    "U<", W_ULT, 0          ; unsigned
        lda     2,x
        cmp     0,x
        lda     3,x
        sbc     1,x
        bcc     @true
        lda     #0
        beq     @st
@true:  lda     #$FF
@st:    inx
        inx
        sta     0,x
        sta     1,x
        NEXT

; ---------------------------------------------------------------------------
; Memory
; ---------------------------------------------------------------------------
        prim    "@", W_FETCH, 0
        lda     0,x
        sta     TMP1
        lda     1,x
        sta     TMP1+1
        ldy     #0
        lda     (TMP1),y
        sta     0,x
        iny
        lda     (TMP1),y
        sta     1,x
        NEXT

        prim    "!", W_STORE, 0         ; v a --
        lda     0,x
        sta     TMP1
        lda     1,x
        sta     TMP1+1
        ldy     #0
        lda     2,x
        sta     (TMP1),y
        iny
        lda     3,x
        sta     (TMP1),y
        inx
        inx
        inx
        inx
        NEXT

        prim    "C@", W_CFETCH, 0
        lda     0,x
        sta     TMP1
        lda     1,x
        sta     TMP1+1
        ldy     #0
        lda     (TMP1),y
        sta     0,x
        sty     1,x
        NEXT

        prim    "C!", W_CSTORE, 0       ; c a --
        lda     0,x
        sta     TMP1
        lda     1,x
        sta     TMP1+1
        ldy     #0
        lda     2,x
        sta     (TMP1),y
        inx
        inx
        inx
        inx
        NEXT

        prim    "+!", W_PLUSSTORE, 0    ; n a --
        lda     0,x
        sta     TMP1
        lda     1,x
        sta     TMP1+1
        ldy     #0
        clc
        lda     (TMP1),y
        adc     2,x
        sta     (TMP1),y
        iny
        lda     (TMP1),y
        adc     3,x
        sta     (TMP1),y
        inx
        inx
        inx
        inx
        NEXT

; ---------------------------------------------------------------------------
; Threading control
; ---------------------------------------------------------------------------
        prim    "EXIT", W_EXIT, 0
        pla
        sta     IP
        pla
        sta     IP+1
        NEXT

        prim    "EXECUTE", W_EXECUTE, 0
        lda     0,x
        sta     W
        lda     1,x
        sta     W+1
        inx
        inx
        jmp     (W)

; Push the cell compiled inline after this one.
        prim    "LIT", W_LIT, 0
        ldy     #0
        lda     (IP),y
        sta     TMP1
        iny
        lda     (IP),y
        dex
        dex
        sta     1,x
        lda     TMP1
        sta     0,x
        clc
        lda     IP
        adc     #2
        sta     IP
        bcc     :+
        inc     IP+1
:       NEXT

; Branches carry an absolute target inline, which keeps the compiling words
; simple: they only ever patch a whole cell.
        prim    "BRANCH", W_BRANCH, 0
DoBranch:
        ldy     #0
        lda     (IP),y
        sta     TMP1
        iny
        lda     (IP),y
        sta     IP+1
        lda     TMP1
        sta     IP
        NEXT

        prim    "0BRANCH", W_0BRANCH, 0
        lda     0,x
        ora     1,x
        inx
        inx
        cmp     #$00                    ; INX clobbered Z, but A still holds
        beq     DoBranch                ; the OR -- re-test it here
SkipCell:
        clc
        lda     IP
        adc     #2
        sta     IP
        bcc     :+
        inc     IP+1
:       NEXT

; --- counted loops ---------------------------------------------------------
; (DO) moves limit and index onto the return stack, index on top, so that I
; is a cheap peek and (LOOP) can reach the limit two cells down.
        prim    "(DO)", W_PDO, 0        ; limit start --
        lda     3,x                     ; limit hi
        pha
        lda     2,x                     ; limit lo
        pha
        lda     1,x                     ; index hi
        pha
        lda     0,x                     ; index lo
        pha
        inx
        inx
        inx
        inx
        NEXT

        prim    "(LOOP)", W_PLOOP, 0
        stx     XSAV
        tsx
        clc
        lda     $0101,x                 ; index++
        adc     #1
        sta     $0101,x
        lda     $0102,x
        adc     #0
        sta     $0102,x
        sec                             ; index - limit, signed
        lda     $0101,x
        sbc     $0103,x
        lda     $0102,x
        sbc     $0104,x
        bvc     @nov
        eor     #$80
@nov:   sta     YSAV                    ; LDX would set N from the stack
        ldx     XSAV                    ; pointer, so stash the comparison
        lda     YSAV                    ; and re-test it after restoring X
        bpl     @finished               ; index reached the limit
        jmp     DoBranch                ; otherwise go round again
@finished:
        pla                             ; discard index and limit
        pla
        pla
        pla
        jmp     SkipCell

        prim    "I", W_I, 0
        stx     XSAV
        tsx
        lda     $0101,x
        sta     TMP1
        lda     $0102,x
        sta     TMP1+1
        ldx     XSAV
        dex
        dex
        lda     TMP1
        sta     0,x
        lda     TMP1+1
        sta     1,x
        NEXT

; ---------------------------------------------------------------------------
; Terminal I/O
; ---------------------------------------------------------------------------
; COUT and friends clobber X and Y, so both get parked around every call.
; ReadLine -- a line into TIB, length in A.
;
; This is the monitor's GETLN written out again, and the reason is the
; language card: GETLN lives in the ROM, so waiting inside it means waiting
; with the card banked out -- and the card is where the system's dictionary
; is.  Anything looking at the machine while it sat at the prompt would see
; ROM where the dictionary should be.  Here it waits in main memory instead,
; and only steps into the ROM for the few cycles it takes to echo.
;
; Keys are folded to upper case on the way in, because every name in the
; dictionary is upper case.
ReadLine:
        stx     LNX
        lda     PROMPT
        jsr     PutChar
        ldy     #0
@key:   lda     KBD
        bpl     @key
        bit     KBDSTRB
        and     #$7F
        cmp     #'a'
        bcc     @nofold
        cmp     #'z'+1
        bcs     @nofold
        sec
        sbc     #$20
@nofold:
        cmp     #$0D
        beq     @done
        cmp     #$08                    ; backspace, and the left arrow
        beq     @back
        cmp     #$20
        bcc     @key                    ; any other control: ignore it
        cpy     #200
        bcs     @key                    ; the line buffer is one page
        sta     TIB,y
        iny
        jsr     PutChar                 ; leaves Y alone
        jmp     @key
@back:  cpy     #0
        beq     @key
        dey
        lda     #$08
        jsr     PutChar
        lda     #' '
        jsr     PutChar
        lda     #$08
        jsr     PutChar
        jmp     @key
@done:  sty     LNLEN
        ROMIN
        jsr     CROUT
        ROMOUT
        ldx     LNX
        lda     LNLEN
        rts

PutChar:
        ora     #$80                    ; the text screen wants high ASCII
        stx     XSAV
        sty     YSAV
        ROMIN
        jsr     COUT
        ROMOUT
        ldx     XSAV
        ldy     YSAV
        rts

; Print the zero-terminated string at TMP2.
PutStr:
        ldy     #0
@l:     lda     (TMP2),y
        beq     @done
        jsr     PutChar                 ; preserves X and Y
        iny
        bne     @l
@done:  rts

        prim    "EMIT", W_EMIT, 0
        lda     0,x
        inx
        inx
        jsr     PutChar
        NEXT

        prim    "KEY", W_KEY, 0
        stx     XSAV
        ROMIN
        jsr     RDKEY
        ROMOUT
        ldx     XSAV
        and     #$7F
        dex
        dex
        sta     0,x
        lda     #0
        sta     1,x
        NEXT

        prim    "CR", W_CR, 0
        stx     XSAV
        sty     YSAV
        ROMIN
        jsr     CROUT
        ROMOUT
        ldx     XSAV
        ldy     YSAV
        NEXT

        prim    "PAGE", W_PAGE, 0
        stx     XSAV
        sty     YSAV
        ROMIN
        jsr     HOME
        ROMOUT
        ldx     XSAV
        ldy     YSAV
        NEXT

; --- signed numeric output -------------------------------------------------
; TMP1 := TMP1 / BASE, A := the remainder.  A general divide rather than the
; divide-by-ten this used to be: BASE is a variable, and a BASE that only
; some of the output words honoured would be worse than none at all.
DivBase:
        lda     #0
        ldy     #16
@l:     asl     TMP1
        rol     TMP1+1
        rol     a
        cmp     BASEV
        bcc     @skip
        sbc     BASEV
        inc     TMP1
@skip:  dey
        bne     @l
        rts

PrintDec:                               ; value in TMP1, printed in BASE
        lda     TMP1+1
        bpl     @pos
        sec
        lda     #0
        sbc     TMP1
        sta     TMP1
        lda     #0
        sbc     TMP1+1
        sta     TMP1+1
        lda     #'-'
        jsr     PutChar
@pos:   ldy     #0
@digit: sty     YSAV
        jsr     DivBase
        ldy     YSAV
        cmp     #10                     ; past nine the digits are letters
        bcc     :+
        adc     #6                      ; carry is set, so this adds seven
:       adc     #'0'
        sta     NUMBUF,y
        iny
        lda     TMP1
        ora     TMP1+1
        bne     @digit
@out:   dey                             ; digits came out backwards
        lda     NUMBUF,y
        jsr     PutChar
        tya
        bne     @out
        rts

        prim    ".", W_DOT, 0
        lda     0,x
        sta     TMP1
        lda     1,x
        sta     TMP1+1
        inx
        inx
        jsr     PrintDec
        lda     #' '
        jsr     PutChar
        NEXT

; Print the inline counted string that follows, then skip past it.
; Spelled out in bytes because ca65 strings have no escape for a quote.
        headlink
        .byte   4
        .byte   '(', '.', '"', ')'
W_PDOTQ:
        ldy     #0
        lda     (IP),y                  ; length byte
        sta     TMP1
        beq     @skip
        sta     TMP2
        ldy     #1
@l:     lda     (IP),y
        jsr     PutChar                 ; preserves Y
        iny
        dec     TMP2
        bne     @l
@skip:  sec                             ; IP += length + 1 (SEC supplies the 1)
        lda     TMP1
        adc     IP
        sta     IP
        bcc     :+
        inc     IP+1
:       NEXT
