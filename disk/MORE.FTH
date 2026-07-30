\ MORE.FTH -- page through a text file: N MORE.
\
\ Twenty-two lines at a time, a --MORE-- at the bottom, any key for the
\ next page and Q to stop.  Reads through the same sequential file words
\ everything else uses, so it works on either drive's files.
\
\ It lives on the system disk because it is a tool, not a program: load
\ it once and MORE any file whose contents you wonder about -- HELPTEXT,
\ a saved program, this file itself.

: MORE-- ;

VARIABLE MLN
: MKEY ( -- c ) BEGIN KEY? UNTIL KEYC ;
: MORE ( n -- )
  FOPEN 0= IF ." CANNOT OPEN IT" CR EXIT THEN
  0 MLN !
  BEGIN
    PAD 79 DFGETS >R                    ( got )
    PAD SWAP TYPE CR
    1 MLN +!
    MLN @ 22 = IF
      ." --MORE--"
      MKEY CR 0 MLN !
      81 = IF R> DROP FCLOSE EXIT THEN  \ Q is enough
    THEN
  R> UNTIL FCLOSE ;

: MOREHELP ." N MORE PAGES FILE N.  ANY KEY TURNS, Q STOPS." CR ;
MOREHELP
