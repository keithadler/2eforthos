\ STACK.FTH -- the data stack, which is where everything happens.
\
\ Forth is postfix: values are pushed, and words consume them from the top.
\ A stack comment says what a word expects and leaves, with the top of the
\ stack on the right:
\
\   ( n1 n2 -- n3 )     takes two, leaves one
\
\ .S prints the stack without disturbing it, deepest first.  It is the single
\ most useful word when something is not doing what you expected.
\
\ Type SHOW1 through SHOW5, or ALL.  FORGET STK-- to reclaim the space.

: STK-- ;

: SHOW1 ." 1 2 3 -> " 1 2 3 .S CR 2DROP DROP ;
: SHOW2 ." DUP     -> " 1 2 DUP .S CR 2DROP DROP ;
: SHOW3 ." SWAP    -> " 1 2 SWAP .S CR 2DROP ;
: SHOW4 ." OVER    -> " 1 2 OVER .S CR 2DROP DROP ;
: SHOW5 ." ROT     -> " 1 2 3 ROT .S CR 2DROP DROP ;

\ Reaching deeper than the top three:  2 PICK copies the third item,
\ 2 ROLL moves it.  0 PICK is DUP and 2 ROLL is ROT.

: SHOW6 ." 2 PICK  -> " 1 2 3 2 PICK .S CR 2DROP 2DROP ;
: SHOW7 ." 2 ROLL  -> " 1 2 3 2 ROLL .S CR 2DROP DROP ;

: ALL SHOW1 SHOW2 SHOW3 SHOW4 SHOW5 SHOW6 SHOW7 ;

." LOADED.  TYPE ALL" CR
