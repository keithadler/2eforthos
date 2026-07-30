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
: 2SWAP 3 ROLL 3 ROLL ;
: 2OVER 3 PICK 3 PICK ;
: SPACE 32 EMIT ;
: SPACES 0 ?DO SPACE LOOP ;
: TYPE 0 ?DO DUP I + C@ 127 AND EMIT LOOP DROP ;
: COUNT DUP 1+ SWAP C@ ;

\ A cell is two bytes and a character is one, and neither ever needs padding
\ on a 6502 -- so the alignment words are here to be spelled, not to act.
: CELL+ 2 + ;   : CELLS 2* ;
: CHAR+ 1+ ;    : CHARS ;
: ALIGN ;       : ALIGNED ;
: >BODY 3 + ;                           \ past the JSR in the code field
: 2@ DUP 2 + @ SWAP @ ;
: 2! SWAP OVER ! 2 + ! ;
: ERASE 0 FILL ;
: BLANK 32 FILL ;
: WITHIN OVER - >R - R> U< ;

\ A scratch buffer, at the standard name.  $0D00-$0FFF is the only RAM the
\ system leaves alone once it has booted.
$0F00 CONSTANT PAD

\ --- catching a failure ----------------------------------------------------
\ Without these, any error takes the whole line down and clears the stack: a
\ word cannot try something and recover.  CATCH remembers where both stacks
\ were and hands that to THROW, which puts them back and returns through
\ CATCH rather than through whatever was in the middle.
VARIABLE HANDLER
: CATCH ( xt -- 0 | n )
  SP@ >R  HANDLER @ >R  RP@ HANDLER !
  EXECUTE
  R> HANDLER !  R> DROP  0 ;
: THROW ( n -- )
  ?DUP IF
    HANDLER @ RP!  R> HANDLER !  R> SWAP >R  SP! DROP  R>
  THEN ;

\ --- signed and mixed precision --------------------------------------------
\ UM* and UM/MOD are unsigned and in the kernel; everything signed is those
\ two with the signs taken off first and put back afterwards.
: S>D DUP 0< IF -1 ELSE 0 THEN ;
: DABS DUP 0< IF DNEGATE THEN ;
: D- DNEGATE D+ ;
: M* 2DUP XOR >R ABS SWAP ABS UM* R> 0< IF DNEGATE THEN ;

\ SM/REM truncates toward zero and FM/MOD toward negative infinity; they
\ differ only when the division is inexact and the signs disagree, and that
\ is exactly the adjustment at the end of FM/MOD.
VARIABLE SRN VARIABLE SRD
: SM/REM ( d n -- rem quot )
  DUP SRN ! OVER SRD !
  ABS >R DABS R> UM/MOD
  SRD @ SRN @ XOR 0< IF NEGATE THEN
  SWAP SRD @ 0< IF NEGATE THEN SWAP ;
: FM/MOD SM/REM
  OVER 0<> SRD @ SRN @ XOR 0< AND
  IF 1- SWAP SRN @ + SWAP THEN ;

: /MOD >R S>D R> FM/MOD ;
: / /MOD NIP ;
: MOD /MOD DROP ;
: */MOD >R M* R> FM/MOD ;
: */ */MOD NIP ;

\ --- pictured numeric output -----------------------------------------------
\ Digits come out least significant first, so they are laid down backwards
\ into a buffer and the string is whatever is left between the pointer and
\ the end.
CREATE PICBUF 36 ALLOT
VARIABLE PICP
: <# PICBUF 36 + PICP ! ;
: HOLD PICP @ 1- DUP PICP ! C! ;
: SIGN 0< IF 45 HOLD THEN ;
: UD/MOD >R 0 R@ UM/MOD ROT ROT R> UM/MOD ROT ;
: # BASE @ UD/MOD ROT DUP 9 > IF 7 + THEN 48 + HOLD ;
: #S BEGIN # 2DUP OR 0= UNTIL ;
: #> 2DROP PICP @ PICBUF 36 + OVER - ;
: U. 0 <# #S #> TYPE SPACE ;
: U.R >R 0 <# #S #> R> OVER - SPACES TYPE ;
: .R >R DUP ABS 0 <# #S ROT SIGN #> R> OVER - SPACES TYPE ;
: D. TUCK DABS <# #S ROT SIGN #> TYPE SPACE ;
: ? @ . ;
: .S DEPTH DUP 0 ?DO DUP I - PICK . LOOP DROP ;
: -TRAILING BEGIN DUP 0> IF 2DUP + 1- C@ 32 = ELSE 0 THEN WHILE 1- REPEAT ;

\ --- CASE ------------------------------------------------------------------
\ The control-flow stack is the data stack, so CASE marks its place with a
\ zero and ENDCASE patches forward branches until it finds it again.
: CASE 0 ; IMMEDIATE
: OF POSTPONE OVER POSTPONE = POSTPONE IF POSTPONE DROP ; IMMEDIATE
: ENDOF POSTPONE ELSE ; IMMEDIATE
: ENDCASE POSTPONE DROP BEGIN ?DUP WHILE POSTPONE THEN REPEAT ; IMMEDIATE

\ --- shapes ----------------------------------------------------------------
\ The drawing words in the kernel plot, span and fill; a rectangle outline is
\ four spans, which is cheaper to write here than to carry in the image.
VARIABLE FX1 VARIABLE FX2 VARIABLE FY1 VARIABLE FY2
: HFRAME FY2 ! FY1 ! FX2 ! FX1 !
  FX1 @ FX2 @ FY1 @ HLINE  FX1 @ FX2 @ FY2 @ HLINE
  FX1 @ FY1 @ FY2 @ HVLINE  FX2 @ FY1 @ FY2 @ HVLINE ;

