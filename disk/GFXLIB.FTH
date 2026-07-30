\ GFXLIB.FTH -- the shapes and the sprite support the kernel does not carry.
\
\ Load it when you need it; FORGET GLB-- gives the space back.
\ Type GFXLIB-DEMO to see all of it at once.

: GLB-- ;

\ --- polygons --------------------------------------------------------------
\ Points are cell pairs in memory: x y x y ...  HPOLY closes the shape,
\ HPOLYLINE leaves it open.
VARIABLE PGA VARIABLE PGN
: PT ( i -- x y ) 4 * PGA @ + DUP @ SWAP 2 + @ ;
: HPOLYLINE ( addr n -- )
  PGN ! PGA !
  PGN @ 1- 0 ?DO I PT I 1+ PT HLINE2 LOOP ;
: HPOLY ( addr n -- )
  2DUP HPOLYLINE
  PGN ! PGA !
  PGN @ 1- PT 0 PT HLINE2 ;

\ --- ellipses and arcs -----------------------------------------------------
\ A circle drawn with the x coordinate scaled: cheap, and exact enough at
\ this resolution.  HCIRCLE is in the kernel and does the hard part.
VARIABLE ELX VARIABLE ELY VARIABLE ELA VARIABLE ELB

\ The parametric form needs a sine table, which is more than this is worth.
\ An ellipse is drawn instead as a run of horizontal spans, one per row:
\ for each y, x = a * sqrt(1 - y^2/b^2), and the square root is by search
\ because there is no SQRT in the kernel.
: ISQRT ( n -- root ) 0 BEGIN 1+ DUP DUP * 2 PICK > UNTIL 1- NIP ;
: HELLIPSE ( x y a b -- )
  ELB ! ELA ! ELY ! ELX !
  ELB @ 1+ 0 ?DO
    ELB @ DUP * I DUP * - 0 MAX          ( b^2 - y^2 )
    ELA @ DUP * ELB @ DUP * */           ( scaled by a^2/b^2 )
    ISQRT                                ( half-width )
    ELX @ OVER - ELX @ ROT +             ( x1 x2 )
    2DUP ELY @ I + HLINE
    ELY @ I - HLINE
  LOOP ;

\ --- arcs ------------------------------------------------------------------
\ Wanted a sine table until FSIN and FCOS turned up; now it is the parametric
\ form written out.  Pi is four times the arctangent of one, which is exact
\ rather than a constant somebody typed in.
\
\ Four degrees a step: at sixty pixels' radius that is about four pixels
\ between points, which draws as a line rather than a dotted one.
VARIABLE ACX VARIABLE ACY VARIABLE ACR
VARIABLE AD1 VARIABLE AD2
: FPI ( -- )  1 S>F FATN 4 S>F F* ;
: DEG>RAD ( -- )  FPI F* 180 S>F F/ ;
\ F>S truncates, and the transcendentals do not land on whole numbers:
\ Applesoft's COS(0) is 0.99999, so sixty times it is 59 and every arc comes
\ out a pixel small.  Adding a half first is the difference between a circle
\ and a circle that is wrong everywhere the maths was right.
: F>S+ ( -- n )  1 S>F 2 S>F F/ F+ F>S ;
: ARCPT ( deg -- x y )
  S>F DEG>RAD
  FDUP FCOS ACR @ S>F F* F>S+
  FSIN ACR @ S>F F* F>S+
  SWAP ACX @ + SWAP ACY @ + ;
\ Plotting the points leaves a dotted line -- four degrees at seventy pixels
\ is five pixels between them -- so each step draws to the one before it and
\ the arc comes out solid.  A polygon of ninety sides is a circle at this
\ resolution.
VARIABLE ANX VARIABLE ANY VARIABLE APX VARIABLE APY VARIABLE AFIRST
: ARCSTEP ( deg -- )
  ARCPT ANY ! ANX !
  AFIRST @ IF 0 AFIRST ! ELSE APX @ APY @ ANX @ ANY @ HLINE2 THEN
  ANX @ APX !  ANY @ APY ! ;
: HARC ( x y r d1 d2 -- )
  AD2 ! AD1 ! ACR ! ACY ! ACX !  -1 AFIRST !
  AD2 @ 1+ AD1 @ ?DO I ARCSTEP 4 +LOOP
  AD2 @ ARCSTEP ;                 \ the step rarely lands on the end

VARIABLE PPX VARIABLE PPY
: PIERAD ( deg -- )
  ARCPT PPY ! PPX !
  ACX @ ACY @ PPX @ PPY @ HLINE2 ;
: HPIE ( x y r d1 d2 -- )         \ the arc and both radii, for a chart
  2DUP 2>R HARC
  2R> SWAP PIERAD PIERAD ;

\ --- saving what is under a sprite -----------------------------------------
\ A byte a pixel: wasteful, but a sprite-sized block is a few hundred bytes
\ and the alternative is packing and unpacking bits for no gain.
VARIABLE BKA VARIABLE BKX VARIABLE BKY VARIABLE BKW VARIABLE BKH
: BLK-SAVE ( addr x y w h -- )
  BKH ! BKW ! BKY ! BKX ! BKA !
  BKH @ 0 ?DO BKW @ 0 ?DO
    BKX @ I + BKY @ J + HPOINT
    IF 1 ELSE 0 THEN
    BKA @ J BKW @ * + I + C!
  LOOP LOOP ;
: BLK-REST ( addr x y w h -- )
  BKH ! BKW ! BKY ! BKX ! BKA !
  BKH @ 0 ?DO BKW @ 0 ?DO
    BKA @ J BKW @ * + I + C@
    IF 3 ELSE 0 THEN HCOLOR
    BKX @ I + BKY @ J + HPLOT
  LOOP LOOP ;
: BLK-SIZE ( w h -- n ) * ;

\ --- a demonstration -------------------------------------------------------
CREATE TRI  120 , 40 ,  200 , 150 ,  40 , 150 ,
CREATE BLK 1024 ALLOT
: GFXLIB-DEMO
  HGR HCLS 3 HCOLOR
  TRI 3 HPOLY
  400 60 90 40 HELLIPSE
  400 150 30 30 HELLIPSE
  BLK 380 40 32 32 BLK-SAVE
  0 HCOLOR 380 412 40 72 HBOX
  3 HCOLOR
  BLK 100 40 32 32 BLK-REST ;
." LOADED.  TYPE GFXLIB-DEMO" CR
