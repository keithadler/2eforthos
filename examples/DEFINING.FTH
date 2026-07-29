\ DEFINING.FTH -- words that make words.  This is the part of Forth that
\ has no equivalent in most languages.
\
\ Type SHOWARR, SHOWCOL or SHOWMSG.  FORGET DEF-- to reclaim the space.

: DEF-- ;

\ CREATE makes a word that pushes the address of whatever follows it.
\ DOES> replaces that behaviour with your own: everything after DOES> runs
\ when the new word runs, and is handed that same address.
\
\ So ARRAY is a word that makes array words.  CREATE and CELLS ALLOT happen
\ once, when SCORES is defined; SWAP CELLS + happens every time SCORES runs.

: ARRAY ( n -- ) CREATE CELLS ALLOT DOES> ( i -- addr ) SWAP CELLS + ;

5 ARRAY SCORES

: SHOWARR
  10 0 SCORES !  20 1 SCORES !  30 2 SCORES !
  ." SCORES: " 3 0 DO I SCORES @ . LOOP CR ;

\ The same shape gives you constants that do something extra.  Here the
\ stored value is a colour, and the word sets it rather than pushing it.

: COLOUR ( n -- ) CREATE , DOES> @ HCOLOR ;
0 COLOUR BLACK
3 COLOUR WHITE

: SHOWCOL
  ." WHITE AND BLACK ARE NOW WORDS THAT SET HCOLOR." CR
  ." TRY:  HGR WHITE 100 400 50 150 HBOX  BLACK 200 300 80 120 HBOX  TEXT" CR ;

\ And a defining word can store a string as easily as a number.

: MESSAGE ( -- ) CREATE  DOES> COUNT TYPE CR ;

." LOADED.  TYPE SHOWARR OR SHOWCOL" CR
