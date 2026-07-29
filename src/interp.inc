; ---------------------------------------------------------------------------
; interp.inc -- outer interpreter, compiler, and defining words
;
; The outer interpreter is assembly rather than a colon definition, which
; keeps the bootstrap short: there is no chicken-and-egg problem where the
; thing that compiles definitions must itself be compiled.  It reaches back
; into Forth through DoRun whenever it has to execute a word.
; ---------------------------------------------------------------------------

; --- system variables, visible from Forth ----------------------------------
        head    "STATE", 0
W_STATE:        jsr DOVAR
STATEV:         .word 0         ; 0 interpreting, 1 compiling

        head    "BASE", 0
W_BASE:         jsr DOVAR
BASEV:          .word 10

        head    "DP", 0
W_DP:           jsr DOVAR
DPV:            .word KERNEL_END

        head    "LATEST", 0
W_LATEST:       jsr DOVAR
LATESTV:        .word FINAL_LATEST

; ---------------------------------------------------------------------------
; Dictionary construction helpers
; ---------------------------------------------------------------------------

; Append the cell in TMP2 at DP.
Comma:
        lda     DPV
        sta     UTMP
        lda     DPV+1
        sta     UTMP+1
        ldy     #0
        lda     TMP2
        sta     (UTMP),y
        iny
        lda     TMP2+1
        sta     (UTMP),y
        clc
        lda     DPV
        adc     #2
        sta     DPV
        lda     DPV+1
        adc     #0
        sta     DPV+1
        rts

; Append the byte in A at DP.
CComma:
        sta     UTMP2
        lda     DPV
        sta     UTMP
        lda     DPV+1
        sta     UTMP+1
        ldy     #0
        lda     UTMP2
        sta     (UTMP),y
        inc     DPV
        bne     :+
        inc     DPV+1
:       rts

; Compile a call to the primitive whose address is in A/Y (lo/hi).
CommaWord:
        sta     TMP2
        sty     TMP2+1
        jmp     Comma

; Clear the hidden bit on the most recent definition.
Unhide:
        lda     LATESTV
        sta     UTMP
        lda     LATESTV+1
        sta     UTMP+1
        ldy     #4
        lda     (UTMP),y
        and     #$BF
        sta     (UTMP),y
        rts

; Lay down a header for the name at TMP1/WORDLEN and link it into both chains,
; hidden.  A new definition is the newest of its bucket, so it goes on the
; front -- the opposite of how BuildIndex fills them at cold start.
CreateHeader:
        jsr     HashName
        asl     a                       ; two bytes per bucket
        sta     NBKT
        lda     DPV
        sta     NEWHDR
        lda     DPV+1
        sta     NEWHDR+1
        lda     LATESTV                 ; definition-order link
        sta     TMP2
        lda     LATESTV+1
        sta     TMP2+1
        jsr     Comma
        ldy     NBKT                    ; bucket link
        lda     BUCKETS,y
        sta     TMP2
        lda     BUCKETS+1,y
        sta     TMP2+1
        jsr     Comma
        lda     WORDLEN
        ora     #F_HIDDEN
        jsr     CComma
        lda     #0
        sta     PIDX
@l:     lda     PIDX
        cmp     WORDLEN
        beq     @done
        ldy     PIDX
        lda     (TMP1),y
        jsr     CComma
        inc     PIDX
        bne     @l
@done:  lda     NEWHDR
        sta     LATESTV
        lda     NEWHDR+1
        sta     LATESTV+1
        ldy     NBKT
        lda     NEWHDR
        sta     BUCKETS,y
        lda     NEWHDR+1
        sta     BUCKETS+1,y
        rts

; Lay down a `JSR <A/Y>` code field.
CommaCodeField:
        sta     CFLO
        sty     CFHI
        lda     #$20                    ; JSR opcode
        jsr     CComma
        lda     CFLO
        jsr     CComma
        lda     CFHI
        jmp     CComma

; ---------------------------------------------------------------------------
; Input
; ---------------------------------------------------------------------------

