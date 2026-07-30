\ CARDS.FTH -- a card file, the third thing AppleWorks did.
\
\ Names, telephone numbers and a note, browsed with a highlighted bar and
\ kept on the disk.  Forty cards, which is more than a shoebox held.
\
\ Fixed-length fields, space padded.  A record is a fixed number of bytes
\ at a computable address, the whole file is one BSAVE, and there is no
\ free-space management to get wrong -- the right trade at this size.  A
\ card file that can lose a card is worse than one that holds forty.
\
\ Self-contained, because a file cannot LOAD another file: the console
\ writer and the typing line here are its own.  CPUT and CINV are the
\ kernel's.
\
\ CARDS runs it.  Arrows move, A adds, D deletes, S saves, L loads,
\ ESC leaves.

: CARDS-- ;

40 CONSTANT MAXC
20 CONSTANT NLEN  14 CONSTANT PLEN  24 CONSTANT TLEN
NLEN PLEN + TLEN + CONSTANT RLEN
18 CONSTANT CVIS                        \ rows the list shows at once

\ CHDR sits immediately before CBASE and holds the count, so one BSAVE
\ from CHDR writes the cards and how many there are.  ALLOT lays them
\ consecutively; that is the whole of the file format.
CREATE CHDR 2 ALLOT
CREATE CBASE MAXC RLEN * ALLOT
VARIABLE SEL VARIABLE FIRST

: NCARD ( -- n ) CHDR @ ;
: NCARD! ( n -- ) CHDR ! ;
: REC ( i -- addr ) RLEN * CBASE + ;
: RNAME ( i -- addr ) REC ;
: RPHONE ( i -- addr ) REC NLEN + ;
: RNOTE ( i -- addr ) REC NLEN + PLEN + ;
: FLEN ( addr max -- len )
  BEGIN DUP 0> IF 2DUP + 1- C@ 127 AND 32 = ELSE 0 THEN WHILE 1- REPEAT
  NIP ;
: CCLR ( -- ) CBASE MAXC RLEN * 32 FILL  0 NCARD! ;

\ --- console ---------------------------------------------------------------
VARIABLE KA VARIABLE KL VARIABLE KC VARIABLE KR
: KTYPE ( addr len col row -- )
  KR ! KC ! KL ! KA !
  KL @ 0 ?DO KA @ I + C@ 127 AND  KC @ I +  KR @  CPUT LOOP ;
: KBLANK ( n col row -- )
  KR ! KC ! 0 ?DO 32 KC @ I + KR @ CPUT LOOP ;

\ --- typing a field --------------------------------------------------------
\ Echoes where it is told to, unlike ASKLN, which echoes wherever the
\ console cursor happens to be -- and that is in the middle of the list.
CREATE FBUF 40 ALLOT
VARIABLE FL VARIABLE FMAX VARIABLE FROW
: FGET ( paddr plen max row -- addr len ok )
  FROW ! FMAX ! 0 FL !
  70 0 FROW @ KBLANK
  0 FROW @ KTYPE
  BEGIN
    BEGIN KEY? UNTIL KEYC
    DUP 13 = IF DROP FBUF FL @ -1 EXIT THEN
    DUP 27 = IF DROP 0 0 0 EXIT THEN
    DUP 8 = IF DROP
      FL @ 0> IF -1 FL +! 32 14 FL @ + FROW @ CPUT THEN
    ELSE
      DUP 31 > FL @ FMAX @ < AND IF
        DUP FBUF FL @ + C!
        DUP 14 FL @ + FROW @ CPUT
        1 FL +!
      THEN DROP
    THEN
  0 UNTIL ;

\ --- the list --------------------------------------------------------------
VARIABLE LI
: CROW ( i -- )                         \ one card, highlighted if current
  LI !
  LI @ FIRST @ < IF EXIT THEN
  LI @ FIRST @ CVIS + < 0= IF EXIT THEN
  LI @ SEL @ = IF -1 ELSE 0 THEN CINV
  46 2 LI @ FIRST @ - 3 + KBLANK
  LI @ RNAME DUP NLEN FLEN   2 LI @ FIRST @ - 3 + KTYPE
  LI @ RPHONE DUP PLEN FLEN 24 LI @ FIRST @ - 3 + KTYPE
  0 CINV ;

: CDETAIL ( -- )                        \ the note of the current card
  70 0 22 KBLANK
  NCARD 0= IF EXIT THEN
  SEL @ RNOTE DUP TLEN FLEN 2 22 KTYPE ;

: CLIST ( -- )
  PAGE
  S" CARD FILE   ARROWS  A ADD  D DELETE  S SAVE  L LOAD  ESC" 2 0 KTYPE
  S" NAME                    TELEPHONE" 2 2 KTYPE
  CVIS 0 DO 46 2 I 3 + KBLANK LOOP
  FIRST @ CVIS + NCARD MIN FIRST @ ?DO I CROW LOOP
  NCARD 0= IF S" NO CARDS YET -- PRESS A" 2 4 KTYPE THEN
  CDETAIL ;