\ --- talking to the disk ---------------------------------------------------
\ Nothing below calls DREAD or DWRITE directly; everything goes through these.
\
\ They retry.  A read straight after a write fails often enough to matter --
\ the head has just been somewhere else and the sector comes round when it
\ comes round -- which is why DOS retried too.  Failing once is not the same
\ as the sector not being there, and FOPEN refusing a file that LOAD had just
\ read perfectly well is what made that obvious.
\
\ The retry is only half of it.  The other half is that the answer has to be
\ looked at.  A read whose error is dropped leaves the *previous* sector in
\ the buffer, and every caller then goes on to believe it: the catalog walk
\ took a failed read for the end of the chain and quietly reported seven
\ files out of twenty-nine, and the file commands laid one catalog sector
\ over another.  Silently, in both cases.  So these return a flag, and the
\ code below stops and says DISK ERROR rather than carrying on with rubbish.
\
\ And they retry with PATIENCE.  Back-to-back retries all land inside the
\ same bad moment and burn out in milliseconds -- sixteen reads straight
\ after sixteen writes (INIT reloading the catalog it just wrote) failed
\ all four instant tries and worked seconds later.  A pause between tries
\ is what DOS did too: RWTS retried forty-eight times with recalibration
\ between groups.  Sixteen tries a quarter second apart outwaits anything
\ observed -- the worst was the catalog read after a sixty-five sector
\ picture, still failing at eight -- and costs nothing on the reads that
\ succeed first time.
VARIABLE DERR VARIABLE RDT VARIABLE RDS VARIABLE RDA
VARIABLE WROTE
VARIABLE DRV  1 DRV !
\ Drive 3 is a RAM disk on a RamWorks-style memory card, and everything
\ about it lives in RAMDISK.FTH on this disk -- loaded with LIB, it fills
\ these vectors and DRIVE starts accepting 3.  The system only carries
\ the fork, so a machine without the card pays three cells for the whole
\ feature.
VARIABLE 'ARD VARIABLE 'AWR VARIABLE 'D3F
16 CONSTANT DTRIES
: DPAUSE 5000 0 DO LOOP ;               \ about a quarter of a second
\ What was measured, not deduced: a read shortly after a write cannot be
\ trusted.  Some fail, and the retry catches those; some SUCCEED WITH THE
\ SECTOR'S OLD CONTENTS, and nothing downstream can catch that -- INIT
\ wrote an empty catalog, read it straight back, and got the twenty-eight
\ files it had just erased.  Waiting helps but the safe interval is seconds
\ long.  Moving the head is better: stepping away and back forces the
\ written track out of the drive's hands, the way DOS's recalibrate-
\ between-retries did, and costs a fraction of a second.  Writes
\ themselves never mind -- sixteen go down back to back without complaint
\ -- so only the first read after writing pays.
: DSETTLE WROTE @ IF 0 DSEEK DPAUSE 0 WROTE ! THEN ;
: RD ( t s addr -- ok )
  RDA ! RDS ! RDT !
  DRV @ 3 = IF RDT @ RDS @ RDA @ 'ARD @ EXECUTE EXIT THEN
  DSETTLE
  DTRIES 0 DO
    RDT @ RDS @ RDA @ DREAD DUP DERR !
    0= IF -1 UNLOOP EXIT THEN
    DPAUSE
  LOOP 0 ;
: WR ( t s addr -- ok )
  RDA ! RDS ! RDT !
  DRV @ 3 = IF RDT @ RDS @ RDA @ 'AWR @ EXECUTE EXIT THEN
  DTRIES 0 DO
    RDT @ RDS @ RDA @ DWRITE DUP DERR !
    0= IF -1 -1 WROTE ! UNLOOP EXIT THEN
    DPAUSE
  LOOP 0 ;
: DISKERR ." DISK ERROR " DERR @ . CR ;

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
\ A read that fails is not the end of the chain, and must not be taken for
\ it: doing that reported a fraction of the disk as the whole of it, with an
\ OK after it.  Say so instead.
: CATLOAD 0 NFILE !
  17 0 SECBUF RD 0= IF DISKERR EXIT THEN
  SECBUF 1+ C@ CTRK !  SECBUF 2 + C@ CSEC !
  BEGIN CTRK @ WHILE
    CTRK @ CSEC @ SECBUF RD 0= IF DISKERR 0 CTRK ! ELSE
      7 0 DO SECBUF 11 + I 35 * +
        DUP C@ 0= IF DROP ELSE
        DUP C@ 255 = IF DROP ELSE CATADD THEN THEN LOOP
      SECBUF 1+ C@ SECBUF 2 + C@ CSEC ! CTRK !
    THEN
  REPEAT ;

\ free sectors, counted out of the VTOC's four-byte-per-track bitmap
: BITS 0 SWAP 8 0 DO DUP 1 AND ROT + SWAP 2/ LOOP DROP ;
: FREE 17 0 SECBUF RD 0= IF DISKERR 0 EXIT THEN 0
  35 0 DO SECBUF 56 + I 4 * +
    DUP C@ BITS SWAP 1+ C@ BITS + + LOOP ;

\ Three drives.  Drive 1 is the system's own disk; drive 2 the Programs
\ disk, all free space and no kernel underneath it -- where anything big
\ belongs; drive 3 a RAM disk, if a memory card is there and RAMDISK.FTH
\ has been loaded to run it.  Switching selects the drive and reloads the
\ catalog, so CAT, LOAD and the file commands all mean the new disk from
\ here on.
: DRIVE ( n -- )
  DUP 1 < OVER 3 > OR IF DROP ." 1 2 OR 3" CR EXIT THEN
  DUP 3 = 'ARD @ 0= AND IF DROP ." TYPE RAMDISK FIRST" CR EXIT THEN
  DUP DRV !  3 < IF DRV @ DRVSEL THEN
  DRV @ 3 = IF 'D3F @ EXECUTE THEN
  CATLOAD FREE NFREE !
  ." DRIVE " DRV @ . NFILE @ . ." FILES " NFREE @ . ." FREE" CR ;

