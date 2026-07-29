\ LANG.FTH -- making new defining words, and CASE.
\
\ ARRAY is a word that makes words: CREATE lays down the space and DOES>
\ says what the words it made should do when they run.
\
\ Type DEMO.  FORGET LNG-- to reclaim the space.
: LNG-- ;
: ARRAY CREATE CELLS ALLOT DOES> SWAP CELLS + ;
10 ARRAY SQUARES
: FILLSQ 10 0 DO I DUP * I SQUARES ! LOOP ;
: SHOWSQ 10 0 DO I SQUARES @ 5 .R LOOP CR ;
: NAME ( n -- ) CASE
    1 OF ." ONE" ENDOF
    2 OF ." TWO" ENDOF
    3 OF ." THREE" ENDOF
    ." MANY"
  ENDCASE CR ;
: DEMO FILLSQ SHOWSQ 1 NAME 2 NAME 3 NAME 9 NAME ;
." LOADED.  TYPE DEMO" CR
