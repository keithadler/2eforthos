\ LOOPS.FTH -- counted loops, and the one that always runs once.
\
\ Type COUNT10, EVENS, DOWN, FIRST7, TABLE or EMPTY.
\ FORGET LOP-- to reclaim the space.

: LOP-- ;

\ DO takes the limit first and the start second, and I is the index.
\ The limit is exclusive: 10 0 DO runs with I = 0 through 9.

: COUNT10 10 0 DO I . LOOP CR ;

\ +LOOP steps by whatever is on the stack, in either direction.  It stops
\ when the index crosses the boundary between limit-1 and limit, which is
\ why it works going down as well as up.

: EVENS 20 0 DO I . 2 +LOOP CR ;
: DOWN 0 10 DO I . -1 +LOOP CR ;

\ LEAVE jumps out.  UNLOOP is only needed if you EXIT the whole word from
\ inside a loop, because the loop's parameters are on the return stack.

: FIRST7 100 0 DO I . I 6 > IF LEAVE THEN LOOP CR ;

\ Nested loops: I is the inner index and J is the next one out.

: TABLE 4 1 DO 4 1 DO J I * 4 .R LOOP CR LOOP ;

\ THE TRAP.  DO always runs at least once, so 0 0 DO counts all the way
\ round to 65536.  ?DO checks first and skips the body entirely when the
\ limit equals the start, which is what a loop over a possibly-empty count
\ wants.  Compare these two -- only one of them is safe.

: EMPTY 0 0 ?DO ." NEVER" LOOP ." NOTHING HAPPENED, WHICH IS RIGHT" CR ;

." LOADED.  TYPE COUNT10, EVENS, DOWN, FIRST7, TABLE OR EMPTY" CR
