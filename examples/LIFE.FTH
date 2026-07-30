\ LIFE.FTH -- Conway's Game of Life, on the 40x40 lo-res screen.
\
\ The rules fit in a sentence -- a live cell with two or three neighbours
\ lives, a dead cell with exactly three is born -- and everything else in
\ the universe follows.  The world is twenty-two on a side with dead
\ edges, centred on the lo-res screen; two generations sit side by side
\ so one can be read while the next is written, and only the cells that
\ CHANGED get replotted.  A generation is a few seconds of honestly
\ interpreted Forth -- watch it think.
\
\   LIFE           a random soup, running until any key
\   GLIDER LIFE    clear space, one glider crossing it
\   GEN            one generation by hand, for watching closely

: LIFE-- ;

22 CONSTANT WSZ
CREATE WA WSZ WSZ * ALLOT
CREATE WB WSZ WSZ * ALLOT
VARIABLE CUR VARIABLE NXT

: CELL ( x y buf -- addr ) -ROT WSZ * + + ;
: WCLR ( -- ) WA WSZ WSZ * 0 FILL  WB WSZ WSZ * 0 FILL ;

: NBORS ( x y -- n )                    \ the eight around, current world
  0
  2 -1 DO 2 -1 DO
    I J OR IF
      2 PICK I +  2 PICK J +  CUR @ CELL C@ +
    THEN
  LOOP LOOP
  -ROT 2DROP ;

: RULE ( alive n -- alive' )            \ the whole game, one line
  SWAP IF DUP 2 = SWAP 3 = OR ELSE 3 = THEN 1 AND ;

: GEN ( -- )                            \ one generation, changes plotted
  WSZ 1- 1 DO WSZ 1- 1 DO
    I J CUR @ CELL C@  DUP  I J NBORS RULE
    DUP I J NXT @ CELL C!
    2DUP <> IF
      DUP IF 15 ELSE 0 THEN GCOLOR!
      I 9 +  J 9 +  GPLOT
    THEN 2DROP
  LOOP LOOP
  CUR @ NXT @ CUR ! NXT ! ;

: SEED ( -- )                           \ a third of the middle, at random
  WSZ 4 - 4 DO WSZ 4 - 4 DO
    RND 3 MOD 0= 1 AND  I J WA CELL C!
  LOOP LOOP ;

: GLIDER ( -- )                         \ the five-cell spaceship
  WCLR
  1 6 5 WA CELL C!  1 7 6 WA CELL C!
  1 5 7 WA CELL C!  1 6 7 WA CELL C!  1 7 7 WA CELL C!
  WA CUR ! WB NXT ! ;

: DRAW-ALL ( -- )
  WSZ 0 DO WSZ 0 DO
    I J CUR @ CELL C@ IF 15 GCOLOR! I 9 + J 9 + GPLOT THEN
  LOOP LOOP ;

: LIFE ( -- )
  \ WCLR before SEED, not just SEED: the world is dictionary space and
  \ ALLOT does not promise zeros, so the border SEED never touches came
  \ up as whatever the last program left there -- a tidy dashed line
  \ along the bottom of the first screenshot, which is not Life.
  CUR @ 0= IF WA CUR ! WB NXT ! WCLR SEED THEN
  GR 0 GCLS DRAW-ALL
  BEGIN GEN KEY? UNTIL KEYC DROP
  TEXT 0 CUR ! ;

: LIFEHELP ." LIFE RUNS A SOUP.  GLIDER LIFE SENDS THE SHIP." CR ;
LIFEHELP