; Read the next sector of the system's own source into SRCBUF and point SRC
; at it.  Carry set means there are none left.
;
; The sectors are laid down consecutively from SRCTRACK with no interleave:
; compiling one takes about a second and the disk turns five times in that,
; so where the next sector sits makes no difference to how long it is waited
; for.  X belongs to the Forth stack and the caller parks it.
NextSrcSector:
        lda     SRCIDX
        cmp     #SRCSECS
        bcs     @none
        lsr     a                       ; sixteen sectors to the track
        lsr     a
        lsr     a
        lsr     a
        clc
        adc     #SRCTRACK
        sta     D2TRK
        lda     SRCIDX
        and     #$0F
        sta     D2SEC
        lda     #<SRCBUF
        sta     D2PTR
        lda     #>SRCBUF
        sta     D2PTR+1
        jsr     D2ReadSector
        inc     SRCIDX
        lda     #<SRCBUF
        sta     SRC
        lda     #>SRCBUF
        sta     SRC+1
        clc
        rts
@none:  lda     #0
        sta     SRC+1
        sec
        rts

; Advance the bootstrap source pointer.
BumpSrc:
        inc     SRC
        bne     :+
        inc     SRC+1
:       rts

; Fill TIB with the next line, from the built-in source if any is left,
; otherwise from the keyboard.
Refill:
        lda     SRC+1
        beq     @kbd
        lda     #0
        sta     TIBLEN
        sta     TOIN
        ; A loaded file lives on hi-res page 1, and 80STORE is set for the
        ; console -- so $2000-$3FFF follows PAGE2, which the 80-column
        ; firmware toggles on every character it prints.  Putting it back to
        ; main here, once per line, is what makes that buffer readable; the
        ; firmware sets it again for itself the next time it prints.
        bit     $C054
@copy:  ldy     #0
        lda     (SRC),y
        beq     @exhausted
        cmp     #$0D
        beq     @eol
        ldy     TIBLEN
        sta     TIB,y
        inc     TIBLEN
        jsr     BumpSrc
        jmp     @copy
@eol:   jsr     BumpSrc
        rts
@exhausted:
        ; The end of a sector, not the end of the source: no line crosses a
        ; sector boundary, so nothing has been copied into TIB yet and the
        ; next sector can simply be read and the line taken from that.
        stx     XSAV
        jsr     NextSrcSector
        ldx     XSAV
        bcs     @nomore
        jmp     Refill
@nomore:
        rts

@kbd:   lda     #$BE                    ; '>' prompt, high bit set for COUT
        sta     PROMPT
        stx     XSAV
        jsr     GETLN                   ; returns the length in X
        stx     TIBLEN
        ldx     XSAV
        lda     #0
        sta     TOIN
        ; Strip the high bit, and fold to upper case: a //e keyboard sends
        ; lower case, but every name in the dictionary is upper case.
        ldy     TIBLEN
        beq     @nostrip
@strip: dey
        lda     TIB,y
        and     #$7F
        cmp     #'a'
        bcc     @put
        cmp     #'z'+1
        bcs     @put
        sec
        sbc     #$20
@put:   sta     TIB,y
        tya
        bne     @strip
@nostrip:
        rts

; Parse the next blank-delimited word.  TMP1 := address, WORDLEN := A := length
; (zero once the line is used up).
ParseWord:
        ldy     TOIN
@skip:  cpy     TIBLEN
        bcs     @empty
        lda     TIB,y
        cmp     #' '
        bne     @start
        iny
        bne     @skip
@empty: sty     TOIN
        lda     #0
        sta     WORDLEN
        rts
@start: sty     PIDX
@scan:  iny
        cpy     TIBLEN
        bcs     @end
        lda     TIB,y
        cmp     #' '
        bne     @scan
@end:   sty     TOIN
        tya
        sec
        sbc     PIDX
        sta     WORDLEN
        clc
        lda     #<TIB
        adc     PIDX
        sta     TMP1
        lda     #>TIB
        adc     #0
        sta     TMP1+1
        lda     WORDLEN
        rts

