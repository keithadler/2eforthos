; ---------------------------------------------------------------------------
; hello.s -- "Hello, world" for the Apple ][+ , in 6502 machine code.
;
; Output goes through COUT, the monitor ROM's character-out vector.  COUT
; expects the character in the accumulator with the high bit SET -- the
; Apple II's text screen uses "high ASCII", so $C8 is 'H', not $48.
; ---------------------------------------------------------------------------

COUT    = $FDED                 ; monitor ROM: print A to the current output
DOSWARM = $03D0                 ; DOS 3.3 re-entry vector (JMP into DOS)

; Emit a string as high-ASCII, the way the Apple II wants it.
.macro  ascii_hi str
        .repeat .strlen(str), i
                .byte .strat(str, i) | $80
        .endrep
.endmacro

        .segment "STARTUP"      ; entry point -> lands at the load address

start:
        ldy     #$00            ; index into the message
loop:
        lda     msg,y           ; next character
        beq     done            ; $00 terminates
        jsr     COUT            ; print it
        iny
        bne     loop            ; (message is well under 256 bytes)
done:
.ifdef  DOS
        ; BRUN loads us over the Applesoft greeting program, so there is no
        ; sane BASIC program left to RTS back into.  Hand control to DOS.
        jmp     DOSWARM
.else
        rts                     ; poked in by hand: just return to the monitor
.endif

msg:
        ascii_hi "HELLO, WORLD!"
        .byte   $8D             ; carriage return (high bit set)
        .byte   $00             ; terminator
