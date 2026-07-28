\ ===========================================================================
\ system.fth -- 2E FORTH OS, the part of the system written in Forth
\
\ Interpreted at boot, before the keyboard is read.  Definitions must appear
\ before their first use, so the order here is: primitives' helpers, shapes,
\ the window list, disk, text, the explorer, painting, input, and finally the
\ boot sequence itself on the last line.
\
\ Comments and blank lines are stripped by tools/mkboot.py -- they cost both
\ image space and boot time, since every token is looked up by linear search.
\ ===========================================================================

\ --- words the kernel leaves to Forth --------------------------------------
: 2DUP OVER OVER ;
: 2DROP DROP DROP ;
: > SWAP < ;
: <> = 0= ;
: 0> 0 SWAP < ;
: ABS DUP 0< IF NEGATE THEN ;
: MIN 2DUP > IF SWAP THEN DROP ;
: MAX 2DUP < IF SWAP THEN DROP ;
: SPACE 32 EMIT ;
: /MOD U/MOD ;
: / U/MOD NIP ;
: MOD U/MOD DROP ;

\ --- shapes ----------------------------------------------------------------
VARIABLE FX1 VARIABLE FX2 VARIABLE FY1 VARIABLE FY2
: HFRAME FY2 ! FY1 ! FX2 ! FX1 !
  FX1 @ FX2 @ FY1 @ HLINE  FX1 @ FX2 @ FY2 @ HLINE
  FX1 @ FY1 @ FY2 @ HVLINE  FX2 @ FY1 @ FY2 @ HVLINE ;

\ black interior, white frame, title bar with a close box
VARIABLE WX1 VARIABLE WX2 VARIABLE WY1 VARIABLE WY2
: WINDOW WY2 ! WY1 ! WX2 ! WX1 !
  0 HCOLOR WX1 @ WX2 @ WY1 @ WY2 @ HBOX
  3 HCOLOR WX1 @ WX2 @ WY1 @ WY2 @ HFRAME
  WX1 @ WX2 @ WY1 @ WY1 @ 8 + HBOX
  0 HCOLOR WX1 @ 3 + WX1 @ 9 + WY1 @ 2 + WY1 @ 6 + HBOX ;

\ --- the window list -------------------------------------------------------
\ Array order is z-order: the last record is the frontmost window.
4 CONSTANT MAXWIN
CREATE WINS 40 ALLOT  CREATE WTMP 10 ALLOT
VARIABLE NWIN
: W' 10 * WINS + ;
: .X1 W' ;  : .X2 W' 2 + ;
: .Y1 W' 4 + ;  : .Y2 W' 6 + ;
VARIABLE AX1 VARIABLE AX2 VARIABLE AY1 VARIABLE AY2
: ADDWIN AY2 ! AY1 ! AX2 ! AX1 !
  NWIN @ MAXWIN < IF
    AX1 @ NWIN @ .X1 !  AX2 @ NWIN @ .X2 !
    AY1 @ NWIN @ .Y1 !  AY2 @ NWIN @ .Y2 !
    1 NWIN +! THEN ;

\ --- the DOS 3.3 catalog ---------------------------------------------------
\ SECBUF takes one raw sector; CATBUF holds the parsed catalog as 36-byte
\ records: type, size, then where the entry came from (catalog track, sector
\ and byte offset) so it can be written back, then the 30-char name.
$0800 CONSTANT SECBUF  $1000 CONSTANT CATBUF
$0900 CONSTANT VTOCBUF  $0A00 CONSTANT TSBUF
VARIABLE NFILE VARIABLE CTRK VARIABLE CSEC VARIABLE ESRC
: CATENT 36 * CATBUF + ;
: CATADD ESRC !
  NFILE @ 60 < IF
    ESRC @ 2 + C@ NFILE @ CATENT C!
    ESRC @ 33 + C@ NFILE @ CATENT 1+ C!
    CTRK @ NFILE @ CATENT 2 + C!
    CSEC @ NFILE @ CATENT 3 + C!
    ESRC @ SECBUF - NFILE @ CATENT 4 + C!
    ESRC @ 3 + NFILE @ CATENT 6 + 30 CMOVE
    1 NFILE +! THEN ;

