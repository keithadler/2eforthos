\ HAT.FTH -- the hat, the one every Apple II drew sooner or later.
\
\ A ripple of sines seen in three-quarter view: for every point of a
\ grid, the height is the sine of the distance from the centre, and the
\ rows nearer the eye hide the rows behind them.  The hidden-line trick
\ is one byte per screen column -- the highest pixel drawn there so far
\ -- and a point only lands if it rises above that.
\
\ The arithmetic is Applesoft's own five-byte floating point, called in
\ the ROM, which is exactly what drew it in 1978 -- just with different
\ words in front of it.  HAT draws; it takes a couple of minutes, and
\ it took longer in BASIC.

: HAT-- ;

\ KEYC reads the latch without waiting, so an end screen would vanish
\ before anyone saw it.  This waits.
: PAUSE ( -- ) BEGIN KEY? UNTIL KEYC DROP ;

CREATE HMAX 560 ALLOT                   \ per column: lowest y drawn yet

: HCLR ( -- ) HMAX 560 191 FILL ;

\ Round to the nearest pixel rather than truncate -- half a pixel of
\ droop on every point makes a surface look moth-eaten.  GFXLIB has
\ this word too; it is two cells, so owning a copy beats depending.
: F>S+ ( -- n )  1 S>F 2 S>F F/ F+ F>S ;

\ height of the surface at grid point ( x z ), both about -70..70.
\ The sombrero is sin(r)/r: full height at the centre, through zero at
\ about r of 47, and the negative lobe past it is the brim.  The grid
\ never lands exactly on the centre, but the guard keeps the division
\ honest for anyone who changes the steps.
: ALT ( x z -- y )
  OVER 0= OVER 0= AND IF 2DROP 30 EXIT THEN
  DUP * SWAP DUP * +                    \ x*x + z*z
  S>F FSQRT                             \ f: r, in grid units
  67 S>F 1000 S>F F/ F*                 \ f: a = r/15, 4.7 at the corner
  FDUP FSIN FSWAP F/                    \ f: sin(a)/a
  30 S>F F* F>S+ ;                      \ a 30-pixel crown

\ One row of the grid, front to back handled by the caller's order.
\ The three-quarter view: x spreads doubled, z walks the row back and
\ pushes it up the screen and slightly across.
VARIABLE HZ
: HATROW ( z -- )
  HZ !
  71 -70 DO
    I HZ @ ALT                          ( y-swell )
    110 SWAP -  HZ @ 2/ -               ( screen-y )
    I 2* 280 +  HZ @ 2/ +              ( sy sx )
    OVER DUP 0 < 0= SWAP 192 < AND IF
      2DUP HMAX + C@ < IF               \ above everything drawn here
        2DUP SWAP HPLOT
        2DUP HMAX + C!
      THEN
    THEN 2DROP
  2 +LOOP ;

: HAT ( -- )
  HGR HCLS 3 HCOLOR HCLR
  71 -70 DO I HATROW 4 +LOOP
  0 0 TAT T." THE HAT.  ANY KEY." PAUSE TEXT ;

: HATHELP ." HAT DRAWS THE CLASSIC.  GIVE IT TWO MINUTES." CR ;
HATHELP
