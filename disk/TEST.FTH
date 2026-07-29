\ TEST.FTH -- loaded by the console tests to prove LOAD works.
: TRIPLE 3 * ;
: SUMTO 0 SWAP 1+ 1 ?DO I + LOOP ;
VARIABLE LOADED  -1 LOADED !
: SQUARES CREATE 0 DO I DUP * , LOOP DOES> SWAP 2 * + @ ;
8 SQUARES SQ