\ VTOC is track 17 sector 0 and names the first catalog sector; each catalog
\ sector names the next.  A $00 first byte ends the catalog, $FF is a
\ deleted entry.
: CATLOAD 0 NFILE !
  17 0 SECBUF DREAD DROP
  SECBUF 1+ C@ CTRK !  SECBUF 2 + C@ CSEC !
  BEGIN CTRK @ WHILE
    CTRK @ CSEC @ SECBUF DREAD DROP
    7 0 DO SECBUF 11 + I 35 * +
      DUP C@ 0= IF DROP ELSE
      DUP C@ 255 = IF DROP ELSE CATADD THEN THEN LOOP
    SECBUF 1+ C@ CTRK !  SECBUF 2 + C@ CSEC !
  REPEAT ;

\ free sectors, counted out of the VTOC's four-byte-per-track bitmap
: BITS 0 SWAP 8 0 DO DUP 1 AND ROT + SWAP 2/ LOOP DROP ;
: FREE 17 0 SECBUF DREAD DROP 0
  35 0 DO SECBUF 56 + I 4 * +
    DUP C@ BITS SWAP 1+ C@ BITS + + LOOP ;

\ --- text on the graphics screen -------------------------------------------
: TTYPE 0 DO DUP I + C@ 127 AND TEMIT LOOP DROP ;
: TDIG 48 + TEMIT ;
: T3 DUP 100 / TDIG DUP 10 / 10 MOD TDIG 10 MOD TDIG ;
\ Signed, no leading zeros: digits come out backwards so they go to a buffer
\ first.  T3 above is fixed-width for the size column; this is for the
\ calculator, where 7 and 1000000 must both look right.
CREATE NBUF 8 ALLOT  VARIABLE NLEN
: T# DUP 0< IF 45 TEMIT NEGATE THEN
  0 NLEN !
  BEGIN 10 U/MOD SWAP 48 + NBUF NLEN @ + C! 1 NLEN +! DUP 0= UNTIL DROP
  NLEN @ 0 DO NBUF NLEN @ 1- I - + C@ TEMIT LOOP ;

: FTYPE 127 AND
  DUP 4 = IF DROP 66 EXIT THEN
  DUP 2 = IF DROP 65 EXIT THEN
  DUP 1 = IF DROP 73 EXIT THEN
  DUP 0= IF DROP 84 EXIT THEN DROP 63 ;

\ --- the explorer ----------------------------------------------------------
\ Window 0 is the file browser.  Its text grid is derived from the window
\ rectangle rather than fixed, so it stays correct wherever the window is.
VARIABLE ESEL VARIABLE ETOP VARIABLE NFREE
VARIABLE ECOL VARIABLE EROW VARIABLE EROWS VARIABLE ETROW
\ The window's top edge is a multiple of 8, so its title bar lines up exactly
\ with a text row: title on ETROW, column header two below, list from there.
: EGEOM 0 .X1 @ 5 + 7 / ECOL !
  0 .Y1 @ 8 / ETROW !
  ETROW @ 3 + EROW !
  0 .Y2 @ 0 .Y1 @ - 24 - 8 / EROWS ! ;
: ELINE DUP ETOP @ - EROW @ + ECOL @ SWAP TAT
  DUP ESEL @ = TINV
  DUP CATENT C@ 128 AND IF 42 ELSE 32 THEN TEMIT
  DUP CATENT 6 + 30 TTYPE 32 TEMIT
  DUP CATENT C@ FTYPE TEMIT 32 TEMIT
  CATENT 1+ C@ T3 32 TEMIT 0 TINV ;
: EXPLORER EGEOM
  ECOL @ ETROW @ TAT -1 TINV T." DISK CATALOG" 0 TINV
  ECOL @ EROW @ 1- TAT T."  NAME                           T SIZ "
  NFILE @ ETOP @ - EROWS @ MIN
  DUP 0> IF 0 DO ETOP @ I + ELINE LOOP ELSE DROP THEN ;
