; ---------------------------------------------------------------------------
; forth.s -- a Forth system for the Apple ][+, with a hi-res screen driver.
;
; Memory map once BRUN from DOS 3.3:
;
;   $0800-$1FFF   free (6K)  -- earmarked for window backing store
;   $2000-$3FFF   hi-res page 1, the visible screen
;   $4000-$5FFF   hi-res page 2, a back buffer for later
;   $6000-....    this kernel, then the dictionary growing upward
;   $9300-$95FF   DOS 3.3 file buffer (the greeting sets MAXFILES 1, which
;                 hands about 2K back to the dictionary)
;   $9600-$BFFF   DOS 3.3
;
; The kernel is direct-threaded: a thread cell is a code field address and
; the inner interpreter ends in JMP (W).  See dict.inc for the layout.
; ---------------------------------------------------------------------------

.include "zp.inc"
.include "dict.inc"

        .segment "STARTUP"
ColdStart:
        cld
        ldx     #$FF                    ; return stack
        txs
        ldx     #DSTACK_TOP             ; data stack
        jsr     HgrText
        stx     XSAV
        jsr     HOME
        ldx     XSAV
        lda     #<BANNER
        sta     TMP2
        lda     #>BANNER
        sta     TMP2+1
        jsr     PutStr
        lda     #<BOOTSRC               ; the interpreter reads this first,
        sta     SRC                     ; then switches to the keyboard
        lda     #>BOOTSRC
        sta     SRC+1
        jmp     Quit

        .segment "CODE"
.include "kernel.inc"
.include "interp.inc"
.include "gwords.inc"
.include "pointer.inc"
.include "hires.inc"

; ---------------------------------------------------------------------------
        .segment "RODATA"

BANNER: .byte   "APPLE ][ FORTH", $0D
        .byte   "6502 DTC KERNEL + HIRES DRIVER", $0D, $00

; The system's own source, interpreted at boot before the keyboard is read.
; Everything expressible in Forth lives here rather than in assembly.
BOOTSRC:
        .byte   ": 2DUP OVER OVER ;", $0D
        .byte   ": 2DROP DROP DROP ;", $0D
        .byte   ": > SWAP < ;", $0D
        .byte   ": <> = 0= ;", $0D
        .byte   ": ABS DUP 0< IF NEGATE THEN ;", $0D
        .byte   ": MIN 2DUP > IF SWAP THEN DROP ;", $0D
        .byte   ": MAX 2DUP < IF SWAP THEN DROP ;", $0D
        .byte   ": SPACE 32 EMIT ;", $0D
        .byte   ": /MOD U/MOD ;", $0D
        .byte   ": / U/MOD NIP ;", $0D
        .byte   ": MOD U/MOD DROP ;", $0D

        ; outline rectangle -- four edges, so the corners get named
        .byte   "VARIABLE FX1 VARIABLE FX2 VARIABLE FY1 VARIABLE FY2", $0D
        .byte   ": HFRAME FY2 ! FY1 ! FX2 ! FX1 ! ", $0D
        .byte   "  FX1 @ FX2 @ FY1 @ HLINE  FX1 @ FX2 @ FY2 @ HLINE", $0D
        .byte   "  FX1 @ FY1 @ FY2 @ HVLINE  FX2 @ FY1 @ FY2 @ HVLINE ;", $0D

        ; --- how a window looks -------------------------------------------
        ; black interior, white frame, solid title bar with a close box.
        .byte   "VARIABLE WX1 VARIABLE WX2 VARIABLE WY1 VARIABLE WY2", $0D
        .byte   ": WINDOW WY2 ! WY1 ! WX2 ! WX1 !", $0D
        .byte   "  0 HCOLOR WX1 @ WX2 @ WY1 @ WY2 @ HBOX", $0D
        .byte   "  3 HCOLOR WX1 @ WX2 @ WY1 @ WY2 @ HFRAME", $0D
        .byte   "  WX1 @ WX2 @ WY1 @ WY1 @ 8 + HBOX", $0D
        .byte   "  0 HCOLOR WX1 @ 3 + WX1 @ 9 + WY1 @ 2 + WY1 @ 6 + HBOX ;", $0D

        ; --- the window list ----------------------------------------------
        ; Four records of five cells: x1 x2 y1 y2 spare.  Array order is
        ; z-order, so the last record is the frontmost window.
        .byte   "4 CONSTANT MAXWIN", $0D
        .byte   "CREATE WINS 40 ALLOT  CREATE WTMP 10 ALLOT", $0D
        .byte   "VARIABLE NWIN", $0D
        .byte   ": W' 10 * WINS + ;", $0D
        .byte   ": .X1 W' ;  : .X2 W' 2 + ;", $0D
        .byte   ": .Y1 W' 4 + ;  : .Y2 W' 6 + ;", $0D
        .byte   "VARIABLE AX1 VARIABLE AX2 VARIABLE AY1 VARIABLE AY2", $0D
        .byte   ": ADDWIN AY2 ! AY1 ! AX2 ! AX1 !", $0D
        .byte   "  NWIN @ MAXWIN < IF", $0D
        .byte   "    AX1 @ NWIN @ .X1 !  AX2 @ NWIN @ .X2 !", $0D
        .byte   "    AY1 @ NWIN @ .Y1 !  AY2 @ NWIN @ .Y2 !", $0D
        .byte   "    1 NWIN +! THEN ;", $0D

        ; --- repainting ----------------------------------------------------
        ; There is no backing store under a window: everything is redrawn
        ; back to front, which is what makes overlap and z-order free.
        .byte   ": PAINT 5 HCOLOR 0 279 0 158 HBOX", $0D
        .byte   "  NWIN @ 0 DO", $0D
        .byte   "    I .X1 @ I .X2 @ I .Y1 @ I .Y2 @ WINDOW LOOP ;", $0D
        .byte   ": REPAINT PTRHIDE PAINT PTRSHOW ;", $0D

        ; --- hit testing ---------------------------------------------------
        .byte   "VARIABLE HX0 VARIABLE HY0 VARIABLE HN VARIABLE FOUND", $0D
        .byte   ": IN? HN !", $0D
        .byte   "  HX0 @ HN @ .X1 @ < IF 0 EXIT THEN", $0D
        .byte   "  HX0 @ HN @ .X2 @ > IF 0 EXIT THEN", $0D
        .byte   "  HY0 @ HN @ .Y1 @ < IF 0 EXIT THEN", $0D
        .byte   "  HY0 @ HN @ .Y2 @ > IF 0 EXIT THEN -1 ;", $0D
        ; front-to-back falls out of keeping the last match
        .byte   ": HIT HY0 ! HX0 ! -1 FOUND !", $0D
        .byte   "  NWIN @ 0 DO I IN? IF I FOUND ! THEN LOOP FOUND @ ;", $0D
        .byte   ": INTITLE? HN ! HY0 @ HN @ .Y1 @ 8 + > IF 0 EXIT THEN -1 ;", $0D
        .byte   ": INCLOSE? HN ! HX0 @ HN @ .X1 @ 10 + > IF 0 EXIT THEN -1 ;", $0D

        ; --- raise: shuffle a record to the end of the array ---------------
        .byte   ": RAISE DUP NWIN @ 1- < 0= IF DROP EXIT THEN", $0D
        .byte   "  DUP W' WTMP 10 CMOVE", $0D
        .byte   "  NWIN @ 1- SWAP DO I 1+ W' I W' 10 CMOVE LOOP", $0D
        .byte   "  WTMP NWIN @ 1- W' 10 CMOVE ;", $0D

        ; --- dragging ------------------------------------------------------
        .byte   "VARIABLE GRAB VARIABLE DX VARIABLE DY", $0D
        .byte   ": WSHIFT DY ! DX ! GRAB @ DUP DUP DUP", $0D
        .byte   "  DX @ SWAP .X1 +!  DX @ SWAP .X2 +!", $0D
        .byte   "  DY @ SWAP .Y1 +!  DY @ SWAP .Y2 +! ;", $0D
        .byte   ": CLOSEW -1 NWIN +! -1 GRAB ! ;", $0D

        ; A click on the title bar picks the window up; the next click drops
        ; it.  A click on the close box removes it; anywhere else just raises.
        .byte   ": CLICK GRAB @ 0< 0= IF -1 GRAB ! EXIT THEN", $0D
        .byte   "  PTRX PTRY HIT DUP 0< IF DROP EXIT THEN", $0D
        .byte   "  RAISE NWIN @ 1-", $0D
        .byte   "  DUP INTITLE? IF", $0D
        .byte   "    DUP INCLOSE? IF DROP CLOSEW REPAINT EXIT THEN", $0D
        .byte   "    GRAB ! REPAINT EXIT THEN", $0D
        .byte   "  DROP REPAINT ;", $0D

        ; --- moving the pointer, and whatever it is holding ----------------
        .byte   ": PMOVE PTRY + SWAP PTRX + SWAP PTRAT ;", $0D
        .byte   ": PSTEP 2DUP PMOVE", $0D
        .byte   "  GRAB @ 0< IF 2DROP EXIT THEN WSHIFT REPAINT ;", $0D

        ; --- the event loop ------------------------------------------------
        .byte   "6 CONSTANT STEP  VARIABLE RUNF", $0D
        .byte   ": EVENT KEYC", $0D
        .byte   "  DUP 73 = IF 0 STEP NEGATE PSTEP THEN", $0D
        .byte   "  DUP 75 = IF 0 STEP PSTEP THEN", $0D
        .byte   "  DUP 74 = IF STEP NEGATE 0 PSTEP THEN", $0D
        .byte   "  DUP 76 = IF STEP 0 PSTEP THEN", $0D
        .byte   "  DUP 32 = IF CLICK THEN", $0D
        .byte   "  DUP 77 = IF MREAD THEN", $0D
        .byte   "  81 = IF 0 RUNF ! THEN ;", $0D
        .byte   ": DESK -1 RUNF ! REPAINT", $0D
        .byte   "  BEGIN RUNF @ WHILE KEY? IF EVENT THEN REPEAT ;", $0D

        ; --- the initial screen --------------------------------------------
        .byte   ": DESKTOP HGR 0 NWIN ! -1 GRAB !", $0D
        .byte   "  20 150 12 80 ADDWIN", $0D
        .byte   "  110 250 46 116 ADDWIN", $0D
        .byte   "  60 200 86 150 ADDWIN", $0D
        .byte   "  PAINT 140 80 PTRAT ;", $0D
        .byte   ": GREET .", $22, " IJKL MOVE  SPC CLICK  Q QUIT", $22, " CR ;", $0D
        .byte   "DESKTOP GREET", $0D
        .byte   $00

; ---------------------------------------------------------------------------
        .segment "DATA"

TIBLEN:  .byte  0                       ; characters in the terminal buffer
TOIN:    .byte  0                       ; parse offset into it
WORDLEN: .byte  0                       ; length of the word just parsed
PIDX:    .byte  0                       ; general character index
NBASE:   .byte  10
NDIG:    .byte  0
NCNT:    .byte  0
NNEG:    .byte  0
FFLAGS:  .byte  0                       ; flags byte of the header being tested
FCHR:    .byte  0
NEWHDR:  .word  0                       ; header being built
STRLEN:  .word  0                       ; count byte of a compiling string
CFLO:    .byte  0
CFHI:    .byte  0
NUMBUF:  .res   8                       ; digits, emitted in reverse

PX:      .word  140                     ; pointer position
PY:      .byte  80
PVIS:    .byte  0                       ; is the arrow currently XORed in?
PCOL:    .byte  0                       ; byte column it lands in
PSHIFT:  .byte  0                       ; and how far into that byte
PROW:    .byte  0
PSH:     .word  0                       ; one shape row, shifted into place
PTMP:    .word  0

; The two-cell thread DoRun executes: the word asked for, then the primitive
; that restores IP and returns to the assembly caller.
RunSlot: .word  0
         .word  RetToAsm

; Dictionary head and free space, both resolved after every word is defined.
FINAL_LATEST = LASTHDR
KERNEL_END:
