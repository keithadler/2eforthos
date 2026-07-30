\ STR.FTH -- the string words, the other thing Applesoft had and this did not.
\
\ Applesoft gives you A$ and LEFT$ and MID$ and a garbage-collected heap.
\ This gives you the operations without the heap: a string here is the
\ pair an address and a length, which is what S" leaves and what TYPE
\ takes, and where the bytes live is your business.  SBUF and SCOPY are
\ here for when it should be somebody's business.
\
\ Type STR and this loads itself.  The words:
\
\   S=      ( a1 l1 a2 l2 -- f )   are they the same text
\   SUB     ( a l start n -- a2 l2 )   MID$
\   LEFT    ( a l n -- a2 l2 )     the first n
\   RIGHT   ( a l n -- a2 l2 )     the last n
\   SCAN    ( a l c -- i )         where c first appears, -1 if never
\   SPLIT   ( a l c -- a1 l1 a2 l2 )   head and tail either side of c
\   TRIM    ( a l -- a2 l2 )       blanks off both ends
\   UPPER   ( a l -- )             in place
\   S>N     ( a l -- n f )         VAL: the number, and whether it was one
\   N>S     ( n -- a l )           STR$
\   SBUF    ( n -- a )             one of eight 64-byte scratch strings
\   SCOPY   ( a l dest -- dest l ) put a string somewhere it will stay
\   SCAT    ( a1 l1 a2 l2 dest -- dest l )   join two into somewhere

\ One trap, and it is the language's not this file's: S" hands back a
\ pointer into a single shared buffer, so two of them on one line are the
\ same address holding the second string.  Copy one into an SBUF slot
\ before fetching the other, or the join comes out CDCD.

: STR-- ;

\ --- comparing --------------------------------------------------------------
VARIABLE SA VARIABLE SL VARIABLE SB VARIABLE SM
: S= ( a1 l1 a2 l2 -- f )
  SM ! SB ! SL ! SA !
  SL @ SM @ <> IF 0 EXIT THEN
  SL @ 0 ?DO
    SA @ I + C@ 127 AND  SB @ I + C@ 127 AND
    <> IF 0 UNLOOP EXIT THEN
  LOOP -1 ;

\ --- cutting ----------------------------------------------------------------
\ Every one of these clamps rather than trusting: a substring that runs off
\ the end should come back short, not hand you the dictionary.
: SUB ( a l start n -- a2 l2 )
  SM ! SB ! SL ! SA !
  SB @ 0 MAX SB !
  SB @ SL @ > IF SL @ SB ! THEN
  SA @ SB @ +
  SM @ 0 MAX  SL @ SB @ -  MIN ;
: LEFT ( a l n -- a2 l2 ) >R 0 R> SUB ;
: RIGHT ( a l n -- a2 l2 )
  SM ! SB ! SA !
  SA @ SB @  SB @ SM @ - 0 MAX  SM @ SB @ MIN  SUB ;

: SCAN ( a l c -- i )
  SM ! SL ! SA !
  SL @ 0 ?DO
    SA @ I + C@ 127 AND SM @ = IF I UNLOOP EXIT THEN
  LOOP -1 ;

: SPLIT ( a l c -- a1 l1 a2 l2 )        \ before the char, and after it
  SM ! SL ! SA !
  SA @ SL @ SM @ SCAN DUP 0< IF
    DROP SA @ SL @  SA @ SL @ +  0
  ELSE
    SB !
    SA @ SB @  SA @ SB @ + 1+  SL @ SB @ - 1-
  THEN ;

: TRIM ( a l -- a2 l2 )
  BEGIN DUP 0> IF 2DUP + 1- C@ 32 = ELSE 0 THEN WHILE 1- REPEAT
  BEGIN DUP 0> IF OVER C@ 32 = ELSE 0 THEN WHILE 1- SWAP 1+ SWAP REPEAT ;

: UPPER ( a l -- )                      \ in place, lower to upper
  0 ?DO
    DUP I + DUP C@ 127 AND
    DUP 97 < 0= OVER 123 < AND IF 32 - THEN
    SWAP C!
  LOOP DROP ;

\ --- numbers ----------------------------------------------------------------
\ VAL, but honest about failure: Applesoft quietly returns 0 for rubbish,
\ which turns a typo into an answer.  This hands back a flag as well.
VARIABLE SN VARIABLE SNG
: S>N ( a l -- n f )
  SL ! SA ! 0 SN ! 0 SNG !
  SL @ 0= IF 0 0 EXIT THEN
  SA @ C@ 45 = IF 1 SNG ! 1 SA +! -1 SL +! THEN
  SL @ 0= IF 0 0 EXIT THEN
  SL @ 0 ?DO
    SA @ I + C@ 127 AND
    DUP 48 < OVER 57 > OR IF DROP 0 0 UNLOOP EXIT THEN
    48 - SN @ 10 * + SN !
  LOOP
  SN @ SNG @ IF NEGATE THEN -1 ;

: N>S ( n -- a l ) DUP ABS 0 <# #S ROT SIGN #> ;

\ --- somewhere to keep one --------------------------------------------------
\ Eight 64-byte slots.  Not a heap and not garbage collected: a string
\ lives in the slot you put it in until you put another one there, which
\ is the whole of the memory management and is the honest amount for a
\ machine this size.
CREATE SPACE8 512 ALLOT
: SBUF ( n -- a ) 7 AND 64 * SPACE8 + ;

\ Variables, not the return stack.  The first draft of these two juggled
\ five things through >R and R@ and was wrong in a way that reads as
\ right, which is the failure this project has made more than any other.
VARIABLE SD VARIABLE SA2 VARIABLE SL2
: SCOPY ( a l dest -- dest l )
  SD ! 63 MIN SL ! SA !
  SA @ SD @ SL @ MOVE
  SD @ SL @ ;
: SCAT ( a1 l1 a2 l2 dest -- dest l )
  SD ! SL2 ! SA2 ! SL ! SA !
  SL @ 63 MIN SL !                      \ the slot is 64 bytes and that
  SL2 @ 63 SL @ - MIN 0 MAX SL2 !       \ is the whole of the promise
  SA @ SD @ SL @ MOVE
  SA2 @ SD @ SL @ + SL2 @ MOVE
  SD @ SL @ SL2 @ + ;

: STR ( -- ) ." STRING WORDS LOADED.  SEE HELP STR." CR ;
STR
