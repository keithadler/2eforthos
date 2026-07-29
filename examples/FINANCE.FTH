\ FINANCE.FTH -- the money arithmetic, on Applesoft's floating point.
\
\ Applesoft has `^` and gets compound interest for free; this system has
\ FEXP and FLN, which is the same thing spelled out: x^n is exp(n ln x).
\ That one word is what the rest of this is built from -- without a power
\ there is no amortization, no present value and no declining balance.
\
\ Rates are basis points, so five per cent is 500.  Integers in, a float on
\ the float stack out: finish with F. to print it or F>S to round it down.
\
\ Type FINANCE-DEMO.  FORGET FIN-- to reclaim the space.

: FIN-- ;

VARIABLE FPRIN VARIABLE FRATE VARIABLE FPER

: F** ( -- )                     \ float stack: x n -- x^n
  FSWAP FLN F* FEXP ;
: RATE1 ( -- )                   \ float stack: -- 1+i
  FRATE @ S>F 10000 S>F F/ 1 S>F F+ ;
: FRATE> ( -- )                  \ float stack: -- i
  FRATE @ S>F 10000 S>F F/ ;
: 3ARGS ( a b c -- ) FPER ! FRATE ! FPRIN ! ;

\ What a principal grows to.
: COMPOUND ( principal bp periods -- )
  3ARGS  RATE1 FPER @ S>F F**  FPRIN @ S>F F* ;

\ What a level payment accumulates to, and what it is worth today.
: FV ( pmt bp periods -- )
  3ARGS  RATE1 FPER @ S>F F** 1 S>F F-  FRATE> F/  FPRIN @ S>F F* ;
: PV ( pmt bp periods -- )
  3ARGS  1 S>F RATE1 FPER @ NEGATE S>F F** F-  FRATE> F/  FPRIN @ S>F F* ;

\ The level payment that clears a loan.
: PMT ( principal bp periods -- )
  3ARGS
  FPRIN @ S>F FRATE> F*
  1 S>F RATE1 FPER @ NEGATE S>F F** F-
  F/ ;

\ Depreciation: straight line, and sum of the years' digits.
: SLN ( cost salvage life -- ) >R - S>F R> S>F F/ ;
: SYD ( cost salvage life period -- )
  >R >R - S>F                    \ cost less salvage
  R> R@ SWAP - 1+ S>F F*         \ times the years remaining
  R@ R@ 1+ * 2/ S>F F/  R> DROP ;

: FINANCE-DEMO
  ." 100000 AT 5 PER CENT FOR 30 YEARS" CR
  ."   GROWS TO      " 100000 500 30 COMPOUND F. CR
  ."   YEARLY PAYMENT" 100000 500 30 PMT F. CR
  ." 1000 A YEAR FOR 10 YEARS AT 5 PER CENT" CR
  ."   IS WORTH NOW  " 1000 500 10 PV F. CR
  ."   ACCUMULATES TO" 1000 500 10 FV F. CR
  ." A 9000 ASSET, 1000 SALVAGE, 5 YEARS" CR
  ."   STRAIGHT LINE " 9000 1000 5 SLN F. CR
  ."   FIRST YEAR SYD" 9000 1000 5 1 SYD F. CR ;
." LOADED.  TYPE FINANCE-DEMO" CR
