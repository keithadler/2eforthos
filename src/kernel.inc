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
COUT1   = $FDF0                 ; the ROM's own character output
KEYIN   = $FD1B                 ; and its key input
CSW     = $36                   ; the monitor's output vector, hooked by DOS
KSW     = $38                   ; and its input vector
TIB     = $0200                 ; GETLN's line buffer is our terminal buffer
PROMPT  = $33                   ; GETLN's prompt character

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
PutChar:
        ora     #$80                    ; the text screen wants high ASCII
        stx     XSAV
        sty     YSAV
        jsr     COUT
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
        jsr     RDKEY
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
        jsr     CROUT
        ldx     XSAV
        ldy     YSAV
        NEXT

        prim    "PAGE", W_PAGE, 0
        stx     XSAV
        sty     YSAV
        jsr     HOME
        ldx     XSAV
        ldy     YSAV
        NEXT

; --- signed decimal output -------------------------------------------------
; Div10 leaves TMP1/10 in TMP1 and the remainder in A.
Div10:
        lda     #0
        sta     TMP2
        ldy     #16
@l:     asl     TMP1
        rol     TMP1+1
        rol     TMP2
        lda     TMP2
        cmp     #10
        bcc     @skip
        sbc     #10
        sta     TMP2
        inc     TMP1                    ; quotient bit shifts in at the bottom
@skip:  dey
        bne     @l
        lda     TMP2
        rts

PrintDec:                               ; value in TMP1
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
        jsr     Div10
        ldy     YSAV
        clc
        adc     #'0'
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
