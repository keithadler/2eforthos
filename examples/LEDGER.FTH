\ LEDGER.FTH -- a checkbook, because somebody always asks what it's FOR.
\
\ Amounts are whole cents in double cells, so the arithmetic is exact to
\ the penny out to twenty million dollars -- floating point is for
\ curves, not money.  Each entry is an amount and a memo; the running
\ balance is kept as you go and printed the way a bank would.
\
\   LEDGER               start a fresh book
\   1250 00 IN SALARY    take in $1250.00 -- dollars, cents, memo
\   3 15 OUT COFFEE      pay out $3.15
\   BAL.                 the balance
\   ENTRIES              the whole book, with running balance
\   LSAVE                write the book as a text file, asking the name
\
\ Everything is ordinary Forth: IN is a word, the memo is parsed off the
\ line the way HELP parses its argument, and the book is lines of text a
\ MORE or a WLOAD can read.

: LEDGER-- ;

40 CONSTANT LMAX
32 CONSTANT LWID
CREATE LBOOK LMAX LWID * ALLOT          \ sign+cents double, then the memo
VARIABLE LN
VARIABLE BLO VARIABLE BHI               \ the running balance, a double

: LENT ( n -- addr ) LWID * LBOOK + ;

: LEDGER ( -- ) 0 LN ! 0 BLO ! 0 BHI !
  ." A FRESH BOOK.  1250 00 IN SALARY PUTS IN $1250.00" CR ;

\ print cents as dollars, signed, with the point where banks keep it
: $. ( d -- )
  TUCK DABS <# # # 46 HOLD #S ROT SIGN #> TYPE ;

: BAL. ( -- ) BLO @ BHI @ $. SPACE ." ON HAND" CR ;

\ one entry: dollars and cents on the stack -- combined into a double
\ before anything can overflow a cell, because $327.68 is not a salary
\ cap anyone would accept -- the memo is the next word on the line, and
\ the sign is which word you used
VARIABLE LSGN
: (ENTRY) ( dollars cents -- )
  LN @ LMAX < 0= IF 2DROP ." THE BOOK IS FULL" CR EXIT THEN
  SWAP 100 UM* ROT S>D D+
  LSGN @ 0< IF DNEGATE THEN
  2DUP BLO @ BHI @ D+ BHI ! BLO !
  LN @ LENT 2!
  PARSE-NAME 20 MIN
  DUP LN @ LENT 4 + C!
  LN @ LENT 5 + SWAP MOVE
  1 LN +!  BAL. ;
: IN ( dollars cents -- ) 1 LSGN ! (ENTRY) ;
: OUT ( dollars cents -- ) -1 LSGN ! (ENTRY) ;

: ENTRIES ( -- )
  0 BLO ! 0 BHI !
  LN @ 0 ?DO
    I LENT 2@ 2DUP BLO @ BHI @ D+ BHI ! BLO !
    I 2 .R SPACE
    $. SPACE
    I LENT 4 + C@ I LENT 5 + SWAP TYPE
    14 I LENT 4 + C@ - 1 MAX SPACES
    BLO @ BHI @ $. CR
  LOOP
  ." -- " BAL. ;

\ the book as text, one entry a line: cents, a space, the memo --
\ readable by MORE, by a person, or by a spreadsheet on the other side
\ of a null modem
VARIABLE LFP
: LFLAT ( -- addr len )
  HERE LFP !
  LN @ 0 ?DO
    I LENT 2@ TUCK DABS <# #S ROT SIGN #>
    DUP >R LFP @ SWAP MOVE R> LFP +!
    32 LFP @ C! 1 LFP +!
    I LENT 4 + C@ DUP >R
    I LENT 5 + LFP @ R@ MOVE R> LFP +!
    13 LFP @ C! 1 LFP +!
  LOOP
  HERE LFP @ HERE - ;
: LSAVE ( -- ) LFLAT SAVE ;

: LHELP2 ." LEDGER STARTS A BOOK.  1250 IN SALARY.  315 OUT COFFEE." CR ;
LHELP2
