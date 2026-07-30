\ INPUT.FTH -- ask a question and get an answer, the way Applesoft did.
\
\ INPUT A$ was one statement that prompted, read a line, converted it and
\ assigned it.  Here that was three or four words every time, and the
\ conversion is the part people get wrong -- so these do it once.
\
\ Type INPUT and this loads itself.
\
\   addr len ASK$   ( -- addr len )  prompt, return what was typed
\   addr len ASK#   ( -- n ok )      prompt, return a number and whether
\                                    it was one
\   addr len ASKY?  ( -- flag )      prompt, true if the answer began Y
\
\ The number reader here is its own, not STR's.  A file cannot LOAD
\ another file -- LOAD points the interpreter at the new source, and the
\ rest of the old one is never read -- so depending on STR.FTH meant this
\ file ending quietly at the dependency with none of its own words
\ defined, which is exactly what the first version did.  Twelve duplicated
\ lines beat a dependency that cannot be expressed.
\
\ Nothing here loops until the answer is valid, deliberately.  A word that
\ will not give up is a word you cannot get out of, and this machine has
\ no interrupt key.  ASK# hands back a flag; what to do about a bad answer
\ belongs to the program, not to the question.

: INPUT-- ;

VARIABLE INA VARIABLE INL VARIABLE INN VARIABLE INS

: ITRIM ( addr len -- addr2 len2 )      \ blanks off both ends
  BEGIN DUP 0> IF 2DUP + 1- C@ 32 = ELSE 0 THEN WHILE 1- REPEAT
  BEGIN DUP 0> IF OVER C@ 32 = ELSE 0 THEN WHILE 1- SWAP 1+ SWAP REPEAT ;

: IN>N ( addr len -- n ok )             \ all of it, or nothing
  INL ! INA ! 0 INN ! 0 INS !
  INL @ 0= IF 0 0 EXIT THEN
  INA @ C@ 45 = IF 1 INS ! 1 INA +! -1 INL +! THEN
  INL @ 0= IF 0 0 EXIT THEN
  INL @ 0 ?DO
    INA @ I + C@ 127 AND
    DUP 48 < OVER 57 > OR IF DROP 0 0 UNLOOP EXIT THEN
    48 - INN @ 10 * + INN !
  LOOP
  INN @ INS @ IF NEGATE THEN -1 ;

: ASK$ ( addr len -- addr2 len2 )       \ prompt, then the typed line
  TYPE ASKLN ;

: ASK# ( addr len -- n ok )
  ASK$ ITRIM IN>N ;

: ASKY? ( addr len -- flag )
  ASK$ DUP 0= IF 2DROP 0 EXIT THEN
  DROP C@ 127 AND DUP 89 = SWAP 121 = OR ;

: INPUT ( -- )
  ." ADDR LEN ASK$    PROMPT, RETURN THE LINE" CR
  ." ADDR LEN ASK#    PROMPT, RETURN N AND A FLAG" CR
  ." ADDR LEN ASKY?   PROMPT, TRUE IF THE ANSWER BEGAN Y" CR ;
INPUT
