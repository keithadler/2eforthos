\ PRIMES.FTH -- loops, and numbers in columns.
\
\ Trial division by odd numbers only, stopping once the divisor squared
\ passes the candidate.  Type PRIMES.  FORGET PRM-- to reclaim the space.
: PRM-- ;
: PRIME? ( n -- flag )
  DUP 2 < IF DROP 0 EXIT THEN
  DUP 2 = IF DROP -1 EXIT THEN
  DUP 1 AND 0= IF DROP 0 EXIT THEN
  3
  BEGIN 2DUP DUP * 1- > WHILE
    2DUP MOD 0= IF 2DROP 0 EXIT THEN
    2 +
  REPEAT
  2DROP -1 ;
: PRIMES 0 200 2 DO
    I PRIME? IF I 5 .R 1+ DUP 12 MOD 0= IF CR THEN THEN
  LOOP DROP CR ;
." LOADED.  TYPE PRIMES" CR
