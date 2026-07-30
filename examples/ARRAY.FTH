\ ARRAY.FTH -- arrays with bounds, the DIM Applesoft had and this did not.
\
\ CREATE and ALLOT give you the space; what they do not give you is any
\ opinion about how big it was.  `20 ARRAY SCORES` makes twenty cells and
\ a word that hands back the address of one -- and refuses, loudly, if the
\ index is not in it.  Applesoft's ?BAD SUBSCRIPT was worth having.
\
\ Type ARRAY and this loads itself.
\
\   n ARRAY NAME          n cells, i NAME gives an address
\   n CARRAY NAME         n bytes, for characters
\   r c 2ARRAY NAME       r rows of c, i j NAME gives an address
\
\ The count sits in the first cell of the body, which is why NAME is
\ >BODY 2 + and not >BODY.  A bounds failure THROWs rather than printing:
\ a word that checked and then carried on regardless would be worse than
\ not checking.

: ARRAY-- ;

: ?RANGE ( i n -- i )                   \ i must be 0 <= i < n
  2DUP U< 0= IF
    ." SUBSCRIPT " SWAP . ." NOT UNDER " . CR  ABORT
  THEN DROP ;

\ One dimension.  The body is [count][cells...], so the data starts two
\ bytes in.
: ARRAY ( n -- )
  CREATE DUP , CELLS ALLOT
  DOES> ( i addr -- addr' )
    DUP @ >R  2 +  SWAP R> ?RANGE CELLS + ;

: CARRAY ( n -- )
  CREATE DUP , ALLOT
  DOES> DUP @ >R  2 +  SWAP R> ?RANGE + ;

\ Two dimensions, row-major: [rows][cols][cells...].  Both subscripts are
\ checked, because catching only one of them is how a walk off the end of
\ a row quietly reads the next one.
\
\ Variables rather than stack juggling: this has five things in the air
\ at once and that is exactly the shape this project keeps getting wrong.
VARIABLE A2R VARIABLE A2C VARIABLE A2B
: 2ARRAY ( rows cols -- )
  CREATE OVER , DUP , * CELLS ALLOT
  DOES> ( i j addr -- addr' )
    DUP @ A2R !                         \ rows
    DUP 2 + @ A2C !                     \ cols
    4 + A2B !                           ( i j )
    A2C @ ?RANGE                        \ j against cols
    SWAP A2R @ ?RANGE                   \ i against rows
    A2C @ * + CELLS A2B @ + ;

: AHELP
  ." N ARRAY NAME     N CELLS, I NAME IS AN ADDRESS" CR
  ." N CARRAY NAME    N BYTES" CR
  ." R C 2ARRAY NAME  I J NAME IS AN ADDRESS" CR
  ." A SUBSCRIPT OUT OF RANGE STOPS THE LINE." CR ;
AHELP
