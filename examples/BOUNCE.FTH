\ BOUNCE.FTH -- an animated sprite, erased by drawing it again.
\
\ In XOR mode a shape drawn twice in the same place leaves the screen as it
\ was found, so no background needs saving and no rectangle needs clearing.
\ VBL waits for the video counter, which paces the whole thing off the same
\ crystal that drives the display.
\
\ Type BOUNCE.  Any key stops it.  FORGET BNC-- to reclaim the space.
: BNC-- ;
CREATE BALL
  $3C C, $7E C, $FF C, $FF C, $FF C, $FF C, $7E C, $3C C,
VARIABLE BX VARIABLE BY VARIABLE DX VARIABLE DY
: SHOW BALL 8 8 BX @ BY @ BLIT ;
: STEP
  BX @ DX @ + BX !  BY @ DY @ + BY !
  BX @ 0< IF 0 BX ! DX @ NEGATE DX ! THEN
  BX @ 551 > IF 551 BX ! DX @ NEGATE DX ! THEN
  BY @ 0< IF 0 BY ! DY @ NEGATE DY ! THEN
  BY @ 183 > IF 183 BY ! DY @ NEGATE DY ! THEN ;
: BOUNCE HGR HCLS 3 HCOLOR -1 HXOR
  0 BX ! 0 BY ! 7 DX ! 3 DY !
  SHOW
  2000 0 DO SHOW STEP SHOW VBL KEY? IF LEAVE THEN LOOP
  0 HXOR KEY? IF KEYC DROP THEN ;
." LOADED.  TYPE BOUNCE" CR
