\ COMMENTS.FTH -- the two comment forms, and what they will and will not
\ swallow.  Loading this file should define three words and print one line.
\
\ FORGET CMT-- to reclaim the space.

: CMT-- ;

( A bracket comment.  It runs to the closing bracket, however many lines
  that takes -- this one takes three.  Anything inside is inert: quotes,
  a semicolon, a colon, $HEX, even the word FORGET. )

\ A backslash comment runs to the end of the line and no further.

: DOUBLE ( n -- n2 ) 2 * ;      \ stack comments are the usual place for one
: TREBLE ( n -- n3 ) 3 * ;      ( and this form works just as well )

\ Both are ordinary words, so both need a space after them.  "\this" is not
\ a comment; it is a word the system will not find, and it will say so.
\
\ A stack comment is not checked by anything -- it is a comment.  It is
\ still the most useful thing you can write, because a Forth word's
\ interface is entirely in what it leaves on the stack.

: SIXFOLD ( n -- n6 ) DOUBLE TREBLE ;

." LOADED.  TRY  7 SIXFOLD ." CR