\ Find a file by name rather than number: -1 when it is not there.  The
\ names in the catalog are high-bit text padded with blanks to thirty
\ characters, so the comparison strips both.
VARIABLE FFA VARIABLE FFL VARIABLE FFI
: FNCH ( i -- c )  FFI @ CATENT 6 + + C@ 127 AND ;
: FNAME? ( -- f )                       \ entry FFI bears the name FFA/FFL?
  FFL @ 30 > IF 0 EXIT THEN
  FFL @ 0 ?DO
    FFA @ I + C@ I FNCH <> IF 0 UNLOOP EXIT THEN
  LOOP
  30 FFL @ ?DO
    I FNCH 32 <> IF 0 UNLOOP EXIT THEN
  LOOP -1 ;
: FINDF ( addr len -- n )
  FFL ! FFA !
  NFILE @ 0 ?DO
    I FFI ! FNAME? IF I UNLOOP EXIT THEN
  LOOP -1 ;

: FTYPE 127 AND
  DUP 4 = IF DROP 66 EXIT THEN
  DUP 2 = IF DROP 65 EXIT THEN
  DUP 1 = IF DROP 73 EXIT THEN
  DUP 0= IF DROP 84 EXIT THEN DROP 63 ;

\ --- listing the disk ------------------------------------------------------
\ Locked files are starred, the way DOS itself listed them.
: .ENT DUP 2 .R SPACE
  DUP CATENT C@ 128 AND IF 42 ELSE 32 THEN EMIT
  DUP CATENT 6 + 30 TYPE SPACE
  DUP CATENT C@ FTYPE EMIT SPACE
  CATENT 1+ C@ 3 .R ;
\ A paging CAT was tried and taken out again: pausing inside the loop
\ made CAT restart from its header instead of resuming, over and over,
\ and a catalog that can loop is worse than one that scrolls.  The list
\ needs paging -- the Programs disk is 28 files -- but it needs it done
\ properly, outside the DO loop that prints it.
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

\ Every command below reads a sector, changes a few bytes and writes it back,
\ which is why each one checks: what gets written back after a read whose
\ error was ignored is the sector before it, one catalog sector laid over
\ another.  RD and WR are up with the catalog code.

\ Toggle the lock bit and write the catalog sector back.
: LOCK FPICK 0= IF EXIT THEN
  FSEC SECBUF RD 0= IF DISKERR EXIT THEN
  FENTRY 2 +
  DUP C@ 128 XOR SWAP C!
  FSEC SECBUF WR 0= IF DISKERR EXIT THEN
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
\ then the list sectors themselves.  Track 0 holds the boot sector and is
\ never allocated to a file, so a zero track byte means an unused slot.
VARIABLE TLT VARIABLE TLS
: FREEFILE TLS ! TLT !
  BEGIN TLT @ WHILE
    TLT @ TLS @ TSBUF RD 0= IF DISKERR 0 TLT ! ELSE
      122 0 DO TSBUF 12 + I 2* +
        DUP C@ 0= IF DROP ELSE
        DUP C@ SWAP 1+ C@ FREESEC THEN LOOP
      TSBUF 1+ C@ TSBUF 2 + C@
      TLT @ TLS @ FREESEC
      TLS ! TLT !
    THEN
  REPEAT ;

\ Delete: free the sectors, then mark the catalog entry the way DOS does --
\ the first track byte moves to the last byte of the name and $FF takes its
\ place.  Locked files are refused, which is what the lock is for.
: DEL FPICK 0= IF EXIT THEN
  FA @ C@ 128 AND IF ." FILE IS LOCKED" CR EXIT THEN
  17 0 VTOCBUF RD 0= IF DISKERR EXIT THEN
  FSEC SECBUF RD 0= IF DISKERR EXIT THEN
  FENTRY
  DUP C@ OVER 1+ C@ FREEFILE
  DUP C@ OVER 32 + C!
  255 SWAP C!
  FSEC SECBUF WR 0= IF DISKERR EXIT THEN
  17 0 VTOCBUF WR 0= IF DISKERR EXIT THEN
  CATLOAD FREE NFREE ! ;

\ Rename: names are stored high-bit set and space padded to 30 characters.
VARIABLE NADR VARIABLE NLEN VARIABLE NDST
: REN FPICK 0= IF EXIT THEN
  ." NAME? " ASKLN NLEN ! NADR !
  NLEN @ 0= IF EXIT THEN
  NLEN @ 30 > IF 30 NLEN ! THEN
  FSEC SECBUF RD 0= IF DISKERR EXIT THEN
  FENTRY 3 + NDST !
  30 0 DO 160 NDST @ I + C! LOOP
  NLEN @ 0 DO NADR @ I + C@ 128 OR NDST @ I + C! LOOP
  FSEC SECBUF WR 0= IF DISKERR EXIT THEN
  CATLOAD ;

\ --- writing files --------------------------------------------------------
\ Creating a DOS file is four things at once: sectors marked used in the
\ VTOC, a track/sector list naming them, the data itself, and a catalog entry
\ pointing at the list.  Nothing is written until all four are ready except
\ the data sectors, which are harmless on their own -- an interrupted save
\ leaks sectors rather than corrupting the catalog.

\ A set bit in the VTOC bitmap means free.  Four bytes per track: byte 0
\ covers sectors 15-8 and byte 1 covers 7-0, which is why the byte to touch
\ depends on which half the sector is in.
VARIABLE QT VARIABLE QS VARIABLE QB
: QADDR QT @ 4 * 56 + VTOCBUF + QS @ 8 < IF 1+ THEN QB ! ;
: QBIT QS @ 8 < IF QS @ ELSE QS @ 8 - THEN 1<< ;
: SFREE? QS ! QT ! QADDR QB @ C@ QBIT AND 0<> ;
: STAKE QS ! QT ! QADDR QB @ DUP C@ QBIT INVERT AND SWAP C! ;