: ESCROLL EGEOM ETOP @ + DUP 0< IF DROP 0 THEN
  NFILE @ EROWS @ - 0 MAX MIN ETOP ! ;
: EPICK EGEOM PTRY 8 / EROW @ - ETOP @ +
  DUP 0< IF DROP EXIT THEN
  DUP NFILE @ < IF ESEL ! ELSE DROP THEN ;

\ Toggle the lock bit of the selected file and write the catalog sector back.
\ This is the only thing in the system that writes to the disk.
VARIABLE FA
: FLOCK NFILE @ 0= IF EXIT THEN
  ESEL @ CATENT FA !
  FA @ 2 + C@ FA @ 3 + C@ SECBUF DREAD DROP
  SECBUF FA @ 4 + C@ + 2 +
  DUP C@ 128 XOR SWAP C!
  FA @ 2 + C@ FA @ 3 + C@ SECBUF DWRITE DROP
  CATLOAD ;

\ A DO LOOP always runs once, so a zero shift count needs guarding.
: 1<< 1 SWAP DUP 0> IF 0 DO 2* LOOP ELSE DROP THEN ;

\ Mark one sector free in the VTOC image held in VTOCBUF.  Four bytes per
\ track: byte 0 covers sectors 15-8, byte 1 covers 7-0, a set bit means free.
VARIABLE FT VARIABLE FS VARIABLE FB
: FREESEC FS ! FT !
  FT @ 4 * 56 + VTOCBUF + FB !
  FS @ 8 < IF
    FB @ 1+ DUP C@ FS @ 1<< OR SWAP C!
  ELSE
    FB @ DUP C@ FS @ 8 - 1<< OR SWAP C!
  THEN ;

\ Walk a file's track/sector list, freeing every data sector it names and
\ then the list sectors themselves.  Track 0 is DOS and is never allocated
\ to a file, so a zero track byte means an unused slot.
VARIABLE TLT VARIABLE TLS
: FREEFILE TLS ! TLT !
  BEGIN TLT @ WHILE
    TLT @ TLS @ TSBUF DREAD DROP
    122 0 DO TSBUF 12 + I 2* +
      DUP C@ 0= IF DROP ELSE
      DUP C@ SWAP 1+ C@ FREESEC THEN LOOP
    TSBUF 1+ C@ TSBUF 2 + C@
    TLT @ TLS @ FREESEC
    TLS ! TLT !
  REPEAT ;

\ Delete: free the sectors, then mark the catalog entry the way DOS does --
\ the first track byte moves to the last byte of the name and $FF takes its
\ place.  Locked files are refused, which is what the lock is for.
: FDEL NFILE @ 0= IF EXIT THEN
  ESEL @ CATENT C@ 128 AND IF EXIT THEN
  ESEL @ CATENT FA !
  17 0 VTOCBUF DREAD DROP
  FA @ 2 + C@ FA @ 3 + C@ SECBUF DREAD DROP
  SECBUF FA @ 4 + C@ +
  DUP C@ OVER 1+ C@ FREEFILE
  DUP C@ OVER 32 + C!
  255 SWAP C!
  FA @ 2 + C@ FA @ 3 + C@ SECBUF DWRITE DROP
  17 0 VTOCBUF DWRITE DROP
  CATLOAD FREE NFREE !
  ESEL @ NFILE @ < 0= IF 0 ESEL ! THEN ;

\ Rename: names are stored high-bit set and space padded to 30 characters.
VARIABLE NADR VARIABLE NLEN VARIABLE NDST
: FREN NFILE @ 0= IF EXIT THEN
  ESEL @ CATENT FA !
  ." NAME? " ASKLN NLEN ! NADR !
  NLEN @ 0= IF EXIT THEN
  NLEN @ 30 > IF 30 NLEN ! THEN
  FA @ 2 + C@ FA @ 3 + C@ SECBUF DREAD DROP
  SECBUF FA @ 4 + C@ + 3 + NDST !
  30 0 DO 160 NDST @ I + C! LOOP
  NLEN @ 0 DO NADR @ I + C@ 128 OR NDST @ I + C! LOOP
  FA @ 2 + C@ FA @ 3 + C@ SECBUF DWRITE DROP
  CATLOAD ;

