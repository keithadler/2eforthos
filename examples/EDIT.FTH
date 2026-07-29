\ EDIT.FTH -- a line editor, so you can write code on the machine.
\
\ Until this, source lived on the host: you edited a file there, rebuilt the
\ disk, and rebooted.  That is a poor arrangement for a system whose whole
\ argument is that it is interactive.
\
\ It is a line editor rather than a screen one, and deliberately.  A screen
\ editor wants the cursor moved about, the display redrawn under it and the
\ 80-column firmware fought with; a line editor wants ASKLN and a buffer,
\ and it is the same shape as ed, which people managed with for decades.
\
\ Lines are counted strings, 64 bytes each: one length and sixty-three
\ characters.  Sixty of them, which is three and a half kilobytes and about
\ as much source as fits in the dictionary alongside what it compiles to.
\
\ Type EHELP.  FORGET ED-- gives the whole thing back.

: ED-- ;

60 CONSTANT EMAX
64 CONSTANT ELEN
CREATE EBUF EMAX ELEN * ALLOT
VARIABLE ELINES
VARIABLE ESA VARIABLE ESL VARIABLE EFP

: ELINE ( n -- addr ) ELEN * EBUF + ;
: NEW ( -- ) 0 ELINES ! ;

\ Store a line.  Written with variables rather than stack juggling: this
\ shuffles four things and the rest of this project has a poor record with
\ that.
: ESET ( addr len n -- )
  ELINE ESA !
  ELEN 1- MIN ESL !
  ESL @ ESA @ C!
  ESA @ 1+ ESL @ MOVE ;

: E. ( n -- ) DUP 2 .R ." : " ELINE COUNT TYPE CR ;
: LIST ( -- ) ELINES @ 0 ?DO I E. LOOP ;

\ Everything from line n up shifts one further along, so a line can go in
\ between two others.  Walk downward or the copy eats its own tail.
: EOPEN ( n -- )
  ELINES @ EMAX < IF
    ELINES @ OVER ?DO
      ELINES @ 1- I - DUP ELINE SWAP 1+ ELINE ELEN MOVE
    LOOP
    1 ELINES +!
  ELSE DROP THEN ;

: ECLOSE ( n -- )                       \ delete line n
  ELINES @ 1- OVER ?DO
    I 1+ ELINE I ELINE ELEN MOVE
  LOOP DROP
  ELINES @ 1- 0 MAX ELINES ! ;

\ A lone full stop ends the typing, which is what ed does and what anyone
\ who has met a line editor will try first.
: EDONE? ( addr len -- f ) 1 = SWAP C@ 46 = AND ;
: +L ( -- )                             \ append until a lone .
  BEGIN
    ELINES @ EMAX < 0= IF ." FULL" CR EXIT THEN
    ASKLN 2DUP EDONE? IF 2DROP EXIT THEN
    ELINES @ ESET  1 ELINES +!
  0 UNTIL ;

: INS ( n -- ) DUP EOPEN ASKLN ROT ESET ;
: SET ( n -- ) ASKLN ROT ESET ;
: DEL-L ( n -- ) ECLOSE ;

\ --- to and from the disk ---------------------------------------------------
\ Flattened at HERE with a carriage return after each line, which is exactly
\ what SAVE wants and exactly what LOAD will read back.
: EFLAT ( -- addr len )
  HERE EFP !
  ELINES @ 0 ?DO
    I ELINE COUNT ESL ! ESA !
    ESA @ EFP @ ESL @ MOVE
    ESL @ EFP +!
    13 EFP @ C!  1 EFP +!
  LOOP
  HERE EFP @ HERE - ;
: EWRITE ( -- ) EFLAT SAVE ;            \ asks for the name

: EREAD ( n -- )                        \ a file into the buffer
  NEW
  FOPEN 0= IF ." NO" CR EXIT THEN
  BEGIN
    ELINES @ EMAX < 0= IF FCLOSE EXIT THEN
    PAD ELEN 1- DFGETS                  ( got eof )
    SWAP DUP 0> IF
      PAD SWAP ELINES @ ESET  1 ELINES +!
    ELSE DROP THEN
  UNTIL
  FCLOSE ;

: EHELP
  ." NEW        EMPTY THE BUFFER" CR
  ." +L         TYPE LINES, A LONE . ENDS" CR
  ." LIST       SHOW IT WITH NUMBERS" CR
  ." n INS      TYPE A LINE IN BEFORE n" CR
  ." n SET      RETYPE LINE n" CR
  ." n DEL-L    DELETE LINE n" CR
  ." n EREAD    READ A FILE IN" CR
  ." EWRITE     WRITE IT OUT, ASKING FOR A NAME" CR
  ." THEN n LOAD IT, THE WAY YOU WOULD ANY OTHER FILE." CR ;

." LOADED.  TYPE EHELP" CR