\ Track 0 is the boot loader and 1 and 2 are the kernel; 17 is the catalog
\ and is already marked used.  Searching from 3 keeps a new file off the
\ tracks the machine needs to start at all, whatever the bitmap says.
\
\ NEXTT remembers where the last allocation landed, and the search resumes
\ there -- the same trick DOS used.  Without it every sector of a file
\ re-walked all the reserved tracks bit by bit in interpreted Forth, and a
\ sixty-five sector picture spent most of a minute allocating rather than
\ writing.  If nothing is free from NEXTT on, one full scan from 3 catches
\ whatever a deletion has given back.
VARIABLE ALT VARIABLE ALS VARIABLE NEXTT  3 NEXTT !
: (ALLOC) ( from -- )
  -1 ALT !
  35 SWAP DO
    16 0 DO J I SFREE? IF J ALT ! I ALS ! LEAVE THEN LOOP
    ALT @ 0< 0= IF LEAVE THEN
  LOOP ;
: ALLOC ( -- t s )
  NEXTT @ (ALLOC)
  ALT @ 0< IF 3 (ALLOC) THEN
  ALT @ 0< IF -1 -1 EXIT THEN
  ALT @ NEXTT !
  ALT @ ALS @ 2DUP STAKE ;

\ The track/sector list: bytes 1 and 2 point at the next list sector, and
\ from byte 12 on it is pairs of track and sector, 122 of them.
VARIABLE TT VARIABLE TS VARIABLE TN VARIABLE WCNT
VARIABLE FTT VARIABLE FTS
: TSCLR TSBUF 256 0 FILL 0 TN ! ;
: TSFLUSH TT @ TS @ TSBUF WR 0= IF DISKERR THEN ;
: TSPUT ( t s -- ) TSBUF 12 + TN @ 2* + TUCK 1+ C! C! 1 TN +! ;
: NEWTS ALLOC
  TT @ 0< 0= IF
    2DUP TSBUF 2 + C! TSBUF 1+ C!
    TSFLUSH THEN
  TSCLR
  TS ! TT !
  1 WCNT +! ;

\ A binary file carries DOS's four-byte header -- load address then length --
\ so the first sector is that plus 252 bytes of data and the rest are plain.
CREATE WHDR 4 ALLOT
CREATE WNAME 30 ALLOT
VARIABLE WA VARIABLE WL VARIABLE WLT VARIABLE WI
VARIABLE WT VARIABLE WHDRN VARIABLE WNL VARIABLE WNA
: WFILL
  SECBUF 256 0 FILL
  WI @ 0= WHDRN @ 0<> AND IF
    WHDR SECBUF WHDRN @ MOVE
    WA @ SECBUF WHDRN @ + 256 WHDRN @ - WL @ MIN MOVE
  ELSE
    WA @ WI @ + WHDRN @ - SECBUF WLT @ WI @ - 256 MIN MOVE
  THEN ;
: WDATA
  0 WI !
  BEGIN WI @ WLT @ < WHILE
    TN @ 122 = IF NEWTS THEN
    ALLOC OVER 0< IF 2DROP EXIT THEN
    2DUP TSPUT
    WFILL
    SECBUF WR 0= IF DISKERR EXIT THEN
    1 WCNT +!
    256 WI +!
  REPEAT ;

\ A catalog entry is free when its first byte is zero (never used) or $FF
\ (deleted).  The sector it lives in stays in SECBUF so the entry can be
\ filled in and written straight back.
VARIABLE CATE VARIABLE FT2 VARIABLE FS2
: FINDENT
  0 CATE !
  17 0 SECBUF RD 0= IF DISKERR 0 EXIT THEN
  SECBUF 1+ C@ CTRK ! SECBUF 2 + C@ CSEC !
  BEGIN CTRK @ WHILE
    CTRK @ FT2 ! CSEC @ FS2 !
    CTRK @ CSEC @ SECBUF RD 0= IF DISKERR 0 CTRK ! 0 CATE ! ELSE
    7 0 DO
      CATE @ 0= IF
        SECBUF 11 + I 35 * +
        DUP C@ 0= OVER C@ 255 = OR IF CATE ! ELSE DROP THEN
      THEN LOOP
    CATE @ IF 0 CTRK ! ELSE
      SECBUF 1+ C@ SECBUF 2 + C@ CSEC ! CTRK ! THEN
    THEN
  REPEAT
  CATE @ 0<> ;
: PUTENT
  FTT @ CATE @ C!  FTS @ CATE @ 1+ C!
  WT @ CATE @ 2 + C!
  30 0 DO 160 CATE @ 3 + I + C! LOOP
  WNL @ 0 DO WNAME I + C@ 128 OR CATE @ 3 + I + C! LOOP
  WCNT @ 255 AND CATE @ 33 + C!
  WCNT @ 8 RSHIFT CATE @ 34 + C!
  FT2 @ FS2 @ SECBUF WR 0= IF DISKERR THEN ;

: WRITEF ( addr len -- )
  WL ! WA !
  WL @ WHDRN @ + WLT !
  ." NAME? " ASKLN WNL ! WNA !
  WNL @ 0= IF EXIT THEN
  WNL @ 30 > IF 30 WNL ! THEN
  WNA @ WNAME WNL @ MOVE
  17 0 VTOCBUF RD 0= IF DISKERR EXIT THEN
  0 WCNT ! -1 TT ! -1 TS !
  NEWTS
  TT @ 0< IF ." DISK FULL" CR EXIT THEN
  TT @ FTT ! TS @ FTS !
  WDATA
  TSFLUSH
  FINDENT 0= IF ." CATALOG FULL" CR EXIT THEN
  PUTENT
  17 0 VTOCBUF WR 0= IF DISKERR EXIT THEN
  CATLOAD FREE NFREE ! ;

: SAVE ( addr len -- ) 0 WT ! 0 WHDRN ! WRITEF ;
: BSAVE ( addr len -- ) 4 WT ! 4 WHDRN !
  OVER WHDR ! DUP WHDR 2 + ! WRITEF ;

\ The graphics screen is half in each bank, so saving one is two saves with
\ the bank switched between them.  Nothing else may print while aux is
\ selected: with 80STORE set the same switch moves the text screen.
: AUXBANK $C055 C@ DROP ;
: MAINBANK $C054 C@ DROP ;

