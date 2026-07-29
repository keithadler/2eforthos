; ---------------------------------------------------------------------------
; compile.inc -- defining words, the rest of the loop set, and strings
;
; Everything here touches the compiler's own state, which is why none of it
; can be written in Forth: laying down machine code for DOES>, patching
; forward branches out of a loop, and copying a quoted string out of the
; input buffer all need the dictionary pointer and the input buffer directly.
; ---------------------------------------------------------------------------

; --- helpers ---------------------------------------------------------------

; TMP2 := the code field address of the most recent definition, Y := the
; offset of that code field within its header.  Both DOES> and RECURSE need
; it, and the arithmetic is easy to get subtly wrong twice.
LatestCFA:
        lda     LATESTV
        sta     UTMP
        lda     LATESTV+1
        sta     UTMP+1
        ldy     #4
        lda     (UTMP),y
        and     #F_LENMASK
        clc
        adc     #5                      ; len+5 is at most 68: never carries
        tay
        clc
        adc     UTMP
        sta     TMP2
        lda     UTMP+1
        adc     #0
        sta     TMP2+1
        rts

; Push the current leave-stack depth as a cell.  DO and ?DO record it so that
; LOOP knows which forward branches belong to it and which belong to a loop
; further out.
PushLVDepth:
        dex
        dex
        lda     LVDEPTH
        sta     0,x
        lda     #0
        sta     1,x
        rts

; Compile a zero cell and remember its address on the leave stack, to be
; patched with the address past the loop when LOOP is reached.
LeaveSlot:
        ldy     LVDEPTH
        cpy     #LVMAX
        bcs     @full
        lda     DPV
        sta     LVSTK,y
        lda     DPV+1
        sta     LVSTK+1,y
        lda     LVDEPTH
        clc
        adc     #2
        sta     LVDEPTH
@full:  lda     #0
        sta     TMP2
        sta     TMP2+1
        jmp     Comma

; Pop the saved depth and point every leave slot above it at HERE.
ResolveLeaves:
        lda     0,x
        sta     UTMP2
        inx
        inx
@l:     lda     LVDEPTH
        cmp     UTMP2
        beq     @done
        sec
        sbc     #2
        sta     LVDEPTH
        tay
        lda     LVSTK,y
        sta     UTMP
        lda     LVSTK+1,y
        sta     UTMP+1
        ldy     #0
        lda     DPV
        sta     (UTMP),y
        iny
        lda     DPV+1
        sta     (UTMP),y
        jmp     @l
@done:  rts

; Copy the text from the input buffer up to a closing quote into SQBUF.
; A := the length.  One leading blank is skipped, the way the standard says.
;
; Its own buffer rather than ASKLN's: an interpreted S" hands back a pointer
; into this, and the first thing you are likely to do with a string is pass
; it to something that then asks a question -- which would read the answer
; over the string.
ParseQuoted:
        lda     #0
        sta     PIDX
        ldy     TOIN
        cpy     TIBLEN
        bcs     @done
        lda     TIB,y
        cmp     #' '
        bne     @copy
        iny
@copy:  cpy     TIBLEN
        bcs     @done
        lda     TIB,y
        iny
        cmp     #'"'
        beq     @done
        sty     YSAV
        ldy     PIDX
        cpy     #INBUFSZ
        bcs     @skip                   ; refuse to overrun the buffer
        sta     SQBUF,y
        inc     PIDX
@skip:  ldy     YSAV
        jmp     @copy
@done:  sty     TOIN
        lda     PIDX
        rts

; Compile INBUF as a counted string: a length byte, then the text.
CommaCounted:
        lda     PIDX
        jsr     CComma
        lda     #0
        sta     NCNT
@l:     lda     NCNT
        cmp     PIDX
        beq     @done
        ldy     NCNT
        lda     SQBUF,y
        jsr     CComma
        inc     NCNT
        bne     @l
@done:  rts

