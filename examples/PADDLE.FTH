\ PADDLE.FTH -- reading the game port, and drawing what it says.
\
\ PADDLE takes a channel number and gives back 0..255.  It waits out the
\ port's timer afterwards: the reading returns the moment its capacitor has
\ discharged, so a small value returns early and leaves the shared timer
\ still charged -- and the next channel then reads back skewed by the first.
\
\ Type SHOWPDL or TRAIL.  Any key stops them.  FORGET PDL-- to reclaim.

: PDL-- ;

: SHOWPDL
  ." MOVE THE STICK.  ANY KEY STOPS." CR
  BEGIN
    0 PADDLE 4 .R  1 PADDLE 4 .R  BTN IF ."  BUTTON" ELSE ."        " THEN
    13 EMIT
    KEY?
  UNTIL KEYC DROP CR ;

\ The paddle range is 0..255 and the screen is 560 by 192, so x is 17/8 of
\ the reading and y is 3/4 of it.  */ keeps the intermediate in 32 bits.

: PX ( -- x ) 0 PADDLE 17 8 */ ;
: PY ( -- y ) 1 PADDLE 3 4 */ ;

: TRAIL
  HGR HCLS 3 HCOLOR
  BEGIN PX PY HPLOT KEY? UNTIL
  KEYC DROP TEXT ;

." LOADED.  TYPE SHOWPDL OR TRAIL" CR