\ --- the menu bar ----------------------------------------------------------
: MENUBAR 3 HCOLOR 0 559 0 9 HBOX
  0 0 TAT -1 TINV T." 2E FORTH OS  V0.5"
  67 0 TAT T." FREE " NFREE @ T3 0 TINV ;

\ --- desktop icons ---------------------------------------------------------
\ Four bytes each: byte column, top raster row, which bitmap, and what a
\ double click opens.  Icons sit on even byte columns because a 14-pixel icon
\ is two screen bytes and lands there without shifting.
3 CONSTANT NICON
CREATE ICONS
  70 C, 24 C, 0 C, 1 C,
  70 C, 64 C, 1 C, 2 C,
  70 C, 104 C, 2 C, 3 C,
: IREC 4 * ICONS + ;
: I.COL IREC C@ ;
: I.ROW IREC 1+ C@ ;
: I.PIC IREC 2 + C@ ;
: I.ACT IREC 3 + C@ ;
VARIABLE ISEL
: ILABEL DUP I.COL OVER I.ROW 16 + 8 / TAT
  DUP ISEL @ = TINV
  I.PIC DUP 0 = IF DROP T." CALC" ELSE
        DUP 1 = IF DROP T." DISK" ELSE DROP T." INFO" THEN THEN
  0 TINV ;
: DRAWICONS NICON 0 DO I I.COL I I.ROW I I.PIC ICON I ILABEL LOOP ;
VARIABLE IFOUND
: ICONHIT -1 IFOUND !
  NICON 0 DO
    PTRX I I.COL 7 * < 0=
    PTRX I I.COL 7 * 14 + < AND
    PTRY I I.ROW < 0= AND
    PTRY I I.ROW 24 + < AND
    IF I IFOUND ! THEN LOOP IFOUND @ ;

\ Broken cycles: PAINT must redraw the calculator, but the calculator needs
\ REPAINT, which needs PAINT.  Likewise CLICK opens an application defined
\ further down.  Both go through a vector that is filled in later.
VARIABLE CALCON
VARIABLE 'CDRAW  VARIABLE 'OPEN
: DRAWCALC 'CDRAW @ DUP IF EXECUTE ELSE DROP THEN ;
: OPENAPP 'OPEN @ DUP IF EXECUTE ELSE 2DROP THEN ;

\ --- painting --------------------------------------------------------------
\ No backing store: everything is redrawn back to front, which is what makes
\ overlap and z-order free.
: PAINT 2 HCOLOR 0 559 0 191 HBOX MENUBAR
  NWIN @ 0 DO
    I .X1 @ I .X2 @ I .Y1 @ I .Y2 @ WINDOW
    I 0= IF EXPLORER THEN LOOP
  DRAWICONS
  CALCON @ IF DRAWCALC THEN ;
: REPAINT PTRHIDE PAINT PTRSHOW ;

\ --- hit testing -----------------------------------------------------------
VARIABLE HX0 VARIABLE HY0 VARIABLE HN VARIABLE FOUND
: IN? HN !
  HX0 @ HN @ .X1 @ < IF 0 EXIT THEN
  HX0 @ HN @ .X2 @ > IF 0 EXIT THEN
  HY0 @ HN @ .Y1 @ < IF 0 EXIT THEN
  HY0 @ HN @ .Y2 @ > IF 0 EXIT THEN -1 ;
: HIT HY0 ! HX0 ! -1 FOUND !
  NWIN @ 0 DO I IN? IF I FOUND ! THEN LOOP FOUND @ ;
: INTITLE? HN ! HY0 @ HN @ .Y1 @ 8 + > IF 0 EXIT THEN -1 ;
: INCLOSE? HN ! HX0 @ HN @ .X1 @ 10 + > IF 0 EXIT THEN -1 ;