\ --- reading a file a byte at a time ---------------------------------------
\ LOAD interprets a file and BLOAD swallows one whole; this is for the case
\ in between, where a program wants the bytes and does not want the whole
\ file in memory at once.
\
\ One file at a time.  A handle table would want a buffer each, and 256
\ bytes a handle is not a thing this machine has to spare -- so the buffer,
\ the track/sector list and the position are single and named plainly.
\
\ FGETC returns every byte of every sector the file was allocated.  DOS
\ stores no byte count for a text file -- it ends at the first zero -- so
\ where a file stops is the caller's business, exactly as it is for DOS.
CREATE FOBUF 256 ALLOT
VARIABLE FOT VARIABLE FOS          \ the track/sector list being walked
VARIABLE FOI                       \ which pair in it comes next
VARIABLE FOP                       \ position within FOBUF
VARIABLE FOOK VARIABLE FOEOF

: FONEXT ( -- ok )                 \ pull the next data sector into FOBUF
  BEGIN
    FOT @ 0= IF 0 EXIT THEN
    FOI @ 122 < IF
      TSBUF 12 + FOI @ 2* +  1 FOI +!
      DUP C@ IF                    \ a used slot: read it
        DUP C@ SWAP 1+ C@ FOBUF RD 0= IF DISKERR 0 EXIT THEN
        0 FOP ! -1 EXIT
      ELSE DROP THEN               \ an empty one: keep looking
    ELSE                           \ this list is used up; is there another?
      TSBUF 1+ C@ TSBUF 2 + C@ FOS ! FOT !
      FOT @ IF
        FOT @ FOS @ TSBUF RD 0= IF DISKERR 0 EXIT THEN
        0 FOI !
      THEN
    THEN
  AGAIN ;

: FOPEN ( n -- ok )
  FPICK 0= IF 0 EXIT THEN
  FSEC SECBUF RD 0= IF DISKERR 0 EXIT THEN
  FENTRY DUP C@ SWAP 1+ C@ FOS ! FOT !
  FOT @ FOS @ TSBUF RD 0= IF DISKERR 0 EXIT THEN
  0 FOI !  256 FOP !               \ forces the first read
  0 FOEOF !  -1 FOOK !  -1 ;

: FGETC ( -- c | -1 )
  FOOK @ 0= IF -1 EXIT THEN
  FOEOF @ IF -1 EXIT THEN
  FOP @ 256 < 0= IF
    FONEXT 0= IF -1 FOEOF ! -1 EXIT THEN
  THEN
  FOBUF FOP @ + C@  1 FOP +! ;

: FCLOSE ( -- ) 0 FOOK ! ;
: FEOF? ( -- f ) FOEOF @ ;

VARIABLE FRA VARIABLE FRN VARIABLE FRG
: FREAD ( addr n -- got )
  FRN ! FRA ! 0 FRG !
  FRN @ 0 ?DO
    FGETC DUP 0< IF DROP LEAVE THEN
    FRA @ FRG @ + C!
    1 FRG +!
  LOOP FRG @ ;

\ A line rather than a byte.  Reads up to a carriage return, strips the high
\ bit DOS stores text with, and says how many characters and whether the file
\ ran out.  This is what PRINT# and INPUT# were for, and what makes a text
\ file worth interchanging with anything else.
VARIABLE DGA VARIABLE DGN VARIABLE DGC VARIABLE DGE
: DFGETS ( addr n -- got eof )
  DGN ! DGA ! 0 DGC ! 0 DGE !
  BEGIN
    FGETC DUP 0< IF DROP -1 DGE ! -1 ELSE
      127 AND
      DUP 13 = IF DROP -1 ELSE
        DUP 0= IF DROP -1 DGE ! -1 ELSE
          DGC @ DGN @ < IF DGA @ DGC @ + C! 1 DGC +! ELSE DROP THEN
          0
        THEN
      THEN
    THEN
  UNTIL
  DGC @ DGE @ ;

\ RND on its own is a whole 16-bit range; this is the one anyone wants.
: RND-RANGE ( lo hi -- n ) OVER - 1+ RND SWAP MOD + ;

\ --- a fresh filesystem ----------------------------------------------------
\ The disk must already be formatted: writing address fields needs a track
\ writer this driver does not have, and DWRITE can only replace a sector that
\ is already there.  This lays down a VTOC and an empty catalog chain on top
\ of one, which is what INIT does once the format is done.
\
\ Tracks 0-10 and 17 are marked used, because that is where this system keeps
\ its boot sector, its kernel and its own source.  INIT on the disk you
\ booted from will therefore leave the machine bootable and lose only the
\ files.
VARIABLE IVT
: IBITS ( track -- )               \ mark one track free in VTOCBUF
  4 * 56 + VTOCBUF + DUP 255 SWAP C! 1+ 255 SWAP C! ;
: IUSED ( track -- )
  4 * 56 + VTOCBUF + DUP 0 SWAP C! 1+ 0 SWAP C! ;
: INIT ( -- )
  VTOCBUF 256 0 FILL
  17 VTOCBUF 1+ C!  15 VTOCBUF 2 + C!   \ first catalog sector
  3 VTOCBUF 3 + C!                      \ DOS 3.3
  254 VTOCBUF 6 + C!                    \ volume
  122 VTOCBUF $27 + C!
  18 VTOCBUF $30 + C!  1 VTOCBUF $31 + C!
  35 VTOCBUF $34 + C!  16 VTOCBUF $35 + C!
  0 VTOCBUF $36 + C!  1 VTOCBUF $37 + C!
  35 0 DO I IBITS LOOP
  \ the kernel and its source live only on the disk the machine boots
  \ from; formatting the Programs disk gives those thirteen tracks back
  DRV @ 1 = IF SRCEND 1+ 0 DO I IUSED LOOP THEN
  17 IUSED
  17 0 VTOCBUF WR 0= IF DISKERR EXIT THEN
  15 0 DO
    SECBUF 256 0 FILL
    15 I - 1- ?DUP IF                   \ the next catalog sector, 14..0
      17 SECBUF 1+ C!  SECBUF 2 + C!
    THEN
    17 15 I - SECBUF WR 0= IF DISKERR EXIT THEN
  LOOP
  CATLOAD FREE NFREE ! ;