; ---------------------------------------------------------------------------
; Hashing.  Sixteen buckets keyed on the first character plus the length --
; enough spread that a two-hundred word dictionary averages a dozen entries
; per bucket instead of two hundred.  Both hashes must agree, so they are
; written once each and nowhere else.
; ---------------------------------------------------------------------------

; A := bucket for the name at TMP1 of length WORDLEN
HashName:
        ldy     #0
        lda     (TMP1),y
        clc
        adc     WORDLEN
        and     #$0F
        rts

; A := bucket for the header at UTMP
HashHeader:
        ldy     #4
        lda     (UTMP),y
        and     #F_LENMASK
        sta     FCHR
        ldy     #5
        lda     (UTMP),y
        clc
        adc     FCHR
        and     #$0F
        rts

; ---------------------------------------------------------------------------
; BuildIndex -- thread every header into its bucket, newest first.
;
; The definition chain runs newest to oldest, and FindWord needs each bucket
; in that same order, so this appends rather than prepends and keeps a tail
; per bucket while it works.  A bucket's last entry keeps the zero link the
; assembler already put there, so nothing needs terminating.
; ---------------------------------------------------------------------------
BuildIndex:
        lda     #0
        ldy     #31
@clear: sta     BUCKETS,y
        sta     BTAILS,y
        dey
        bpl     @clear
        lda     LATESTV
        sta     UTMP
        lda     LATESTV+1
        sta     UTMP+1
@loop:  lda     UTMP
        ora     UTMP+1
        beq     @done
        jsr     HashHeader
        asl     a                       ; two bytes per bucket
        tay
        lda     BTAILS,y
        ora     BTAILS+1,y
        beq     @first
        lda     BTAILS,y                ; append: tail's bucket link := this
        sta     UTMP2
        lda     BTAILS+1,y
        sta     UTMP2+1
        sty     YSAV
        ldy     #2
        lda     UTMP
        sta     (UTMP2),y
        iny
        lda     UTMP+1
        sta     (UTMP2),y
        ldy     YSAV
        jmp     @tail
@first: lda     UTMP
        sta     BUCKETS,y
        lda     UTMP+1
        sta     BUCKETS+1,y
@tail:  lda     UTMP
        sta     BTAILS,y
        lda     UTMP+1
        sta     BTAILS+1,y
        ldy     #0                      ; on to the previous definition
        lda     (UTMP),y
        sta     FCHR
        iny
        lda     (UTMP),y
        sta     UTMP+1
        lda     FCHR
        sta     UTMP
        jmp     @loop
@done:  rts

; ---------------------------------------------------------------------------
; FindWord -- look up TMP1/WORDLEN.
; Returns A = 0 not found, 1 ordinary, $FF immediate; TMP2 = code field.
; ---------------------------------------------------------------------------
FindWord:
        jsr     HashName
        asl     a
        tay
        lda     BUCKETS,y
        sta     TMP2
        lda     BUCKETS+1,y
        sta     TMP2+1
@loop:  lda     TMP2
        ora     TMP2+1
        beq     @none
        ldy     #4
        lda     (TMP2),y
        sta     FFLAGS
        and     #F_HIDDEN
        bne     @next
        lda     FFLAGS
        and     #F_LENMASK
        cmp     WORDLEN
        bne     @next
        lda     #0
        sta     PIDX
@cmp:   lda     PIDX
        cmp     WORDLEN
        beq     @found
        clc
        adc     #5                      ; name starts at offset 5
        tay
        lda     (TMP2),y
        sta     FCHR
        ldy     PIDX
        lda     (TMP1),y
        cmp     FCHR
        bne     @next
        inc     PIDX
        bne     @cmp
@next:  ldy     #2                      ; follow the bucket link
        lda     (TMP2),y
        sta     UTMP
        iny
        lda     (TMP2),y
        sta     TMP2+1
        lda     UTMP
        sta     TMP2
        jmp     @loop
@none:  lda     #0
        rts