\ --- raise: shuffle a record to the end of the array ------------------------
: RAISE DUP NWIN @ 1- < 0= IF DROP EXIT THEN
  DUP W' WTMP 10 CMOVE
  NWIN @ 1- SWAP DO I 1+ W' I W' 10 CMOVE LOOP
  WTMP NWIN @ 1- W' 10 CMOVE ;

\ --- dragging and clicking -------------------------------------------------
VARIABLE GRAB VARIABLE DX VARIABLE DY
: WSHIFT DY ! DX ! GRAB @ DUP DUP DUP
  DX @ SWAP .X1 +!  DX @ SWAP .X2 +!
  DY @ SWAP .Y1 +!  DY @ SWAP .Y2 +! ;
: CLOSEW -1 NWIN +! -1 GRAB ! ;

\ Two clicks close together in time and place.  There is no clock in this
\ machine, so "close in time" is counted in event loop passes -- roughly 150
\ a second, which makes 40 about a quarter of a second.
VARIABLE LASTCLK VARIABLE LASTCX VARIABLE LASTCY
\ Counted in event loop passes, of which there are on the order of a hundred
\ and fifty a second.  A whole-desktop repaint is a single pass that takes
\ half a second, which is why selecting an icon redraws only the icons: a
\ repaint between the two clicks stalls the count and swallows the second
\ keypress before the loop can read it.
150 CONSTANT DCLICK
: NEAR? - ABS 14 < ;
: DOUBLE? TICKS LASTCLK @ - DCLICK <
  PTRX LASTCX @ NEAR? AND
  PTRY LASTCY @ NEAR? AND ;
: MARKCLK TICKS LASTCLK ! PTRX LASTCX ! PTRY LASTCY ! ;

\ Window 0 is the explorer: clicking it selects a file rather than raising or
\ dragging, which is also why it never leaves the back of the z-order.
: CLICK GRAB @ 0< 0= IF -1 GRAB ! EXIT THEN
  ICONHIT DUP 0< 0= IF
    DUP ISEL !
    DOUBLE? IF I.ACT OPENAPP ELSE DROP PTRHIDE DRAWICONS PTRSHOW THEN
    MARKCLK EXIT THEN
  DROP MARKCLK
  PTRX PTRY HIT DUP 0< IF DROP EXIT THEN
  DUP 0= IF DROP EPICK REPAINT EXIT THEN
  RAISE NWIN @ 1-
  DUP INTITLE? IF
    DUP INCLOSE? IF DROP CLOSEW REPAINT EXIT THEN
    GRAB ! REPAINT EXIT THEN
  DROP REPAINT ;

: PMOVE PTRY + SWAP PTRX + SWAP PTRAT ;
: PSTEP 2DUP PMOVE
  GRAB @ 0< IF 2DROP EXIT THEN WSHIFT REPAINT ;

\ --- the calculator --------------------------------------------------------
\ The shape every four-function calculator has: digits accumulate into ENT,
\ an operator pushes ENT into ACC and is remembered, = applies it.
VARIABLE ACC VARIABLE ENT VARIABLE OP VARIABLE FRESH
154 CONSTANT CX1  350 CONSTANT CX2  40 CONSTANT CY1  128 CONSTANT CY2
: CDIGITS CX1 7 / 2 + CY1 24 + 8 / TAT T."             "
  CX1 7 / 2 + CY1 24 + 8 / TAT ENT @ T# ;
: CDRAW CX1 CX2 CY1 CY2 WINDOW
  CX1 7 / 2 + CY1 8 / TAT -1 TINV T." CALCULATOR" 0 TINV
  3 HCOLOR CX1 8 + CX2 8 - CY1 20 + CY1 36 + HFRAME
  CDIGITS
  CX1 7 / 2 + CY2 32 - 8 / TAT T." 0-9  + - * /  = C"
  CX1 7 / 2 + CY2 24 - 8 / TAT T." Q CLOSES IT" ;
