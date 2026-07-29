\ STRINGS.FTH -- text, and numbers turned into text.
\
\ Type SHOWSTR, MONEY or BASES.  FORGET STR-- to reclaim the space.

: STR-- ;

\ S" leaves an address and a length.  TYPE prints that pair.  C" leaves the
\ address of a counted string -- a length byte followed by the text -- and
\ COUNT turns one into the pair TYPE wants.

: SHOWSTR
  S" ADDRESS AND LENGTH" TYPE CR
  C" A COUNTED STRING" COUNT TYPE CR
  S" LENGTH ONLY: " TYPE  S" TWELVE CHARS" NIP . CR ;

\ Pictured numeric output builds a string a digit at a time, backwards,
\ which is the order division produces them in.  <# starts, # takes one
\ digit, #S takes the rest, HOLD inserts any character, SIGN adds a minus if
\ the number under it was negative, and #> finishes and hands back the pair.
\
\ It works on a double, so a single has to be widened first -- 0 for
\ unsigned, S>D for signed.

: MONEY ( n -- )    \ pence in, pounds and pence out
  DUP ABS 0
  \ Digits are held backwards, so the last thing held prints first: the
  \ sign has to go after the dollar, not before it.
  <# # # [CHAR] . HOLD #S [CHAR] $ HOLD ROT SIGN #> TYPE CR ;

: BASES ( n -- )
  ." DECIMAL " DUP .
  ." HEX " DUP 16 BASE ! . 10 BASE !
  ." BINARY " 2 BASE ! . 10 BASE ! CR ;

." LOADED.  TRY  SHOWSTR   1234 MONEY   255 BASES" CR
