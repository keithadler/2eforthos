\ WRITE.FTH -- ForthWrite: prose on the machine, with word wrap.
\
\ EDIT is for code, a line at a time.  This is for sentences: type and
\ keep typing, and when a word runs past the right margin it is carried
\ whole onto the next line -- the way every writer since the typewriter
\ has wanted.  Delete rubs out, RETURN ends a paragraph, ESC finishes.
\
\   WRITE          start composing (into an empty document)
\   WLIST          read the document back, numbered
\   WSAVE          write it out as a text file, asking the name
\   n WLOAD        read a text file in to continue it
\
\ Sixty lines of sixty-four characters, the same shape EDIT uses, so a
\ document saved here loads there and back again.

: WRITE-- ;

60 CONSTANT WMAX
64 CONSTANT WLEN
58 CONSTANT WRAP                        \ wrap margin, with room for a space
CREATE WBUF WMAX WLEN * ALLOT
VARIABLE WLINES VARIABLE WCOL VARIABLE WESC

: WLINE ( n -- addr ) WLEN * WBUF + ;
: WCUR ( -- addr ) WLINES @ WLINE ;     \ the line being typed

: WOPEN ( -- )                          \ start a fresh line
  0 WCOL !  0 WCUR C! ;

: WFLUSH ( -- )                         \ the current line is finished
  WCOL @ WCUR C!
  WLINES @ 1+ WMAX MIN WLINES ! WOPEN ;

: WPUT ( c -- )                         \ one character onto the line
  WCUR 1+ WCOL @ + C!  1 WCOL +! ;

\ Carry the unfinished last word to the next line, whole.  Scan back for
\ the space; everything after it moves down.
VARIABLE WBRK
: WWRAP ( -- )
  WCOL @ WBRK !
  BEGIN WBRK @ 0> WCUR 1+ WBRK @ + 1- C@ 32 <> AND WHILE -1 WBRK +! REPEAT
  WBRK @ 0= IF WFLUSH EXIT THEN         \ one huge word: just break it
  WCOL @ WBRK @ - >R
  WCUR 1+ WBRK @ +  PAD  R@ MOVE        \ the carried word, aside
  WBRK @ 1- 0 MAX WCOL ! WFLUSH
  PAD WCUR 1+ R@ MOVE  R> WCOL ! ;

: WKEY ( -- c ) BEGIN KEY? UNTIL KEYC ;

: WSHOW ( c -- ) EMIT ;                 \ echo as we go

: WRITE1 ( -- )                         \ one keystroke of composing
  WKEY
  DUP 27 = IF DROP -1 WESC ! EXIT THEN
  DUP 13 = IF DROP WFLUSH CR EXIT THEN
  DUP 8 = IF DROP
    WCOL @ 0> IF -1 WCOL +! 8 EMIT 32 EMIT 8 EMIT THEN EXIT THEN
  DUP 32 < IF DROP EXIT THEN
  DUP WSHOW WPUT
  WCOL @ WRAP > IF WWRAP CR THEN ;

: WRITE ( -- )
  0 WLINES ! WOPEN 0 WESC !
  PAGE ." FORTHWRITE.  ESC ENDS, RETURN IS A PARAGRAPH." CR CR
  BEGIN WRITE1 WESC @ WLINES @ WMAX < 0= OR UNTIL
  WCOL @ 0> IF WFLUSH THEN
  CR ." -- " WLINES @ . ." LINES.  WLIST READS, WSAVE KEEPS." CR ;

: WLIST ( -- )
  WLINES @ 0 ?DO I 2 .R ." : " I WLINE COUNT TYPE CR LOOP ;

\ flattened with a return after each line, which SAVE wants and any
\ text-file reader understands
VARIABLE WFP
: WFLAT ( -- addr len )
  HERE WFP !
  WLINES @ 0 ?DO
    I WLINE COUNT DUP >R WFP @ SWAP MOVE
    R> WFP +!  13 WFP @ C!  1 WFP +!
  LOOP
  HERE WFP @ HERE - ;
: WSAVE ( -- ) WFLAT SAVE ;

: WLOAD ( n -- )                        \ a text file back into the buffer
  0 WLINES !
  FOPEN 0= IF ." CANNOT OPEN IT" CR EXIT THEN
  BEGIN
    WLINES @ WMAX < 0= IF FCLOSE EXIT THEN
    PAD WLEN 1- DFGETS SWAP DUP 0> IF
      DUP WCUR C!  PAD WCUR 1+ ROT MOVE
      WLINES @ 1+ WLINES !
    ELSE DROP THEN
  UNTIL FCLOSE ;

: WHELP ." WRITE COMPOSES WITH WORD WRAP.  ESC ENDS." CR ;
WHELP
