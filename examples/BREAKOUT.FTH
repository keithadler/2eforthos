\ BREAKOUT.FTH -- the game Woz built the hardware for.
\
\ Fourteen columns and six rows of bricks, a paddle on the game port,
\ a ball that speeds nothing up and slows nothing down: the joy is all
\ in the angles.  The ball is a small XOR block, so flying over a score
\ digit does not eat it.
\
\ BREAKOUT plays.  The paddle knob moves the bat; any key launches.

: BREAKOUT-- ;

\ KEYC reads the latch without waiting, so an end screen would vanish
\ before anyone saw it.  This waits.
: PAUSE ( -- ) BEGIN KEY? UNTIL KEYC DROP ;

\ --- the wall ---------------------------------------------------------------
14 CONSTANT BCOLS   6 CONSTANT BROWS
40 CONSTANT BW      8 CONSTANT BH
16 CONSTANT BTOP
CREATE BRICKS BCOLS BROWS * ALLOT
VARIABLE NLEFT VARIABLE SCORE VARIABLE BALLS

: BRICK ( c r -- addr ) BCOLS * + BRICKS + ;
: BX ( c -- x ) BW * ;
: BY ( r -- y ) BH * BTOP + ;

\ Variables, not stack juggling: this project has a poor record with
\ four things in the air at once, and HBOX wants four corners.
VARIABLE DBX VARIABLE DBY
: DRAW-BRICK ( c r -- )
  BY DBY !  BX DBX !
  DBX @ 2 +  DBX @ BW + 2 -
  DBY @ 1+   DBY @ BH + 2 -  HBOX ;

: WALL ( -- )
  BCOLS BROWS * NLEFT !
  BROWS 0 DO BCOLS 0 DO
    1 I J BRICK C!  I J DRAW-BRICK
  LOOP LOOP ;

\ --- the bat ----------------------------------------------------------------
64 CONSTANT BATW
VARIABLE BATX VARIABLE OLDBAT

: BAT-AT ( -- x ) 0 PADDLE 495 255 */ ;  \ 0..255 -> 0..495
: DRAW-BAT ( x -- ) DUP BATW + 186 HLINE ;
: BAT ( -- )                            \ move it only when it moved
  BAT-AT DUP OLDBAT @ <> IF
    OLDBAT @ DRAW-BAT  DUP DRAW-BAT  DUP OLDBAT !
  THEN BATX ! ;

\ --- the ball ---------------------------------------------------------------
VARIABLE X VARIABLE Y VARIABLE DX VARIABLE DY

: BALL ( -- ) X @ DUP 3 + Y @ DUP 2 + HBOX ;   \ XOR block

: SERVE ( -- )
  BATX @ 30 + X !  120 Y !
  RND 1 AND IF 3 ELSE -3 THEN DX !  -2 DY ! ;

\ Which brick is under the ball, or -1.
: HITS ( -- addr | 0 )
  Y @ BTOP < 0=  Y @ BROWS BH * BTOP + <  AND IF
    X @ BW /  Y @ BTOP - BH /  2DUP BRICK C@ IF
      BRICK
    ELSE 2DROP 0 THEN
  ELSE 0 THEN ;

: KILL ( addr -- )                      \ take one brick off the wall
  DUP C@ 0= IF DROP EXIT THEN
  0 OVER C!
  BRICKS - DUP BCOLS MOD SWAP BCOLS /   ( c r )
  DRAW-BRICK                            \ XOR off
  -1 NLEFT +!  10 SCORE +!  30 4 TONE
  DY @ NEGATE DY ! ;

: BOUNCE ( -- )
  X @ 3 <  X @ 553 > OR IF DX @ NEGATE DX ! 20 2 TONE THEN
  Y @ 12 < IF DY @ NEGATE DY ! 20 2 TONE THEN
  Y @ 183 < 0=  Y @ 186 < AND
  X @ BATX @ < 0=  X @ BATX @ BATW + > 0= AND AND IF
    DY @ ABS NEGATE DY !  50 2 TONE
    \ the third of the bat you hit picks the angle out
    X @ BATX @ - BATW 3 / /  1- 3 *  DX @ 0< IF ABS THEN
    DUP IF DX ! ELSE DROP THEN
  THEN ;

: TTYPE ( addr len -- ) 0 ?DO DUP I + C@ TEMIT LOOP DROP ;
: TN ( n -- ) DUP ABS 0 <# #S ROT SIGN #> TTYPE 32 TEMIT ;
: SHOW ( -- )
  0 0 TAT T." SCORE " SCORE @ TN  T." BALLS " BALLS @ TN ;

: STEP ( -- )
  BALL
  DX @ X +!  DY @ Y +!
  BOUNCE  HITS ?DUP IF KILL THEN
  BALL ;

: ONE-BALL ( -- )                       \ until it gets past the bat
  SERVE BALL
  BEGIN
    VBL BAT STEP SHOW
    NLEFT @ 0= IF EXIT THEN
  Y @ 189 > UNTIL
  BALL ;

: BREAKOUT ( -- )
  HGR 3 HCOLOR -1 HXOR
  0 SCORE !  3 BALLS !  0 OLDBAT !
  WALL  BAT-AT DUP DRAW-BAT OLDBAT !
  BEGIN
    ONE-BALL
    NLEFT @ 0= IF
      4 10 TAT T." THE WALL IS DOWN.  WOZ WOULD NOD." PAUSE TEXT EXIT
    THEN
    -1 BALLS +!
  BALLS @ 0= UNTIL
  4 10 TAT T." OUT OF BALLS.  SCORE " SCORE @ TN
  PAUSE TEXT ;

: BHELP ." BREAKOUT PLAYS.  THE PADDLE KNOB IS THE BAT." CR ;
BHELP
