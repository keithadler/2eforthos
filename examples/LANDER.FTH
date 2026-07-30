\ LANDER.FTH -- lunar lander, on the 560x192 hi-res screen.
\
\ The physics is fixed point, six bits of fraction: positions and
\ velocities are kept in 64ths of a pixel, so gravity can be gentler
\ than one pixel per frame and the touchdown can be judged finely.
\ Sixty-fourths and not two-fifty-sixths, because 559 pixels times 256
\ does not fit a cell -- and the pixel is taken back out with unsigned
\ division, because 559 times 64 is past what a signed cell calls
\ positive.
\
\ A or the game button burns the engine, Z and X nudge sideways.
\ Put it down on the flat pad, slowly, or become a crater.
\
\ LANDER plays.  Every piece has a name, so the pieces can be tested.

: LANDER-- ;                            \ FORGET LANDER-- removes the game

\ KEYC reads the latch without waiting, so an end screen would vanish
\ before anyone saw it.  This waits.
: PAUSE ( -- ) BEGIN KEY? UNTIL KEYC DROP ;

\ --- the moon ---------------------------------------------------------------
\ Heights every 16 pixels, 36 posts joined by lines; two spans around the
\ pad post are held level, and that is where you land.
36 CONSTANT NPOSTS
CREATE TERR NPOSTS ALLOT
VARIABLE PAD#                           \ which post the pad starts at

: TH ( i -- y ) TERR + C@ ;
: TH! ( y i -- ) TERR + C! ;

: MAKE-MOON ( -- )
  RND 30 MOD 3 + PAD# !
  NPOSTS 0 DO
    140 RND 40 MOD + I TH!
  LOOP
  160 PAD# @ TH!  160 PAD# @ 1+ TH!  160 PAD# @ 2 + TH! ;

: DRAW-MOON ( -- )
  3 HCOLOR
  NPOSTS 1- 0 DO
    I 16 * I TH  I 1+ 16 * I 1+ TH  HLINE2
  LOOP
  PAD# @ 16 * 1+  PAD# @ 2 + 16 * 1-  161 HLINE ;

\ --- the ship ---------------------------------------------------------------
\ Drawn in XOR, so drawing it where it stands takes it off the screen and
\ the moon underneath survives.  FLAME remembers whether the last drawing
\ included the exhaust, so the erase matches the draw exactly.
VARIABLE SX VARIABLE SY                 \ position, 64ths of a pixel
VARIABLE VX VARIABLE VY                 \ velocity, 64ths per step
VARIABLE FUEL VARIABLE THR VARIABLE SIDE
VARIABLE FLAME

: PX ( -- x ) SX @ 64 U/MOD NIP ;
: PY ( -- y ) SY @ 64 U/MOD NIP ;

: SHIP ( -- )                           \ XOR the ship at PX PY
  PX 6 - PY 6 +  PX PY 6 -  HLINE2
  PX PY 6 -  PX 6 + PY 6 +  HLINE2
  PX 6 - PX 6 + PY 6 + HLINE
  FLAME @ IF PX PY 7 +  PX PY 11 +  HLINE2 THEN ;

\ --- one step of physics ----------------------------------------------------
2 CONSTANT GRAV                         \ 64ths of a pixel per step per step
6 CONSTANT BURN

: PHYS ( -- )
  GRAV VY +!
  THR @ FUEL @ 0> AND IF
    BURN NEGATE VY +!  -2 FUEL +!  THEN
  SIDE @ FUEL @ 0> AND IF
    SIDE @ 2* VX +!  -1 FUEL +!  THEN
  VX @ SX +!  VY @ SY +! ;

\ The terrain under the ship, by interpolating the two nearest posts.
: GROUND ( -- y )
  PX 16 /  DUP TH  OVER 1+ NPOSTS 1- MIN TH
  OVER -  PX 16 MOD  16 */  +  SWAP DROP ;

: ONPAD? ( -- f )
  PX 16 / PAD# @ < 0=  PX 16 / PAD# @ 2 + <  AND ;
: SOFT? ( -- f )
  VY @ 75 <  VX @ ABS 50 <  AND ;
: DOWN? ( -- f ) PY 6 + GROUND < 0= ;

\ --- the loop ---------------------------------------------------------------
\ The console's . prints to the text page, which is not the screen you are
\ looking at.  TEMIT is the graphics screen's character, so numbers get a
\ small printer of their own here.
: TTYPE ( addr len -- ) 0 ?DO DUP I + C@ TEMIT LOOP DROP ;
: TN ( n -- ) DUP ABS 0 <# #S ROT SIGN #> TTYPE 32 TEMIT ;
: HUD ( -- )
  0 0 TAT T." FUEL "  FUEL @ 0 MAX TN  T." ALT "
  GROUND PY - 0 MAX TN  T." VY " VY @ TN  T."   " ;

: KEYS ( -- )
  0 THR ! 0 SIDE !
  BTN IF 1 THR ! THEN
  KEY? IF KEYC CASE
    65 OF 1 THR ! ENDOF                 \ A burns
    90 OF -1 SIDE ! ENDOF               \ Z pushes left
    88 OF 1 SIDE ! ENDOF                \ X pushes right
  ENDCASE THEN ;

: SPLAT ( -- )
  0 HXOR
  30 5 DO PX PY I HCIRCLE 40 8 TONE 3 +LOOP
  10 10 TAT T." A NEW CRATER.  LANDER AGAIN?" ;

: SETTLE ( -- )
  0 HXOR  10 10 TAT T." THE EAGLE HAS LANDED. "
  100 30 TONE 80 30 TONE 60 60 TONE ;

: START ( -- )
  HGR MAKE-MOON DRAW-MOON
  40 64 * SX !  20 64 * SY !
  45 VX !  0 VY !  800 FUEL !  0 THR ! 0 SIDE ! 0 FLAME !
  -1 HXOR ;

: LANDER ( -- )
  START
  BEGIN
    SHIP VBL VBL SHIP                   \ on, a frame, off again
    KEYS PHYS
    THR @ FUEL @ 0> AND FLAME !
    HUD
  DOWN? UNTIL
  SHIP                                  \ leave it on the surface
  ONPAD? SOFT? AND IF SETTLE ELSE SPLAT THEN
  PAUSE TEXT ;

: LHELP ." LANDER PLAYS.  A OR BUTTON BURNS, Z AND X STEER." CR ;
LHELP
