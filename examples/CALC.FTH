\ CALC.FTH -- a grid of numbers you move around with the arrow keys.
\
\ VisiCalc is what made people buy an Apple II, and a spreadsheet was the
\ one AppleWorks application this had no answer to.  Six columns by
\ twelve rows, the cursor moved with the arrows, a number typed straight
\ in, and a total under every column and beside every row.
\
\ Whole numbers, not floats.  A column of money adds up exactly in
\ integers and does not in five-byte floating point, which is the
\ argument LEDGER makes too: floating point is for curves.
\
\ Everything here is its own -- the number reader, the string writer, the
\ typing line -- because a file cannot LOAD another file: LOAD points the
\ interpreter at the new source and the rest of the old one is never
\ read.  CPUT and CINV are the kernel's, so those are shared.
\
\ CALC runs it.  Arrows move, RETURN types a number in, Z zeroes a cell,
\ ESC leaves.

: CALC-- ;

6 CONSTANT NCOL   12 CONSTANT NROW
10 CONSTANT CW                          \ how wide a column prints
CREATE CDATA NCOL NROW * CELLS ALLOT
VARIABLE CX VARIABLE CY VARIABLE CK

\ ALLOT does not promise zeros, and a grid that comes up holding whatever
\ the last program left in the dictionary is not an empty grid.  LIFE
\ learned this the same way, with a row of debris along its border.
: CCLR ( -- ) CDATA NCOL NROW * CELLS 0 FILL ;

: CADR ( c r -- addr ) NCOL * + CELLS CDATA + ;
: CGET ( c r -- n ) CADR @ ;
: CSET ( n c r -- ) CADR ! ;

\ --- writing on the console ------------------------------------------------
VARIABLE KA VARIABLE KL VARIABLE KC VARIABLE KR
: KTYPE ( addr len col row -- )
  KR ! KC ! KL ! KA !
  KL @ 0 ?DO
    KA @ I + C@ 127 AND  KC @ I +  KR @  CPUT
  LOOP ;
: KBLANK ( n col row -- )
  KR ! KC ! 0 ?DO 32 KC @ I + KR @ CPUT LOOP ;

\ Right-aligned, the way a column of numbers wants to be.
VARIABLE KP
: KNUM ( n col row -- )
  KR ! KC !
  DUP ABS 0 <# #S ROT SIGN #>           ( addr len )
  DUP CW 1- SWAP - 0 MAX KC @ + KP !    \ where it starts, to end flush
  KP @ KR @ KTYPE ;

\ --- where things sit ------------------------------------------------------
: COLX ( c -- x ) CW * 4 + ;
: ROWY ( r -- y ) 3 + ;

VARIABLE DC VARIABLE DR
: CDRAW1 ( c r -- )
  DR ! DC !
  DC @ CX @ = DR @ CY @ = AND IF -1 ELSE 0 THEN CINV
  CW DC @ COLX DR @ ROWY KBLANK
  DC @ DR @ CGET  DC @ COLX  DR @ ROWY  KNUM
  0 CINV ;

: CHEAD ( -- )
  0 CINV
  NCOL 0 DO
    65 I +  I COLX CW 1- +  1  CPUT
  LOOP
  NROW 0 DO
    I 1+ 0 <# #S #>  1  I ROWY  KTYPE
  LOOP ;

: CSUMC ( c -- n ) 0 NROW 0 DO OVER I CGET + LOOP NIP ;
: CSUMR ( r -- n ) 0 NCOL 0 DO I 2 PICK CGET + LOOP NIP ;

: CTOTS ( -- )
  0 CINV
  S" TOT" 0 NROW ROWY KTYPE
  NCOL 0 DO
    CW I COLX NROW ROWY KBLANK
    I CSUMC  I COLX  NROW ROWY  KNUM
  LOOP
  NROW 0 DO
    CW NCOL COLX I ROWY KBLANK
    I CSUMR  NCOL COLX  I ROWY  KNUM
  LOOP
  CW NCOL COLX NROW ROWY KBLANK
  0 CSUMC 1 CSUMC + 2 CSUMC + 3 CSUMC + 4 CSUMC + 5 CSUMC +
  NCOL COLX NROW ROWY KNUM ;

