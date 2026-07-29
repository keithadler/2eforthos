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
