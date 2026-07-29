\ MATH.FTH -- arithmetic, and the two traps in it.
\
\ Type DIVISION, SCALING or SIZES.  FORGET MTH-- to reclaim the space.

: MTH-- ;

\ TRAP ONE.  Division is floored: the quotient rounds toward negative
\ infinity and the remainder takes the sign of the divisor.  So -10 3 /MOD
\ is 2 and -4, not -1 and -3.  SM/REM truncates toward zero if that is what
\ you want.

: SHOWDIV ( n1 n2 -- ) 2DUP ." (" SWAP 4 .R ."  / " 4 .R ." ) = "
  /MOD 4 .R ."  rem " 4 .R CR ;   \ /MOD leaves the remainder under the
                                  \ quotient, so the quotient prints first

: DIVISION
  10 3 SHOWDIV
  -10 3 SHOWDIV
  10 -3 SHOWDIV
  -10 -3 SHOWDIV ;

\ TRAP TWO.  A cell is sixteen bits, so 300 * 200 does not fit.  */ keeps a
\ 32-bit intermediate, which is what scaling a coordinate needs: to take
\ 17/8 of something, say 17 8 */ and not 17 * 8 / .

: SCALING
  ." 300 * 200 / 100, the wrong way: " 300 200 * 100 / . CR
  ." 300 * 200 / 100, with */      : " 300 200 100 */ . CR ;

\ UM* and UM/MOD are the unsigned primitives underneath all of it.  A double
\ is two cells, low pushed first, so the high one is on top.

: SIZES
  ." 1000 * 1000 as a double: " 1000 1000 UM* .S CR 2DROP
  ." and back again:          " 16960 15 1000 UM/MOD SWAP DROP . CR ;

." LOADED.  TYPE DIVISION, SCALING OR SIZES" CR