@found: clc                             ; code field = header + 5 + length
        lda     TMP2
        adc     #5
        sta     UTMP
        lda     TMP2+1
        adc     #0
        sta     UTMP+1
        clc
        lda     UTMP
        adc     WORDLEN
        sta     TMP2
        lda     UTMP+1
        adc     #0
        sta     TMP2+1
        lda     FFLAGS
        and     #F_IMMED
        beq     @normal
        lda     #$FF
        rts
@normal:
        lda     #1
        rts

; ---------------------------------------------------------------------------
; Number -- convert TMP1/WORDLEN.  Carry set on success, value in TMP2.
; Accepts a leading '-' and a '$' prefix for hex.
; ---------------------------------------------------------------------------
Number:
        lda     #0
        sta     TMP2
        sta     TMP2+1
        sta     NNEG
        sta     PIDX
        lda     #10
        sta     NBASE
        lda     WORDLEN
        bne     @notempty
@fail0: clc                             ; @fail is out of branch range from
        rts                             ; up here, so bail out locally
@notempty:
        ldy     #0
        lda     (TMP1),y
        cmp     #'-'
        bne     @hex
        lda     WORDLEN
        cmp     #2
        bcc     @fail0
        inc     PIDX
        lda     #1
        sta     NNEG
@hex:   ldy     PIDX
        lda     (TMP1),y
        cmp     #'$'
        bne     @loop
        lda     #16
        sta     NBASE
        inc     PIDX
        lda     PIDX
        cmp     WORDLEN
        bcs     @fail
@loop:  lda     PIDX
        cmp     WORDLEN
        bcs     @ok
        ldy     PIDX
        lda     (TMP1),y
        sec
        sbc     #'0'
        bcc     @fail
        cmp     #10
        bcc     @digit
        sbc     #7                      ; 'A'..'F' land on 10..15
        cmp     #10
        bcc     @fail                   ; ':' through '@' rejected here
@digit: cmp     NBASE
        bcs     @fail
        sta     NDIG
        lda     TMP2                    ; accumulator *= BASE, by repeated add
        sta     UTMP
        lda     TMP2+1
        sta     UTMP+1
        lda     NBASE
        sec
        sbc     #1
        sta     NCNT
@mul:   clc
        lda     TMP2
        adc     UTMP
        sta     TMP2
        lda     TMP2+1
        adc     UTMP+1
        sta     TMP2+1
        dec     NCNT
        bne     @mul
        clc
        lda     TMP2
        adc     NDIG
        sta     TMP2
        lda     TMP2+1
        adc     #0
        sta     TMP2+1
        inc     PIDX
        bne     @loop
@ok:    lda     NNEG
        beq     @done
        sec
        lda     #0
        sbc     TMP2
        sta     TMP2
        lda     #0
        sbc     TMP2+1
        sta     TMP2+1
@done:  sec
        rts
@fail:  clc
        rts

; ---------------------------------------------------------------------------
; The interpret loop
; ---------------------------------------------------------------------------
Interpret:
@next:  jsr     ParseWord
        cmp     #0
        beq     @done
        jsr     FindWord
        cmp     #0
        beq     @number
        cmp     #$FF
        beq     @exec                   ; immediate words always run
        lda     STATEV
        ora     STATEV+1
        beq     @exec
        jsr     Comma                   ; compiling: lay down the code field
        jmp     @next
@exec:  jsr     DoRun
        jmp     @next

@number:
        jsr     Number
        bcc     @err
        lda     STATEV
        ora     STATEV+1
        beq     @push
        lda     TMP2                    ; compiling: LIT <value>
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
        jmp     @next
@push:  dex
        dex
        lda     TMP2
        sta     0,x
        lda     TMP2+1
        sta     1,x
        jmp     @next

@err:   jsr     Error
@done:  rts

; Echo the offending word with a '?', then abandon the line.
Error:
        lda     #0
        sta     STATEV
        sta     STATEV+1
        ldy     #0
@l:     cpy     WORDLEN
        beq     @q
        lda     (TMP1),y
        jsr     PutChar                 ; preserves Y
        iny
        bne     @l