\ --- loading source from the disk -----------------------------------------
\ The text goes on hi-res page 1: eight kilobytes that the dictionary cannot
\ reach and that nothing else wants while source is being read.  Reading a
\ file therefore costs no dictionary at all, which matters -- the definitions
\ the file makes have to fit somewhere.  Turning the graphics screen on while
\ a file is still being read would overwrite what is left of it.
\
\ SRC is the kernel's own source pointer: the outer interpreter already reads
\ lines from there in preference to the keyboard and drops back to the
\ keyboard at the first zero byte, which is exactly what loading a file needs.
\ One file at a time -- a load inside a load would move the ground under the
\ first one.
$CE CONSTANT 'SRC  $2000 CONSTANT LDBUF  $4000 CONSTANT LDTOP
VARIABLE LT VARIABLE LS VARIABLE LP VARIABLE LBUF
\ Where the sector walk must stop.  Source goes on hi-res page 1 and must
\ not run past it; a binary goes wherever it was asked for, and is only
\ stopped by the top of memory.  One walk, two ceilings.
VARIABLE LTOP
: LSECS ( t s -- ) LS ! LT !
  MAINBANK              \ the buffer is on hi-res page 1, which follows PAGE2
                        \ while 80STORE is set -- and the console's firmware
                        \ moves PAGE2 every time it prints a character
  BEGIN LT @ WHILE
    LT @ LS @ TSBUF RD 0= IF DISKERR 0 LT ! ELSE
      122 0 DO TSBUF 12 + I 2* +
        DUP C@ 0= IF DROP ELSE
          LP @ LTOP @ U< IF     \ unsigned: these are addresses, not numbers
            DUP C@ SWAP 1+ C@ LP @ RD 0= IF DISKERR THEN  256 LP +!
          ELSE DROP THEN
        THEN LOOP
      TSBUF 1+ C@ TSBUF 2 + C@ LS ! LT !
    THEN
  REPEAT
  0 LP @ C! ;

: LNORM LBUF @ BEGIN DUP C@ ?DUP WHILE 127 AND OVER C! 1+ REPEAT DROP ;

: LOAD ( n -- ) FPICK 0= IF EXIT THEN
  FSEC SECBUF RD 0= IF DISKERR EXIT THEN
  LDTOP LTOP !
  LDBUF DUP LBUF ! LP !
  FENTRY DUP C@ SWAP 1+ C@ LSECS
  LNORM
  LBUF @ 'SRC ! ;

\ --- words as commands ------------------------------------------------------
\ A word the interpreter cannot find is offered here before it becomes a
\ question mark: if the system disk carries a file named WORD.FTH, that
\ file is loaded -- so MORE, MENU and whatever tools come later are simply
\ commands, fetched the first time they are named, from any drive.  The
\ rest of the line is abandoned while the file streams in and announces
\ itself; typed again, the word exists.  The kernel calls this through
\ the 'NF vector, set at the end of this file.
\ --- decimal numbers, and why they are not here ----------------------------
\ 3.14159 at the prompt was written, worked, and had to come out again.
\ The parser is Forth, so it compiled into the language card, and the card
\ had a few hundred bytes left: adding it put LATEST at $FF44, and a
\ dictionary that close to its ceiling stopped being a dictionary --
\ words as ordinary as / and MOD went missing and */ ran into the
\ monitor.  The guard in CheckDP catches DP crossing $FFF0, but the
\ damage here arrives before that, in the pressure a nearly-full card
\ puts on everything compiled after it.
\
\ The feature is right and the place is wrong.  It belongs in the
\ kernel's own Number routine, in assembly, in main memory -- which is
\ affordable only once PICSAVE stops needing sixteen contiguous
\ kilobytes.  Until then S>F is how you make a float.

VARIABLE NFL VARIABLE NFA VARIABLE NFD
VARIABLE NF2NO                          \ drive 2 already failed to answer
: AUTOLOAD ( addr len -- f )
  STATE @ IF 2DROP 0 EXIT THEN
  'SRC 1+ C@ IF 2DROP 0 EXIT THEN       \ not while a file is streaming
  DUP 1 < OVER 26 > OR IF 2DROP 0 EXIT THEN
  NFL ! NFA !
  NFA @ PAD NFL @ MOVE                  \ NAME.FTH at PAD
  46 PAD NFL @ + C!  70 PAD NFL @ 1+ + C!
  84 PAD NFL @ 2 + + C!  72 PAD NFL @ 3 + + C!
  DRV @ NFD !
  NFD @ 1 <> IF 1 DRVSEL CATLOAD THEN
  PAD NFL @ 4 + FINDF
  \ not a tool on the system disk?  perhaps a program on drive 2 --
  \ which is where PAINT, WRITE and their kind live, beside the space
  \ they need.  A machine with one drive has nothing in slot two, and a
  \ mistyped word must not grind an empty drive for half a minute every
  \ time -- so the first failure to read a catalog there is remembered,
  \ and drive 2 is not asked again until reboot.
  DUP 0< NF2NO @ 0= AND IF
    DROP 2 DRVSEL CATLOAD
    NFILE @ 0= IF -1 NF2NO ! THEN
    PAD NFL @ 4 + FINDF THEN
  DUP 0< IF DROP 0 ELSE LOAD -1 THEN
  NFD @ DRVSEL CATLOAD FREE NFREE ! ;

\ BLOAD reads a binary file to wherever you ask, steps the four-byte header
\ off the front, and hands back the length that header claims.
VARIABLE BLA
: BLOAD ( n addr -- len ) BLA ! FPICK 0= IF 0 EXIT THEN
  FSEC SECBUF RD 0= IF DISKERR 0 EXIT THEN
  $BF00 LTOP !
  BLA @ LP !
  FENTRY DUP C@ SWAP 1+ C@ LSECS
  BLA @ 2 + @
  BLA @ 4 + BLA @ ROT DUP >R MOVE R> ;

