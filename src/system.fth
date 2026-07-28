\ ===========================================================================
\ system.fth -- 2E FORTH OS, the part of the system written in Forth
\
\ The system boots to an 80-column console and stops at the Forth prompt.
\ There is no windowing environment: the graphics screen is something the
\ language turns on when a program wants it, with HGR, and leaves with TEXT.
\
\ Interpreted at boot, before the keyboard is read.  Definitions must appear
\ before their first use, so the order here is: words the kernel leaves to
\ Forth, shapes, the disk catalog, the file commands, and the greeting on the
\ last lines.
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
: SPACES 0 DO SPACE LOOP ;
: /MOD U/MOD ;
: / U/MOD NIP ;
: MOD U/MOD DROP ;
: TYPE 0 DO DUP I + C@ 127 AND EMIT LOOP DROP ;

\ Fixed-width digits, for columns that have to line up.
: .D 48 + EMIT ;
: .2 DUP 10 / .D 10 MOD .D ;
: .3 DUP 100 / .D DUP 10 / 10 MOD .D 10 MOD .D ;

\ --- shapes ----------------------------------------------------------------
\ The drawing words in the kernel plot, span and fill; a rectangle outline is
\ four spans, which is cheaper to write here than to carry in the image.
VARIABLE FX1 VARIABLE FX2 VARIABLE FY1 VARIABLE FY2
: HFRAME FY2 ! FY1 ! FX2 ! FX1 !
  FX1 @ FX2 @ FY1 @ HLINE  FX1 @ FX2 @ FY2 @ HLINE
  FX1 @ FY1 @ FY2 @ HVLINE  FX2 @ FY1 @ FY2 @ HVLINE ;

\ --- the DOS 3.3 catalog ---------------------------------------------------
\ SECBUF takes one raw sector; CATBUF holds the parsed catalog as 36-byte
\ records: type, size, then where the entry came from (catalog track, sector
\ and byte offset) so it can be written back, then the 30-char name.
$0800 CONSTANT SECBUF  $1000 CONSTANT CATBUF
$0900 CONSTANT VTOCBUF  $0A00 CONSTANT TSBUF
VARIABLE NFILE VARIABLE NFREE VARIABLE CTRK VARIABLE CSEC VARIABLE ESRC
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

: FTYPE 127 AND
  DUP 4 = IF DROP 66 EXIT THEN
  DUP 2 = IF DROP 65 EXIT THEN
  DUP 1 = IF DROP 73 EXIT THEN
  DUP 0= IF DROP 84 EXIT THEN DROP 63 ;

\ --- listing the disk ------------------------------------------------------
\ Locked files are starred, the way DOS itself listed them.
: .ENT DUP .2 SPACE
  DUP CATENT C@ 128 AND IF 42 ELSE 32 THEN EMIT
  DUP CATENT 6 + 30 TYPE SPACE
  DUP CATENT C@ FTYPE EMIT SPACE
  CATENT 1+ C@ .3 ;
: CAT
  ."  #  NAME                           T SIZ" CR
  NFILE @ 0 DO I .ENT CR LOOP
  NFREE @ . ." SECTORS FREE" CR ;

\ --- the file commands -----------------------------------------------------
\ Each takes the number CAT printed.  An index outside the catalog is refused
\ rather than trusted, because every one of these writes to the disk.
VARIABLE FA
: FPICK DUP 0< OVER NFILE @ < 0= OR
  IF DROP 0 ." NO SUCH FILE" CR EXIT THEN
  CATENT FA ! -1 ;
: FSEC FA @ 2 + C@ FA @ 3 + C@ ;
: FENTRY SECBUF FA @ 4 + C@ + ;

\ Toggle the lock bit and write the catalog sector back.
: LOCK FPICK 0= IF EXIT THEN
  FSEC SECBUF DREAD DROP
  FENTRY 2 +
  DUP C@ 128 XOR SWAP C!
  FSEC SECBUF DWRITE DROP
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
: DEL FPICK 0= IF EXIT THEN
  FA @ C@ 128 AND IF ." FILE IS LOCKED" CR EXIT THEN
  17 0 VTOCBUF DREAD DROP
  FSEC SECBUF DREAD DROP
  FENTRY
  DUP C@ OVER 1+ C@ FREEFILE
  DUP C@ OVER 32 + C!
  255 SWAP C!
  FSEC SECBUF DWRITE DROP
  17 0 VTOCBUF DWRITE DROP
  CATLOAD FREE NFREE ! ;

\ Rename: names are stored high-bit set and space padded to 30 characters.
VARIABLE NADR VARIABLE NLEN VARIABLE NDST
: REN FPICK 0= IF EXIT THEN
  ." NAME? " ASKLN NLEN ! NADR !
  NLEN @ 0= IF EXIT THEN
  NLEN @ 30 > IF 30 NLEN ! THEN
  FSEC SECBUF DREAD DROP
  FENTRY 3 + NDST !
  30 0 DO 160 NDST @ I + C! LOOP
  NLEN @ 0 DO NADR @ I + C@ 128 OR NDST @ I + C! LOOP
  FSEC SECBUF DWRITE DROP
  CATLOAD ;

\ --- the greeting ----------------------------------------------------------
: HELP
  ." CAT              LIST THE DISK" CR
  ." n LOCK           LOCK OR UNLOCK A FILE" CR
  ." n DEL   n REN    DELETE OR RENAME ONE" CR
  ." WORDS            EVERY DEFINITION IN THE DICTIONARY" CR
  ." HGR   TEXT       GRAPHICS SCREEN ON, AND BACK TO HERE" CR
  ." n HCOLOR         0 BLACK 1 GREY 2 GREY 3 WHITE" CR
  ." flag HXOR        DRAW BY XOR, SO DRAWING TWICE ERASES" CR
  ." x y HPLOT        x1 x2 y HLINE        x1 y1 x2 y2 HLINE2" CR
  ." x y r HCIRCLE    x y r HDISC          HCLS" CR
  ." x1 x2 y1 y2 HBOX AND HFRAME" CR
  ." col row TAT      T. TEXT ON THE GRAPHICS SCREEN, flag TINV" CR
  ." KEY? KEYC BTN    n PADDLE" CR
  ." t s addr DREAD   t s addr DWRITE      RAW SECTORS" CR ;
\ ." compiles an inline string, so it only says anything from inside a
\ definition; at the top level it would build one nobody runs.
: GREET PAGE
  ." 2E FORTH OS  VERSION 1.0" CR
  ." 6502 DIRECT-THREADED FORTH   APPLE //e  128K  80 COLUMNS" CR
  ." (C) 2026 KEITH ADLER" CR CR
  CATLOAD FREE NFREE !
  NFILE @ . ." FILES, " NFREE @ . ." SECTORS FREE." CR
  ." TYPE HELP FOR A SUMMARY." CR ;
GREET