@q:     lda     #' '
        jsr     PutChar
        lda     #'?'
        jsr     PutChar
        stx     XSAV
        jsr     CROUT
        ldx     XSAV
        ldx     #DSTACK_TOP             ; clear the data stack
        rts

; ---------------------------------------------------------------------------
; QUIT -- the top level.  Never returns.
; ---------------------------------------------------------------------------
Quit:
@loop:  stx     XSAV                    ; empty the return stack, keep the data
        ldx     #$FF                    ; stack: it carries across lines
        txs
        ldx     XSAV
        jsr     Refill
        jsr     Interpret
        ; Guard the data stack.  A line that pops more than it pushes leaves X
        ; above the top of the stack, and the next fetch reads kernel
        ; variables as if they were data -- which ends in a wild jump rather
        ; than an error message.  Catch it here instead.
        cpx     #DSTACK_TOP+1
        bcs     @stkerr                 ; underflowed
        cpx     #DSTACK_BOT
        bcs     @depthok                ; still inside the stack
@stkerr:
        ldx     #DSTACK_TOP
        lda     #<STKSTR
        sta     TMP2
        lda     #>STKSTR
        sta     TMP2+1
        jsr     PutStr
@depthok:
        lda     STATEV
        ora     STATEV+1
        bne     @loop                   ; mid-definition: no prompt yet
        lda     SRC+1
        bne     @loop                   ; still reading the built-in source
        lda     #<OKSTR
        sta     TMP2
        lda     #>OKSTR
        sta     TMP2+1
        jsr     PutStr
        jmp     @loop

OKSTR:  .byte   "  OK", $0D, $00
STKSTR: .byte   " STACK?", $0D, $00

; ---------------------------------------------------------------------------
; Dictionary words
; ---------------------------------------------------------------------------
        prim    "HERE", W_HERE, 0
        dex
        dex
        lda     DPV
        sta     0,x
        lda     DPV+1
        sta     1,x
        NEXT

        prim    "ALLOT", W_ALLOT, 0
        clc
        lda     DPV
        adc     0,x
        sta     DPV
        lda     DPV+1
        adc     1,x
        sta     DPV+1
        inx
        inx
        NEXT

        prim    ",", W_COMMA, 0
        lda     0,x
        sta     TMP2
        lda     1,x
        sta     TMP2+1
        inx
        inx
        jsr     Comma
        NEXT

        prim    "C,", W_CCOMMA, 0
        lda     0,x
        inx
        inx
        jsr     CComma
        NEXT

; Read a line from the keyboard into a private buffer and return it.
;
; GETLN reads into TIB, which is also the outer interpreter's input buffer, so
; the text is copied straight out to INBUF and TIBLEN/TOIN are left alone.
; Whatever line invoked this word is still consumed, but nothing aliases.
        prim    "ASKLN", W_ASKLN, 0     ; -- addr len
        stx     XSAV
        jsr     GETLN                   ; length comes back in X
        stx     TMP1
        ldx     XSAV
        lda     TMP1
        cmp     #INBUFSZ
        bcc     :+
        lda     #INBUFSZ-1              ; refuse to overrun the buffer
        sta     TMP1
:       ldy     #0
@copy:  cpy     TMP1
        beq     @done
        lda     TIB,y
        and     #$7F
        sta     INBUF,y
        iny
        bne     @copy
@done:  dex
        dex
        lda     #<INBUF
        sta     0,x
        lda     #>INBUF
        sta     1,x
        dex
        dex
        lda     TMP1
        sta     0,x
        lda     #0
        sta     1,x
        NEXT

        prim    "CMOVE", W_CMOVE, 0     ; src dst count -- (count <= 255)
        lda     4,x
        sta     TMP1
        lda     5,x
        sta     TMP1+1
        lda     2,x
        sta     TMP2
        lda     3,x
        sta     TMP2+1
        lda     0,x
        sta     UTMP
        txa
        clc
        adc     #6
        tax
        ldy     #0
@l:     cpy     UTMP
        beq     @done
        lda     (TMP1),y
        sta     (TMP2),y
        iny
        bne     @l