\ --- precompiled overlays --------------------------------------------------
\ Compiling a library from source costs a token lookup per word; the same
\ library saved as an image of the dictionary it produced loads at disk
\ speed.  Nothing has to be relocated because it goes back at the address it
\ came from, which is the whole trick -- a thread cell is an absolute
\ address, and moving one word would mean patching every thread that names
\ it.
\
\   MARK          before defining anything
\   ... : FOO ... ;  ...
\   SAVEDICT      writes a binary file, asking for the name
\
\ and in a later session, before defining anything else:
\
\   n LOADDICT    reads it back and the words are simply there
\
\ The two cells MARK lays down hold LATEST and the base address, so LOADDICT
\ can put the dictionary chain back and refuse the load if it would land
\ somewhere else.
VARIABLE MKBASE VARIABLE MKLATEST
: MARK HERE MKBASE ! LATEST @ MKLATEST ! 0 , 0 , ;
: UNMARK MKBASE @ 0= IF EXIT THEN
  MKBASE @ DP ! MKLATEST @ LATEST ! REINDEX ;
: SAVEDICT
  MKBASE @ 0= IF ." NO MARK" CR EXIT THEN  \ 0<, not 0=, would call every
                                            \ address above $7FFF no mark
  LATEST @ MKBASE @ !
  MKBASE @ MKBASE @ 2 + !
  MKBASE @ HERE OVER - BSAVE ;
: LOADDICT ( n -- )
  HERE DUP >R BLOAD
  R@ 2 + @ R@ = 0= IF
    R> 2DROP ." OVERLAY WANTS A DIFFERENT ADDRESS" CR EXIT THEN
  R@ + DP !
  R> @ LATEST !
  REINDEX ;

\ --- looking at things ----------------------------------------------------
\ SEE, DUMP, MARKER and their helpers live in SEE.FTH on this disk, and
\ the autoload hook fetches them the first time one is named -- the
\ language card was full, and words you reach for occasionally are
\ exactly what should ride on disk.  DUMP.FTH and MARKER.FTH are the
\ same file under the names the hook will look for.

\ --- inline tables of numbers ---------------------------------------------
\ Applesoft's DATA and READ.  The values go in the dictionary between DATA:
\ and ;DATA, and READ-VAL walks them; RESTORE-DATA winds back to the start.
VARIABLE DATA0 VARIABLE DATAP VARIABLE DATAN
: DATA: ( -- ) HERE DATA0 ! HERE DATAP ! 0 DATAN ! ;
: +VAL ( n -- ) , 1 DATAN +! ;
: ;DATA ( -- ) DATA0 @ DATAP ! ;
: DATA# ( -- n ) DATAN @ ;
: RESTORE-DATA ( -- ) DATA0 @ DATAP ! ;
: DATA-END? ( -- f ) DATAP @ DATA0 @ - 2/ DATAN @ < 0= ;
: READ-VAL ( -- n ) DATA-END? IF 0 EXIT THEN DATAP @ @ 2 DATAP +! ;

\ --- odds and ends ---------------------------------------------------------
\ A power by repeated multiplication: exact, where FEXP and FLN would round.
: IPOW ( n e -- n^e ) 1 SWAP ?DUP IF 0 ?DO OVER * LOOP THEN NIP ;

\ Fisher-Yates, w bytes to the element.  RND-RANGE gives the swap partner.
VARIABLE SHA VARIABLE SHW VARIABLE SHP VARIABLE SHQ
: SH@ ( i -- addr ) SHW @ * SHA @ + ;
: SHSWAP ( i j -- )
  SH@ SHQ !  SH@ SHP !
  SHW @ 0 ?DO
    SHP @ I + C@
    SHQ @ I + C@
    SHP @ I + C!
    SHQ @ I + C!
  LOOP ;
: SHUFFLE ( addr n w -- )
  SHW ! SWAP SHA !
  1 SWAP 1- ?DO
    0 I RND-RANGE I SHSWAP
  -1 +LOOP ;

\ Applesoft's WAIT: sit on a location until the masked bits match.
VARIABLE WBA VARIABLE WBM VARIABLE WBV
: WAIT-BIT ( addr mask val -- )
  WBV ! WBM ! WBA !
  BEGIN WBA @ C@ WBM @ AND WBV @ = UNTIL ;

\ --- lo-res lines ----------------------------------------------------------
\ Forty blocks across and forty-eight down -- but in GR the bottom four text
\ rows are the console's, so rows 40-47 belong to it and anything drawn there
\ is scrolled over.  GR-FULL shows all forty-eight; the console still writes
\ into the bottom of it, it is simply not displayed.
\
\ Forty blocks across and forty-eight down, so a span is a short loop and
\ GPLOT does the masking.  GR is the right screen for a bar chart: two
\ blocks to a byte and no shifting, against 560 pixels that need both.
VARIABLE GLA VARIABLE GLB
: GHLIN ( x1 x2 y -- ) GLA ! GLB ! GLB @ 1+ SWAP ?DO I GLA @ GPLOT LOOP ;
: GVLIN ( y1 y2 x -- ) GLA ! GLB ! GLB @ 1+ SWAP ?DO GLA @ I GPLOT LOOP ;
: GBAR ( x y n -- ) OVER + 1- ROT GVLIN ;

