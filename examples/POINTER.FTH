\ POINTER.FTH -- a pointer, an event queue and hit testing.
\
\ Framework rather than kernel: it lives on the disk, is compiled when you
\ want it, and FORGET PTR-- gives every byte back.  With MARK before and
\ SAVEDICT after it keeps as a precompiled overlay instead, which loads at
\ disk speed rather than recompiling.
\
\ WHAT IS NOT HERE.  The AppleMouse II card needs four ROMs this project has
\ not been able to reconstruct, so MOUSE-READ and its family could be written
\ but not run.  Everything below therefore goes through PTR-XY, which reads
\ whichever source is selected -- the game port today, the mouse card when
\ its ROMs turn up -- without a single caller changing.
\
\ Type PTR-DEMO.  FORGET PTR-- to reclaim the space.

: PTR-- ;

\ --- sources ---------------------------------------------------------------
\ An unconnected game port floats high, so 255 on both axes is taken to mean
\ nothing is plugged in.  It is a guess; the port cannot be interrogated.
$C062 CONSTANT BUTN1
: JOY-BTN0 ( -- f ) BTN ;
: JOY-BTN1 ( -- f ) BUTN1 C@ 127 > ;
: JOY-XY ( -- rx ry ) 0 PADDLE 1 PADDLE ;
: JOY? ( -- f ) JOY-XY 255 = SWAP 255 = AND 0= ;

0 CONSTANT PTR-NONE   1 CONSTANT PTR-MOUSE
2 CONSTANT PTR-JOY    3 CONSTANT PTR-KBD

VARIABLE PSRC   PTR-JOY PSRC !
VARIABLE PX     VARIABLE PY
: PTR-SRC! ( n -- ) PSRC ! ;
: PTR-SRC@ ( -- n ) PSRC @ ;
: PTR-POS! ( x y -- ) PY ! PX ! ;

\ The port reads 0..255 per axis and the screen is 560 by 192, so x is 17/8
\ of the reading and y is 3/4.  */ keeps the intermediate in 32 bits, which
\ 17 * 255 does not fit in.
: JOY-SCALE ( rx ry -- x y ) 3 4 */ SWAP 17 8 */ SWAP ;
: PTR-XY ( -- x y )
  PSRC @ PTR-JOY = IF JOY-XY JOY-SCALE PTR-POS! THEN
  PX @ PY @ ;
: PTR-BTN ( -- f ) PSRC @ PTR-JOY = IF JOY-BTN0 ELSE 0 THEN ;

\ Arrows move and Return clicks, for a machine with no pointing device.
\ True means it produced a click.
: KBD-PTR ( -- f )
  KEY? 0= IF 0 EXIT THEN
  KEYC
  DUP 8 = IF DROP PX @ 8 - 0 MAX PX ! 0 EXIT THEN
  DUP 21 = IF DROP PX @ 8 + 559 MIN PX ! 0 EXIT THEN
  DUP 11 = IF DROP PY @ 8 - 0 MAX PY ! 0 EXIT THEN
  DUP 10 = IF DROP PY @ 8 + 191 MIN PY ! 0 EXIT THEN
  13 = ;

\ --- coordinates -----------------------------------------------------------
\ A character cell is 7 pixels by 8 on the graphics screen, which is what the
\ pointer measures in.
: >CELL ( x y -- col row ) 8 / SWAP 7 / SWAP ;
: CELL> ( col row -- x y ) 8 * SWAP 7 * SWAP ;

VARIABLE CIX VARIABLE CIY VARIABLE CIC VARIABLE CIR
VARIABLE CIW VARIABLE CIH
: CLICK-IN? ( x y col row w h -- f )
  CIH ! CIW ! CIR ! CIC ! CIY ! CIX !
  CIX @ CIC @ 7 * < IF 0 EXIT THEN
  CIX @ CIC @ CIW @ + 7 * < 0= IF 0 EXIT THEN
  CIY @ CIR @ 8 * < IF 0 EXIT THEN
  CIY @ CIR @ CIH @ + 8 * < 0= IF 0 EXIT THEN
  -1 ;