; Compile the counted string and carry straight on to the next word.  The
; two quote words both end this way, and jumping here rather than calling
; keeps them the same length as the branch that prints instead.
CommaCountedNext:
        jsr     CommaCounted
        jmp     DoNext

; Push SQBUF and its length, for a quoted string met while interpreting.
PushInbuf:
        dex
        dex
        lda     #<SQBUF
        sta     0,x
        lda     #>SQBUF
        sta     1,x
        dex
        dex
        lda     PIDX
        sta     0,x
        lda     #0
        sta     1,x
        rts

; ---------------------------------------------------------------------------
; State and comments
; ---------------------------------------------------------------------------
        prim    "(", W_PAREN, F_IMMED
        ldy     TOIN
@l:     cpy     TIBLEN
        bcs     @done
        lda     TIB,y
        iny
        cmp     #')'
        bne     @l
@done:  sty     TOIN
        NEXT

        prim    "[", W_LBRACK, F_IMMED
        lda     #0
        sta     STATEV
        sta     STATEV+1
        NEXT

        prim    "]", W_RBRACK, 0
        lda     #1
        sta     STATEV
        lda     #0
        sta     STATEV+1
        NEXT

; ---------------------------------------------------------------------------
; Compiling one thing from inside another
; ---------------------------------------------------------------------------
        prim    "COMPILE,", W_COMPILECOMMA, 0   ; xt --
        lda     0,x
        sta     TMP2
        lda     1,x
        sta     TMP2+1
        inx
        inx
        jsr     Comma
        NEXT

        prim    "LITERAL", W_LITERAL, F_IMMED   ; x --
        lda     0,x
        pha
        lda     1,x
        pha
        inx
        inx
        lda     #<W_LIT
        ldy     #>W_LIT
        jsr     CommaWord
        pla
        sta     TMP2+1
        pla
        sta     TMP2
        jsr     Comma
        NEXT

