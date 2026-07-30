\ SEE.FTH -- the inspection kit: SEE, DUMP, MARKER and their helpers.
\
\ Fetched automatically the first time SEE, DUMP or MARKER is typed --
\ the catalog carries this file under all three names, because the
\ autoload hook maps a word to a file called WORD.FTH and nothing else.
\ It lived in the language card until the card filled; a word you reach
\ for a few times a session is exactly what should ride on disk.

\ --- looking at things ----------------------------------------------------
\ The debugging tax: an interactive interpreter is not the same as being able
\ to stop and ask what a thing is.  These are the two questions worth asking
\ -- what is in that memory, and what is that word made of.
: HEXD ( n -- c ) 15 AND DUP 9 > IF 7 + THEN 48 + ;
: .H2 ( n -- ) DUP 4 RSHIFT HEXD EMIT HEXD EMIT ;
: .H4 ( n -- ) DUP 8 RSHIFT .H2 .H2 ;

VARIABLE DMA VARIABLE DMN
: .DBYTES ( -- ) 8 0 DO DMA @ I + C@ .H2 SPACE LOOP ;
: .DCHARS ( -- )
  8 0 DO DMA @ I + C@ 127 AND
    DUP 32 < IF DROP 46 THEN DUP 126 > IF DROP 46 THEN EMIT LOOP ;
: DUMP ( addr n -- )
  DMN ! DMA !
  BEGIN DMN @ 0> WHILE
    DMA @ .H4 ." : " .DBYTES ." |" .DCHARS ." |" CR
    8 DMA +!  -8 DMN +!
  REPEAT ;

\ Reverse lookup: which word owns this code field.  The definition chain runs
\ newest to oldest and every header knows its own name length, so the code
\ field is a fixed distance past it.
: HDR>CFA ( hdr -- cfa ) DUP 4 + C@ 63 AND + 5 + ;
: HDR>NAME ( hdr -- addr len ) DUP 5 + SWAP 4 + C@ 63 AND ;
VARIABLE SEEX VARIABLE SEEN
: >NAME ( xt -- addr len )
  SEEX ! LATEST @
  BEGIN DUP WHILE
    DUP HDR>CFA SEEX @ = IF HDR>NAME EXIT THEN
    @
  REPEAT DROP 0 0 ;

\ SEE walks the thread and names each cell.  LIT is followed by its value and
\ the branches by a target, so those are printed rather than looked up --
\ otherwise the number would be reported as whatever word happens to live at
\ that address.
: .CELL ( xt -- ) >NAME ?DUP IF TYPE ELSE DROP ." ?" THEN SPACE ;
: SEE ( -- )
  ' ?DUP 0= IF ." ?" CR EXIT THEN
  DUP C@ 32 <> IF ." PRIMITIVE AT " .H4 CR EXIT THEN
  ." : " DUP >NAME TYPE SPACE
  3 +  200 SEEN !
  BEGIN
    SEEN @ 0= IF DROP ." ..." CR EXIT THEN
    -1 SEEN +!
    DUP @
    DUP ['] EXIT = IF 2DROP ." ;" CR EXIT THEN
    DUP ['] LIT = IF DROP 2 + DUP @ . 2 + 0 ELSE
      DUP ['] BRANCH = OVER ['] 0BRANCH = OR IF
        .CELL 2 + DUP @ ." ->" .H4 SPACE 2 + 0
      ELSE .CELL 2 + 0 THEN
    THEN DROP
  AGAIN ;

\ MARKER NAME makes a word that forgets everything defined after it, itself
\ included -- which is what a demo file's leading marker was doing by hand.
VARIABLE MKH VARIABLE MKL
: MARKER ( -- )
  HERE MKH ! LATEST @ MKL !
  CREATE MKH @ , MKL @ ,
  DOES> DUP @ SWAP 2 + @ LATEST ! DP ! REINDEX ;


: SEEHELP ." SEE NAME / addr n DUMP / MARKER NAME NOW LOADED." CR ;
SEEHELP