\ --- events ----------------------------------------------------------------
0 CONSTANT EV-NONE   1 CONSTANT EV-KEYP   2 CONSTANT EV-DOWN
3 CONSTANT EV-UP     4 CONSTANT EV-MOVE
8 CONSTANT EVMAX
CREATE EVQ EVMAX 8 * ALLOT
VARIABLE EVH VARIABLE EVT
: EV ( n -- addr ) 8 * EVQ + ;
: EV-TYPE ( ev -- n ) @ ;
: EV-XY ( ev -- x y ) DUP 2 + @ SWAP 4 + @ ;
: EV-KEY ( ev -- c ) 6 + @ ;
: EV-FLUSH ( -- ) 0 EVH ! 0 EVT ! ;
: EVENT? ( -- f ) EVH @ EVT @ <> ;
: EV+ ( n -- n ) 1+ EVMAX MOD ;
: EV-PUT ( type x y key -- )
  EVH @ EV
  TUCK 6 + !  TUCK 4 + !  TUCK 2 + !  !
  EVH @ EV+ EVH ! ;
: EV-GET ( -- ev ) EVT @ EV  EVT @ EV+ EVT ! ;
: EV-PUSH ( ev -- ) DROP EVT @ DUP 0= IF DROP EVMAX THEN 1- EVT ! ;

VARIABLE LASTB VARIABLE LASTX VARIABLE LASTY
VARIABLE GX VARIABLE GY VARIABLE GB
: EV-GEN ( -- )
  KEY? IF EV-KEYP 0 0 KEYC EV-PUT EXIT THEN
  PTR-XY GY ! GX !  PTR-BTN GB !
  GB @ LASTB @ <> IF
    GB @ LASTB !
    GB @ IF EV-DOWN ELSE EV-UP THEN GX @ GY @ 0 EV-PUT EXIT THEN
  GX @ LASTX @ <> GY @ LASTY @ <> OR IF
    GX @ LASTX !  GY @ LASTY !
    EV-MOVE GX @ GY @ 0 EV-PUT THEN ;
: EVENT-POLL ( -- ev )
  EVENT? 0= IF EV-GEN THEN
  EVENT? IF EV-GET ELSE 0 THEN ;

\ --- hit testing -----------------------------------------------------------
16 CONSTANT HOTMAX
CREATE HOTS HOTMAX 10 * ALLOT
VARIABLE NHOT
: HOT ( n -- addr ) 10 * HOTS + ;
: HOT-CLEAR ( -- ) 0 NHOT ! ;
: HOT-ADD ( col row w h xt -- )
  NHOT @ HOTMAX < IF
    NHOT @ HOT
    TUCK 8 + !  TUCK 6 + !  TUCK 4 + !  TUCK 2 + !  !
    1 NHOT +!
  ELSE DROP DROP DROP DROP DROP THEN ;

VARIABLE HFX VARIABLE HFY VARIABLE HFR VARIABLE HA
: HOT-FIND ( x y -- xt f )
  HFY ! HFX ! 0 HFR !
  NHOT @ 0 ?DO
    HFR @ 0= IF
      I HOT HA !
      HFX @ HFY @ HA @ @ HA @ 2 + @ HA @ 4 + @ HA @ 6 + @ CLICK-IN?
      IF HA @ 8 + @ HFR ! THEN
    THEN
  LOOP
  HFR @ DUP 0<> ;
: HOT-TEST ( ev -- f )
  DUP EV-TYPE EV-DOWN = 0= IF DROP 0 EXIT THEN
  EV-XY HOT-FIND IF EXECUTE -1 ELSE DROP 0 THEN ;

\ --- a demonstration -------------------------------------------------------
: PTR-DEMO
  ." MOVE THE STICK.  BUTTON REPORTS.  ANY KEY QUITS." CR
  EV-FLUSH
  BEGIN
    EVENT-POLL ?DUP IF
      DUP EV-TYPE
      DUP EV-KEYP = IF DROP DROP EXIT THEN
      DUP EV-DOWN = IF ." DOWN AT " OVER EV-XY SWAP . . CR THEN
      DUP EV-UP   = IF ." UP" CR THEN
      DROP DROP
    THEN
  0 UNTIL ;

." LOADED.  TYPE PTR-DEMO" CR