\ --- saving a picture ------------------------------------------------------
\ The screen is sixteen kilobytes, not eight: the same addresses $2000-$3FFF
\ in both banks, aux holding the even byte columns and main the odd.  BSAVE
\ takes one contiguous region, so a plain BSAVE of $2000 gets half a picture
\ and restoring it looks like corruption.
\
\ Both halves are staged into one 16K block above HERE first.  Switching
\ banks only moves $2000-$3FFF, so the staging area and the code doing the
\ copying stay put either way.
\
\ That wants sixteen kilobytes free.  For a while the kernel had grown past
\ leaving them and this word could only refuse politely; the room came back
\ when the uninitialized buffers moved out of the image to the block above
\ the catalog (kernel.inc).  PICROOM stays as the guard: the margin is a
\ few dozen bytes, and the day the kernel grows past it again this refuses
\ honestly instead of writing into the I/O page at $C000.
$4000 CONSTANT PICLEN
: PICROOM ( -- ok )
  UNUSED PICLEN < IF
    ." NEEDS 16K FREE, HAS " UNUSED . CR 0 ELSE -1 THEN ;
: PICSAVE ( -- )                        \ asks for a name
  PICROOM 0= IF EXIT THEN
  MAINBANK  $2000 HERE 8192 MOVE
  AUXBANK   $2000 HERE 8192 + 8192 MOVE
  MAINBANK  HERE PICLEN BSAVE ;
: PICLOAD ( n -- )
  PICROOM 0= IF DROP EXIT THEN
  HERE BLOAD DROP
  MAINBANK  HERE $2000 8192 MOVE
  AUXBANK   HERE 8192 + $2000 8192 MOVE
  MAINBANK ;

\ --- loading a library ------------------------------------------------------
\ Libraries live on the system disk in drive 1; programs live on drive 2.
\ LIB NAME fetches a library from the system disk wherever you happen to
\ be, and puts your drive back -- so a program's instructions can say
\ LIB GFXLIB.FTH without caring which drive is current or what number
\ the catalog gives the file today.  Like LOAD, it is a word for the
\ prompt, not for the middle of a file being loaded.
: LIB ( -- )
  PARSE-NAME DUP 0= IF 2DROP ." LIB NAME" CR EXIT THEN
  DRV @ >R
  R@ 1 <> IF 1 DRVSEL CATLOAD THEN
  FINDF DUP 0< IF DROP ." NOT ON THE SYSTEM DISK" CR ELSE LOAD THEN
  R> DUP 1 <> IF DUP DRV ! DRVSEL CATLOAD FREE NFREE ! ELSE DROP THEN ;

\ --- help -------------------------------------------------------------------
\ HELP alone prints the summary below.  HELP NAME looks NAME up in the
\ HELPTEXT file on the system disk: an entry is a line beginning with the
\ word itself, and every indented line after it belongs to the entry.  The
\ file is data, not code, so adding an entry costs no dictionary at all.
VARIABLE HWA VARIABLE HWL VARIABLE HON VARIABLE HHIT
\ HELP hops to the system disk and back by itself: needing to know which
\ drive the manual was in is the kind of question this system exists to
\ make unnecessary.
VARIABLE HDRV
: HRESTORE ( -- )
  HDRV @ 1 <> IF HDRV @ DRVSEL CATLOAD FREE NFREE ! THEN ;
: HTOK? ( addr len -- f )               \ line's first token = the word?
  DUP HWL @ < IF 2DROP 0 EXIT THEN
  OVER HWL @ + C@ 32 <> OVER HWL @ <> AND IF 2DROP 0 EXIT THEN
  DROP
  HWL @ 0 ?DO
    DUP I + C@ HWA @ I + C@ <> IF DROP 0 UNLOOP EXIT THEN
  LOOP DROP -1 ;
: HLINE? ( addr len -- )                \ one line of the file, maybe printed
  DUP 0= IF 2DROP 0 HON ! EXIT THEN
  OVER C@ 32 = IF
    HON @ IF TYPE CR ELSE 2DROP THEN EXIT THEN
  2DUP HTOK? DUP HON ! IF -1 HHIT ! TYPE CR ELSE 2DROP THEN ;
: HELPW ( addr len -- )
  HWL ! HWA !
  DRV @ HDRV !
  HDRV @ 1 <> IF 1 DRVSEL CATLOAD THEN
  S" HELPTEXT" FINDF DUP 0< IF
    DROP ." NO HELPTEXT ON THE SYSTEM DISK" CR HRESTORE EXIT THEN
  FOPEN 0= IF ." CANNOT OPEN HELPTEXT" CR HRESTORE EXIT THEN
  0 HON ! 0 HHIT !
  BEGIN
    PAD 79 DFGETS >R              ( got ) ( r: eof )
    PAD SWAP HLINE?
    \ once the entry has been printed and has ended, the rest of the file
    \ has nothing more to say -- and it is a long file
    HHIT @ HON @ 0= AND IF R> DROP FCLOSE HRESTORE EXIT THEN
  R> UNTIL FCLOSE
  HHIT @ 0= IF ." NO ENTRY FOR THAT.  PLAIN HELP LISTS THE BASICS." CR THEN
  HRESTORE ;

\ --- the greeting ----------------------------------------------------------
\ The summary plain HELP prints is itself an entry in HELPTEXT -- the one
\ named HELP -- so a screen and a half of text costs the language card
\ nothing.  It used to be ." strings compiled here, and the card was full.
: HELP
  PARSE-NAME DUP 0= IF 2DROP S" HELP" THEN HELPW ;
\ ." compiles an inline string, so it only says anything from inside a
\ definition; at the top level it would build one nobody runs.
: GREET PAGE
  ." 2E FORTH OS  VERSION 1.0" CR
  ." 6502 DIRECT-THREADED FORTH   APPLE //e  "
  $1EAD C@ 64 * 64 + 0 <# #S #> TYPE ." K  80 COLUMNS" CR
  ." (C) 2026 KEITH ADLER" CR CR
  CATLOAD FREE NFREE !
  NFILE @ . ." FILES, " NFREE @ . ." SECTORS FREE." CR
  ." PROGRAMS ARE IN DRIVE 2: TYPE 2 DRIVE THEN CAT." CR
  ." TYPE HELP FOR A SUMMARY, OR HELP HGR FOR ONE WORD." CR ;
: NFON ['] AUTOLOAD 'NF ! ;  NFON
GREET