; ['] NAME -- compile the execution token of NAME as a literal.
        head    "[']", F_IMMED
W_BRACKTICK:
        jsr     ParseWord
        jsr     FindWord
        cmp     #0
        bne     :+
        lda     #0
        sta     TMP2
        sta     TMP2+1
:       lda     TMP2
        pha
        lda     TMP2+1
        pha
        lda     #<W_LIT
        ldy     #>W_LIT
        jsr     CommaWord
        pla
        sta     TMP2+1
        pla
        sta     TMP2
        jsr     Comma
        NEXT

        prim    "CHAR", W_CHAR, 0       ; -- c
        jsr     ParseWord
        ldy     #0
        lda     (TMP1),y
        dex
        dex
        sta     0,x
        lda     #0
        sta     1,x
        NEXT

        head    "[CHAR]", F_IMMED
W_BRACKCHAR:
        jsr     ParseWord
        ldy     #0
        lda     (TMP1),y
        pha
        lda     #<W_LIT
        ldy     #>W_LIT
        jsr     CommaWord
        pla
        sta     TMP2
        lda     #0
        sta     TMP2+1
        jsr     Comma
        NEXT

; POSTPONE NAME -- an immediate word is compiled so that it runs later; an
; ordinary one is compiled as code that will compile it later.
        prim    "POSTPONE", W_POSTPONE, F_IMMED
        jsr     ParseWord
        jsr     FindWord
        cmp     #0
        beq     @done                   ; unknown: quietly nothing
        cmp     #$FF
        beq     @imm
        lda     TMP2                    ; ordinary: LIT xt  COMPILE,
        pha
        lda     TMP2+1
        pha
        lda     #<W_LIT
        ldy     #>W_LIT
        jsr     CommaWord
        pla
        sta     TMP2+1
        pla
        sta     TMP2
        jsr     Comma
        lda     #<W_COMPILECOMMA
        ldy     #>W_COMPILECOMMA
        jsr     CommaWord
        NEXT
@imm:   jsr     Comma                   ; immediate: just lay it down
@done:  NEXT

        prim    "RECURSE", W_RECURSE, F_IMMED
        jsr     LatestCFA
        jsr     Comma
        NEXT

; ---------------------------------------------------------------------------
; DOES>
;
; The child's code field has room for a JSR and nothing else, so there is
; nowhere to keep a pointer to the thread DOES> introduces.  Instead the
; defining word carries a three-byte stub of its own -- JSR DODOES, laid down
; where the thread continues -- and the child's code field is pointed at that.
; Running the child then arrives at DODOES with two return addresses on the
; hardware stack: the stub's, which is where the thread starts, and the
; child's code field, which is where its data starts.  Both are what DODOES
; needs, and neither had to be stored anywhere.
; ---------------------------------------------------------------------------
DODOES:
        pla
        sta     TMP1                    ; stub+2: the thread begins one past
        pla
        sta     TMP1+1
        pla
        sta     W                       ; code field+2: so does the data
        pla
        sta     W+1
        lda     IP+1                    ; caller's IP onto the return stack
        pha
        lda     IP
        pha
        clc
        lda     TMP1
        adc     #1
        sta     IP
        lda     TMP1+1
        adc     #0
        sta     IP+1
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

; The run-time half: point the new word's code field at the stub that follows
; this cell in the thread, then leave the defining word without running it.
W_PDOES:
        lda     LATESTV
        sta     UTMP
        lda     LATESTV+1
        sta     UTMP+1
        ldy     #4
        lda     (UTMP),y
        and     #F_LENMASK
        clc
        adc     #5
        tay
        lda     #$20                    ; JSR
        sta     (UTMP),y
        iny
        lda     IP
        sta     (UTMP),y
        iny
        lda     IP+1
        sta     (UTMP),y
        pla                             ; and return from the defining word
        sta     IP
        pla
        sta     IP+1
        NEXT

        head    "DOES>", F_IMMED
W_DOES:
        lda     #<W_PDOES
        ldy     #>W_PDOES
        jsr     CommaWord
        lda     #$20                    ; the stub: JSR DODOES
        jsr     CComma
        lda     #<DODOES
        jsr     CComma
        lda     #>DODOES
        jsr     CComma
        NEXT

; ---------------------------------------------------------------------------
; The rest of the loop set
; ---------------------------------------------------------------------------
        prim    "UNLOOP", W_UNLOOP, 0
        pla
        pla
        pla
        pla
        NEXT

        prim    "J", W_J, 0             ; the next loop out
        stx     XSAV
        tsx
        lda     $0105,x
        sta     TMP1
        lda     $0106,x
        sta     TMP1+1
        ldx     XSAV
        dex
        dex
        lda     TMP1
        sta     0,x
        lda     TMP1+1
        sta     1,x
        NEXT

; (?DO) -- like (DO), but an empty range skips the body altogether, which is
; what the following cell is for.
        prim    "(?DO)", W_PQDO, 0      ; limit start --
        lda     0,x
        cmp     2,x
        bne     @go
        lda     1,x
        cmp     3,x
        bne     @go
        inx
        inx
        inx
        inx
        jmp     DoBranch
@go:    lda     3,x
        pha
        lda     2,x
        pha
        lda     1,x
        pha
        lda     0,x
        pha
        inx
        inx
        inx
        inx
        jmp     SkipCell

; (+LOOP) -- add n to the index and stop when the index crosses the boundary
; between limit-1 and limit.  Comparing the index with the limit cannot see
; that on its own: the test is whether index-limit changed sign, which works
; for a step of either direction.
        prim    "(+LOOP)", W_PPLUSLOOP, 0
        lda     0,x                     ; the step
        sta     TMP2
        lda     1,x
        sta     TMP2+1
        inx
        inx
        stx     XSAV
        tsx
        sec                             ; before
        lda     $0101,x
        sbc     $0103,x
        sta     TMP1
        lda     $0102,x
        sbc     $0104,x
        sta     TMP1+1
        clc                             ; index += step
        lda     $0101,x
        adc     TMP2
        sta     $0101,x
        lda     $0102,x
        adc     TMP2+1
        sta     $0102,x
        sec                             ; after
        lda     $0101,x
        sbc     $0103,x
        lda     $0102,x
        sbc     $0104,x
        eor     TMP1+1                  ; sign changed?
        sta     YSAV
        ldx     XSAV
        lda     YSAV
        bmi     @finished
        jmp     DoBranch
@finished:
        pla
        pla
        pla
        pla
        jmp     SkipCell

        head    "?DO", F_IMMED
W_QDO:
        lda     #<W_PQDO
        ldy     #>W_PQDO
        jsr     CommaWord
        jsr     PushLVDepth             ; before this loop's own slot
        jsr     LeaveSlot
        jsr     PushHere
        NEXT

        head    "+LOOP", F_IMMED
W_PLUSLOOP:
        lda     #<W_PPLUSLOOP
        ldy     #>W_PPLUSLOOP
        jsr     CommaWord
        jsr     CommaPopped
        jsr     ResolveLeaves
        NEXT

        prim    "LEAVE", W_LEAVE, F_IMMED
        lda     #<W_UNLOOP
        ldy     #>W_UNLOOP
        jsr     CommaWord
        lda     #<W_BRANCH
        ldy     #>W_BRANCH
        jsr     CommaWord
        jsr     LeaveSlot
        NEXT

; --- return stack pairs ----------------------------------------------------
; These cannot be colon definitions: entering one pushes the caller's address
; on the same stack, so anything it left there would be returned into.
        prim    "2>R", W_TWOTOR, 0      ; x1 x2 -- ; R: -- x1 x2
        lda     3,x
        pha
        lda     2,x
        pha
        lda     1,x
        pha
        lda     0,x
        pha
        inx
        inx
        inx
        inx
        NEXT

        prim    "2R>", W_TWORFROM, 0
        dex                             ; 2>R pushed x2 last, so it comes back
        dex                             ; first -- and belongs on top
        dex
        dex
        pla
        sta     0,x
        pla
        sta     1,x
        pla
        sta     2,x
        pla
        sta     3,x
        NEXT

        prim    "2R@", W_TWORFETCH, 0
        stx     XSAV
        tsx
        lda     $0101,x
        sta     TMP1
        lda     $0102,x
        sta     TMP1+1
        lda     $0103,x
        sta     TMP2
        lda     $0104,x
        sta     TMP2+1
        ldx     XSAV
        dex
        dex
        dex
        dex
        lda     TMP2
        sta     2,x
        lda     TMP2+1
        sta     3,x
        lda     TMP1
        sta     0,x
        lda     TMP1+1
        sta     1,x
        NEXT

; FORGET NAME -- throw away NAME and everything defined after it.  The
; definition chain already runs newest to oldest, so the header's own link is
; the new LATEST and its address is the new DP; the buckets are then rebuilt
; from scratch, which is cheaper than unpicking sixteen chains by hand.
        prim    "FORGET", W_FORGET, 0
        jsr     ParseWord
        lda     LATESTV
        sta     UTMP
        lda     LATESTV+1
        sta     UTMP+1
@walk:  lda     UTMP
        ora     UTMP+1
        beq     @done                   ; ran off the end: no such word
        ldy     #4
        lda     (UTMP),y
        and     #F_LENMASK
        cmp     WORDLEN
        bne     @nextw
        ldy     #0
@cmp:   cpy     WORDLEN
        beq     @found
        sty     YSAV
        tya
        clc
        adc     #5
        tay
        lda     (UTMP),y
        sta     FCHR
        ldy     YSAV
        lda     (TMP1),y
        cmp     FCHR
        bne     @nextw
        iny
        bne     @cmp
@nextw: ldy     #1
        lda     (UTMP),y
        pha
        dey
        lda     (UTMP),y
        sta     UTMP
        pla
        sta     UTMP+1
        jmp     @walk
@found: lda     UTMP                    ; DP goes back to the header itself
        sta     DPV
        lda     UTMP+1
        sta     DPV+1
        ldy     #0
        lda     (UTMP),y
        pha
        iny
        lda     (UTMP),y
        sta     LATESTV+1
        pla
        sta     LATESTV
        jsr     BuildIndex
@done:  NEXT

; ---------------------------------------------------------------------------
; Strings
; ---------------------------------------------------------------------------
; (S") -- the text follows in the thread as a counted string; push its address
; and length and step over it.
W_PSQUOTE:
        ldy     #0
        lda     (IP),y
        sta     UTMP
        clc
        lda     IP
        adc     #1
        sta     TMP1
        lda     IP+1
        adc     #0
        sta     TMP1+1
        dex
        dex
        lda     TMP1
        sta     0,x
        lda     TMP1+1
        sta     1,x
        dex
        dex
        lda     UTMP
        sta     0,x
        lda     #0
        sta     1,x
        clc
        lda     IP
        adc     UTMP
        sta     IP
        lda     IP+1
        adc     #0
        sta     IP+1
        inc     IP                      ; and the count byte itself
        bne     :+
        inc     IP+1
:       NEXT

; (C") -- the same text, but pushed as the address of the count byte.
W_PCQUOTE:
        ldy     #0
        lda     (IP),y
        sta     UTMP
        dex
        dex
        lda     IP
        sta     0,x
        lda     IP+1
        sta     1,x
        clc
        lda     IP
        adc     UTMP
        sta     IP
        lda     IP+1
        adc     #0
        sta     IP+1
        inc     IP
        bne     :+
        inc     IP+1
:       NEXT

        headlink
        .byte   2 | F_IMMED
        .byte   'S', '"'
W_SQUOTE:
        jsr     ParseQuoted
        lda     STATEV
        ora     STATEV+1
        beq     @interp
        lda     #<W_PSQUOTE
        ldy     #>W_PSQUOTE
        jsr     CommaWord
        jsr     CommaCounted
        NEXT
@interp:
        jsr     PushInbuf
        NEXT

        headlink
        .byte   2 | F_IMMED
        .byte   'C', '"'
W_CQUOTE:
        jsr     ParseQuoted
        lda     #<W_PCQUOTE
        ldy     #>W_PCQUOTE
        jsr     CommaWord
        jsr     CommaCounted
        NEXT

; ---------------------------------------------------------------------------
; Giving up
; ---------------------------------------------------------------------------
        prim    "ABORT", W_ABORT, 0
        ldx     #DSTACK_TOP
        jmp     Quit

; (ABORT") -- flag on the stack, counted string in the thread.
W_PABORTQ:
        ldy     #0
        lda     (IP),y
        sta     UTMP                    ; length
        lda     0,x
        ora     1,x
        inx
        inx
        bne     @say
        clc                             ; false: step over the text
        lda     IP
        adc     UTMP
        sta     IP
        lda     IP+1
        adc     #0
        sta     IP+1
        inc     IP
        bne     :+
        inc     IP+1
:       NEXT
@say:   lda     #0
        sta     NCNT
@l:     lda     NCNT
        cmp     UTMP
        beq     @stop
        inc     NCNT
        ldy     NCNT
        lda     (IP),y
        jsr     PutChar
        jmp     @l
@stop:  stx     XSAV
        jsr     CROUT
        ldx     #DSTACK_TOP
        jmp     Quit

        headlink
        .byte   6 | F_IMMED
        .byte   'A', 'B', 'O', 'R', 'T', '"'
W_ABORTQ:
        jsr     ParseQuoted
        lda     #<W_PABORTQ
        ldy     #>W_PABORTQ
        jsr     CommaWord
        jsr     CommaCounted
        NEXT

; ---------------------------------------------------------------------------
        .segment "DATA"
LVMAX   = 32                            ; sixteen pending LEAVEs is plenty
SQBUF   = $1C00                         ; spare room above the catalog
LVSTK:  .res    LVMAX
LVDEPTH: .byte  0
        .segment "CODE"
