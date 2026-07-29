\ CONDS.FTH -- choosing, and how CASE is only a library word.
\
\ Type SIGNOF, GRADE or NAMEOF.  FORGET CND-- to reclaim the space.

: CND-- ;

\ A flag is 0 for false and -1 for true.  Any non-zero value counts as true
\ when tested, so 0= is the way to invert one.
\ IF consumes the flag.  ELSE is optional.  THEN closes it -- it means
\ "and then carry on", not "do this".

: SIGNOF ( n -- )
  DUP 0< IF ." NEGATIVE"
  ELSE DUP 0= IF ." ZERO"
  ELSE ." POSITIVE"
  THEN THEN DROP CR ;

\ Nesting gets unreadable quickly, which is what CASE is for.

: GRADE ( n -- )
  DUP 90 < 0= IF ." A"
  ELSE DUP 80 < 0= IF ." B"
  ELSE DUP 70 < 0= IF ." C"
  ELSE ." F"
  THEN THEN THEN DROP CR ;

\ CASE is not built into this system.  It is four lines of Forth, in
\ SYSTEM.FTH, written out of IF and ELSE and THEN with POSTPONE -- which is
\ the whole point of the language: control structures are library code.
\
\ At ENDCASE the selector is still on the stack, and ENDCASE drops it.

: NAMEOF ( n -- ) CASE
    1 OF ." ONE" ENDOF
    2 OF ." TWO" ENDOF
    3 OF ." THREE" ENDOF
    ." SOMETHING ELSE"
  ENDCASE CR ;

." LOADED.  TRY  -5 SIGNOF   85 GRADE   2 NAMEOF" CR