: CCLEAR 0 ACC ! 0 ENT ! 0 OP ! -1 FRESH ! ;
: CAPPLY OP @ 0 = IF ENT @ ACC ! EXIT THEN
  OP @ 43 = IF ACC @ ENT @ + ACC ! EXIT THEN
  OP @ 45 = IF ACC @ ENT @ - ACC ! EXIT THEN
  OP @ 42 = IF ACC @ ENT @ * ACC ! EXIT THEN
  OP @ 47 = IF ENT @ 0= IF 0 ACC ! ELSE ACC @ ENT @ / ACC ! THEN THEN ;
: CDIGIT 48 - FRESH @ IF 0 ENT ! 0 FRESH ! THEN ENT @ 10 * + ENT ! ;
: COP CAPPLY OP ! ACC @ ENT ! -1 FRESH ! ;
: CEQ CAPPLY 0 OP ! ACC @ ENT ! -1 FRESH ! ;
: CKEY DUP 47 > OVER 58 < AND IF CDIGIT CDIGITS EXIT THEN
  DUP 43 = OVER 45 = OR OVER 42 = OR OVER 47 = OR
    IF COP CDIGITS EXIT THEN
  DUP 61 = IF DROP CEQ CDIGITS EXIT THEN
  DUP 67 = IF DROP CCLEAR CDIGITS EXIT THEN
  DUP 81 = IF DROP 0 CALCON ! REPAINT EXIT THEN
  DROP ;
: CALC CCLEAR -1 CALCON ! CDRAW ;
: DOOPEN DUP 1 = IF DROP CALC EXIT THEN
  DUP 2 = IF DROP 0 ESEL ! 0 ETOP ! REPAINT EXIT THEN
  DROP ;
' CDRAW 'CDRAW !
' DOOPEN 'OPEN !

\ --- the event loop --------------------------------------------------------
10 CONSTANT STEP  VARIABLE RUNF VARIABLE BTNW
: EVENT KEYC
  CALCON @ IF CKEY EXIT THEN
  DUP 73 = IF 0 STEP NEGATE PSTEP THEN
  DUP 75 = IF 0 STEP PSTEP THEN
  DUP 74 = IF STEP NEGATE 0 PSTEP THEN
  DUP 76 = IF STEP 0 PSTEP THEN
  DUP 32 = IF CLICK THEN
  DUP 77 = IF MREAD THEN
  DUP 84 = IF FLOCK REPAINT THEN
  DUP 88 = IF FDEL REPAINT THEN
  DUP 82 = IF FREN REPAINT THEN
  DUP 85 = IF -1 ESCROLL REPAINT THEN
  DUP 68 = IF 1 ESCROLL REPAINT THEN
  81 = IF 0 RUNF ! THEN ;
\ Poll the game port every time round: MREAD ignores an unmoved stick, so the
\ keyboard still works when nothing is plugged in.  The button fires CLICK on
\ its press edge only, not for as long as it is held.
: MOUSE MREAD
  BTN BTNW @ 0= AND IF CLICK THEN
  BTN BTNW ! ;
: DESK -1 RUNF ! 0 BTNW ! 0 CALCON ! -1 ISEL ! 0 LASTCLK ! REPAINT
  BEGIN RUNF @ WHILE TICK MOUSE KEY? IF EVENT THEN REPEAT
  PTRHIDE TEXT ;

\ --- boot ------------------------------------------------------------------
: SPLASH HGR 3 HCOLOR
  34 8 TAT T." 2E FORTH OS"
  34 10 TAT T." VERSION 0.5"
  26 12 TAT T." 6502 DIRECT-THREADED FORTH"
  22 14 TAT T." APPLE //e  128K  560X192 MONOCHROME"
  30 17 TAT T." (C) 2026 KEITH ADLER"
  30 19 TAT T." READING CATALOG..."
  CATLOAD FREE NFREE !
  60000 0 DO LOOP ;
: DESKTOP HGR 0 NWIN ! -1 GRAB ! 0 ESEL ! 0 ETOP !
  8 340 16 184 ADDWIN
  352 470 148 184 ADDWIN
  PAINT 280 96 PTRAT ;
SPLASH DESKTOP DESK