: CDRAW ( -- )
  PAGE
  S" CALC    ARROWS MOVE   RETURN ENTERS   Z ZEROES   ESC LEAVES" 0 0 KTYPE
  CHEAD
  NROW 0 DO NCOL 0 DO I J CDRAW1 LOOP LOOP
  CTOTS ;

\ --- typing a number in ----------------------------------------------------
\ Its own line reader rather than ASKLN, because ASKLN echoes wherever the
\ console cursor happens to be and that is somewhere in the middle of the
\ grid.  This echoes where it is told to.
CREATE EBUF 12 ALLOT
VARIABLE ELEN VARIABLE EA VARIABLE EL VARIABLE EN VARIABLE ES

: E>N ( addr len -- n ok )
  EL ! EA ! 0 EN ! 0 ES !
  EL @ 0= IF 0 0 EXIT THEN
  EA @ C@ 45 = IF 1 ES ! 1 EA +! -1 EL +! THEN
  EL @ 0= IF 0 0 EXIT THEN
  EL @ 0 ?DO
    EA @ I + C@ 127 AND
    DUP 48 < OVER 57 > OR IF DROP 0 0 UNLOOP EXIT THEN
    48 - EN @ 10 * + EN !
  LOOP
  EN @ ES @ IF NEGATE THEN -1 ;

: EGET ( -- addr len ok )
  0 ELEN !
  60 0 22 KBLANK
  S" VALUE? " 0 22 KTYPE
  BEGIN
    BEGIN KEY? UNTIL KEYC
    DUP 13 = IF DROP EBUF ELEN @ -1 EXIT THEN
    DUP 27 = IF DROP 0 0 0 EXIT THEN
    DUP 8 = IF DROP
      ELEN @ 0> IF -1 ELEN +! 32 8 ELEN @ + 22 CPUT THEN
    ELSE
      DUP 32 > ELEN @ 10 < AND IF
        DUP EBUF ELEN @ + C!
        DUP 8 ELEN @ + 22 CPUT
        1 ELEN +!
      THEN DROP
    THEN
  0 UNTIL ;

: CENTRY ( -- )
  EGET IF E>N IF CX @ CY @ CSET ELSE DROP THEN ELSE 2DROP THEN
  60 0 22 KBLANK
  CX @ CY @ CDRAW1 CTOTS ;

\ --- the loop --------------------------------------------------------------
\ Only the two cells that changed are redrawn when the cursor moves.
\ Repainting seventy-two of them for every keypress is a visible sweep
\ down the screen at one megahertz.
VARIABLE OX VARIABLE OY
: CMOVE1 ( -- ) OX @ OY @ CDRAW1  CX @ CY @ CDRAW1 ;
: CSAVE ( -- ) CX @ OX ! CY @ OY ! ;

: CALC ( -- )
  0 CX ! 0 CY ! CDRAW
  BEGIN
    BEGIN KEY? UNTIL KEYC DUP CK !
    CASE
      8  OF CSAVE CX @ 1- 0 MAX CX ! CMOVE1 ENDOF
      21 OF CSAVE CX @ 1+ NCOL 1- MIN CX ! CMOVE1 ENDOF
      11 OF CSAVE CY @ 1- 0 MAX CY ! CMOVE1 ENDOF
      10 OF CSAVE CY @ 1+ NROW 1- MIN CY ! CMOVE1 ENDOF
      13 OF CENTRY ENDOF
      90 OF 0 CX @ CY @ CSET CX @ CY @ CDRAW1 CTOTS ENDOF
    ENDCASE
    CK @ 27 =
  UNTIL
  PAGE ." CALC LEFT.  THE NUMBERS ARE STILL THERE -- CALC AGAIN." CR ;

CCLR
: CALCHELP ." CALC RUNS THE GRID.  ARROWS, RETURN, Z, ESC." CR ;
CALCHELP