@done:  NEXT

        prim    "'", W_TICK, 0
        jsr     ParseWord
        jsr     FindWord
        cmp     #0
        bne     :+
        lda     #0
        sta     TMP2
        sta     TMP2+1
:       dex
        dex
        lda     TMP2
        sta     0,x
        lda     TMP2+1
        sta     1,x
        NEXT

; Rebuild the hash buckets from the definition chain.  Anything that moves
; LATEST wholesale -- FORGET, or loading a precompiled overlay -- has to
; follow it with this, because the buckets are a second set of links that
; nothing else maintains.
        prim    "REINDEX", W_REINDEX, 0
        stx     XSAV
        jsr     BuildIndex
        ldx     XSAV
        NEXT

        prim    "IMMEDIATE", W_IMMEDIATE, 0
        lda     LATESTV
        sta     UTMP
        lda     LATESTV+1
        sta     UTMP+1
        ldy     #4
        lda     (UTMP),y
        ora     #F_IMMED
        sta     (UTMP),y
        NEXT

        prim    "WORDS", W_WORDS, 0
        lda     LATESTV
        sta     UTMP
        lda     LATESTV+1
        sta     UTMP+1
@loop:  lda     UTMP
        ora     UTMP+1
        beq     @done
        ldy     #4
        lda     (UTMP),y
        and     #F_LENMASK
        sta     NCNT
        lda     #0
        sta     PIDX
@ch:    lda     PIDX
        cmp     NCNT
        beq     @space
        clc
        adc     #5
        tay
        lda     (UTMP),y
        jsr     PutChar
        inc     PIDX
        bne     @ch
@space: lda     #' '
        jsr     PutChar
        ldy     #0
        lda     (UTMP),y
        sta     TMP1
        iny
        lda     (UTMP),y
        sta     UTMP+1
        lda     TMP1
        sta     UTMP
        jmp     @loop
@done:  NEXT

; ---------------------------------------------------------------------------
; Defining words
; ---------------------------------------------------------------------------
        prim    ":", W_COLON, 0
        jsr     ParseWord
        jsr     CreateHeader
        lda     #<DOCOL
        ldy     #>DOCOL
        jsr     CommaCodeField
        lda     #1
        sta     STATEV
        lda     #0
        sta     STATEV+1
        NEXT

        prim    ";", W_SEMI, F_IMMED
        lda     #<W_EXIT
        ldy     #>W_EXIT
        jsr     CommaWord
        jsr     Unhide
        lda     #0
        sta     STATEV
        sta     STATEV+1
        NEXT

        prim    "VARIABLE", W_VARIABLE, 0
        jsr     ParseWord
        jsr     CreateHeader
        lda     #<DOVAR
        ldy     #>DOVAR
        jsr     CommaCodeField
        lda     #0
        sta     TMP2
        sta     TMP2+1
        jsr     Comma
        jsr     Unhide
        NEXT

        prim    "CONSTANT", W_CONSTANT, 0
        jsr     ParseWord
        jsr     CreateHeader
        lda     #<DOCON
        ldy     #>DOCON
        jsr     CommaCodeField
        lda     0,x
        sta     TMP2
        lda     1,x
        sta     TMP2+1
        inx
        inx
        jsr     Comma
        jsr     Unhide
        NEXT

        prim    "CREATE", W_CREATE, 0
        jsr     ParseWord
        jsr     CreateHeader
        lda     #<DOVAR
        ldy     #>DOVAR
        jsr     CommaCodeField
        jsr     Unhide
        NEXT

; ---------------------------------------------------------------------------
; Compiling words.  Each is immediate and works on the data stack, holding
; the addresses of branch cells that still need patching.
; ---------------------------------------------------------------------------

; push HERE onto the data stack
PushHere:
        dex
        dex
        lda     DPV
        sta     0,x
        lda     DPV+1
        sta     1,x
        rts

; pop an address and store HERE into it
PatchHere:
        lda     0,x
        sta     UTMP
        lda     1,x
        sta     UTMP+1
        inx
        inx
        ldy     #0
        lda     DPV
        sta     (UTMP),y
        iny
        lda     DPV+1
        sta     (UTMP),y
        rts

; compile a zero placeholder cell, leaving its address on the data stack
CommaSlot:
        jsr     PushHere
        lda     #0
        sta     TMP2
        sta     TMP2+1
        jmp     Comma

; compile the popped address as a branch target
CommaPopped:
        lda     0,x
        sta     TMP2
        lda     1,x
        sta     TMP2+1
        inx
        inx
        jmp     Comma

        prim    "IF", W_IF, F_IMMED
        lda     #<W_0BRANCH
        ldy     #>W_0BRANCH
        jsr     CommaWord
        jsr     CommaSlot
        NEXT

        prim    "THEN", W_THEN, F_IMMED
        jsr     PatchHere
        NEXT

        prim    "ELSE", W_ELSE, F_IMMED
        lda     #<W_BRANCH
        ldy     #>W_BRANCH
        jsr     CommaWord
        jsr     CommaSlot               ; new slot goes on top
        lda     0,x                     ; swap it under the IF slot
        ldy     2,x
        sty     0,x
        sta     2,x
        lda     1,x
        ldy     3,x
        sty     1,x
        sta     3,x
        jsr     PatchHere               ; patches the IF slot, leaves ours
        NEXT

        prim    "BEGIN", W_BEGIN, F_IMMED
        jsr     PushHere
        NEXT

        prim    "UNTIL", W_UNTIL, F_IMMED
        lda     #<W_0BRANCH
        ldy     #>W_0BRANCH
        jsr     CommaWord
        jsr     CommaPopped
        NEXT

        prim    "AGAIN", W_AGAIN, F_IMMED
        lda     #<W_BRANCH
        ldy     #>W_BRANCH
        jsr     CommaWord
        jsr     CommaPopped
        NEXT

        prim    "WHILE", W_WHILE, F_IMMED
        lda     #<W_0BRANCH
        ldy     #>W_0BRANCH
        jsr     CommaWord
        jsr     CommaSlot
        NEXT

        prim    "REPEAT", W_REPEAT, F_IMMED
        lda     #<W_BRANCH
        ldy     #>W_BRANCH
        jsr     CommaWord
        lda     0,x                     ; ( begin while ) -- swap to reach begin
        ldy     2,x
        sty     0,x
        sta     2,x
        lda     1,x
        ldy     3,x
        sty     1,x
        sta     3,x
        jsr     CommaPopped             ; the BEGIN address
        jsr     PatchHere               ; the WHILE slot
        NEXT

        prim    "DO", W_DO, F_IMMED
        lda     #<W_PDO
        ldy     #>W_PDO
        jsr     CommaWord
        jsr     PushLVDepth             ; so LOOP knows which LEAVEs are ours
        jsr     PushHere
        NEXT

        prim    "LOOP", W_LOOP, F_IMMED
        lda     #<W_PLOOP
        ldy     #>W_PLOOP
        jsr     CommaWord
        jsr     CommaPopped
        jsr     ResolveLeaves
        NEXT

; ." <text>"  -- compile an inline string
        headlink
        .byte   2 | F_IMMED
        .byte   '.', '"'
W_DOTQUOTE:
        jsr     ParseQuoted
        lda     STATEV
        ora     STATEV+1
        beq     @now
        lda     #<W_PDOTQ
        ldy     #>W_PDOTQ
        jsr     CommaWord
        jmp     CommaCountedNext
@now:   lda     #0
        sta     NCNT
@l:     lda     NCNT
        cmp     PIDX
        beq     @done
        ldy     NCNT
        lda     SQBUF,y
        jsr     PutChar
        inc     NCNT
        bne     @l
@done:  NEXT

; \ -- ignore the rest of the line.  Spelled in bytes: ca65 string escapes
; are off, so a lone backslash is easier to state directly.
        headlink
        .byte   1 | F_IMMED
        .byte   $5C
W_BACKSLASH:
        lda     TIBLEN
        sta     TOIN
        NEXT

        prim    "BYE", W_BYE, 0
        jsr     HgrText
        jmp     MONITOR                 ; there is no DOS to go back to now
