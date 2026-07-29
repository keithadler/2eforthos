\ FLOAT.FTH -- the floating point that came out of the ROM.
\
\ Applesoft's five-byte floats, called rather than reimplemented: several
\ kilobytes of debugged arithmetic and transcendentals that were already in
\ the machine.  They live on their own stack, eight deep, because a float
\ does not fit a cell.
\
\ F>S truncates rather than rounding.  That is Applesoft's behaviour and it
\ matters: sixty times the cosine of zero is 59, not 60, because COS(0) comes
\ back as 0.99999.  Multiply by a thousand before converting when you want to
\ see the difference.
\
\ Type CONSTANTS, TRIG or ROOTS.  FORGET FLT-- to reclaim the space.

: FLT-- ;

: PI ( -- )  1 S>F FATN 4 S>F F* ;      \ exact, not a typed-in constant
: E  ( -- )  1 S>F FEXP ;

: CONSTANTS
  ." PI       = " PI F. CR
  ." E        = " E F. CR
  ." PI x 1000 as an integer = " PI 1000 S>F F* F>S . CR
  ." E  x 1000 as an integer = " E 1000 S>F F* F>S . CR ;

: DEG>RAD ( -- ) PI F* 180 S>F F/ ;
: SHOWSIN ( deg -- )
  DUP 4 .R ." deg  sin=" S>F DEG>RAD FSIN 1000 S>F F* F>S 6 .R CR ;
: TRIG
  ." sine, scaled by a thousand" CR
  0 SHOWSIN 30 SHOWSIN 45 SHOWSIN 60 SHOWSIN 90 SHOWSIN ;

: ROOTS
  ." sqrt 2 squared = " 2 S>F FSQRT FDUP F* F. CR
  ." sqrt 144       = " 144 S>F FSQRT F. CR
  ." 22/7           = " 22 S>F 7 S>F F/ F. CR
  ." ln 20          = " 20 S>F FLN F. CR ;

." LOADED.  TYPE CONSTANTS, TRIG OR ROOTS" CR