: CMOVE1 ( new -- )
  0 MAX NCARD 1- 0 MAX MIN
  SEL @ OVER = IF DROP EXIT THEN
  SEL @ >R SEL !
  SEL @ FIRST @ < IF SEL @ FIRST ! R> DROP CLIST EXIT THEN
  SEL @ FIRST @ CVIS + < 0= IF
    SEL @ CVIS - 1+ FIRST ! R> DROP CLIST EXIT THEN
  R> CROW SEL @ CROW CDETAIL ;

\ --- adding and deleting ---------------------------------------------------
\ Variables, not the return stack.  Four things in the air is where this
\ project has gone wrong more often than anywhere else.
VARIABLE PA VARIABLE PL VARIABLE PD VARIABLE PM VARIABLE AI VARIABLE CK
: FPUT ( addr len dst max -- )          \ store, space padded
  PM ! PD ! PL ! PA !
  PD @ PM @ 32 FILL
  PA @ PD @ PL @ PM @ MIN MOVE ;

VARIABLE NA VARIABLE NL VARIABLE NV VARIABLE NS
: F>N ( addr len -- n ok )
  NL ! NA ! 0 NV ! 0 NS !
  NL @ 0= IF 0 0 EXIT THEN
  NA @ C@ 45 = IF 1 NS ! 1 NA +! -1 NL +! THEN
  NL @ 0= IF 0 0 EXIT THEN
  NL @ 0 ?DO
    NA @ I + C@ 127 AND
    DUP 48 < OVER 57 > OR IF DROP 0 0 UNLOOP EXIT THEN
    48 - NV @ 10 * + NV !
  LOOP
  NV @ NS @ IF NEGATE THEN -1 ;

: CADD ( -- )
  NCARD MAXC < 0= IF EXIT THEN
  NCARD AI !
  S" NAME:" NLEN 21 FGET 0= IF 2DROP CLIST EXIT THEN
  AI @ RNAME NLEN FPUT
  S" PHONE:" PLEN 21 FGET 0= IF 2DROP AI @ RPHONE PLEN 32 FILL
  ELSE AI @ RPHONE PLEN FPUT THEN
  S" NOTE:" TLEN 21 FGET 0= IF 2DROP AI @ RNOTE TLEN 32 FILL
  ELSE AI @ RNOTE TLEN FPUT THEN
  NCARD 1+ NCARD!
  AI @ SEL !
  SEL @ FIRST @ CVIS + < 0= IF SEL @ CVIS - 1+ 0 MAX FIRST ! THEN
  CLIST ;

\ Walk upward, not downward: copying record i+1 down onto i has to read
\ before it writes, and the loop that goes the other way eats its tail.
: CDEL ( -- )
  NCARD 0= IF EXIT THEN
  NCARD 1- SEL @ ?DO  I 1+ REC  I REC  RLEN MOVE  LOOP
  NCARD 1- NCARD!
  SEL @ NCARD 1- 0 MAX MIN SEL !
  FIRST @ NCARD < 0= IF 0 FIRST ! THEN
  CLIST ;

\ --- the disk --------------------------------------------------------------
\ One BSAVE of the count and the cards together, which works because
\ CHDR and CBASE were ALLOTted one after the other.
: CSAVE ( -- )
  PAGE ." SAVING THE CARD FILE." CR
  CHDR MAXC RLEN * 2 + BSAVE
  CLIST ;

: CLOAD ( -- )
  PAGE CAT
  ." WHICH NUMBER? " ASKLN F>N
  IF CHDR BLOAD DROP
     NCARD 0 MAXC WITHIN 0= IF ." NOT A CARD FILE" CR CCLR THEN
  ELSE DROP ." NOT A NUMBER" CR THEN
  0 SEL ! 0 FIRST ! CLIST ;

\ --- the loop --------------------------------------------------------------
: CARDS ( -- )
  0 SEL ! 0 FIRST ! CLIST
  BEGIN
    BEGIN KEY? UNTIL KEYC DUP CK !
    CASE
      11 OF SEL @ 1- CMOVE1 ENDOF
      10 OF SEL @ 1+ CMOVE1 ENDOF
      65 OF CADD ENDOF
      68 OF CDEL ENDOF
      83 OF CSAVE ENDOF
      76 OF CLOAD ENDOF
    ENDCASE
    CK @ 27 =
  UNTIL
  PAGE ." CARD FILE CLOSED." CR ;

CCLR
: CARDSHELP ." CARDS RUNS THE CARD FILE.  A ADDS, D DELETES, S SAVES." CR ;
CARDSHELP
