\ MENU.FTH -- the Programs disk as a menu.
\
\ MENU switches to drive 2, lists everything on it, and asks which
\ number to load.  It is the whole of "2 DRIVE CAT n LOAD" folded into
\ one word, for whoever would rather be asked than remember -- and it
\ leaves you on drive 2 afterwards, which is where the programs assume
\ they are.  1 DRIVE comes home.

: MENU-- ;

\ Read a number out of a typed line by hand: the interpreter's own
\ number reader works on the input stream, not on a string in memory.
VARIABLE MV VARIABLE MOK
: MNUM ( addr len -- n ok )
  0 MV ! -1 MOK !
  DUP 0= IF 0 MOK ! THEN
  0 ?DO
    DUP I + C@
    DUP 47 > OVER 58 < AND IF
      48 - MV @ 10 * + MV !
    ELSE DROP 0 MOK ! THEN
  LOOP DROP
  MV @ MOK @ ;

: MENU ( -- )
  2 DRIVE CAT
  ." WHICH NUMBER? " ASKLN MNUM
  IF LOAD ELSE DROP ." THAT IS NOT A NUMBER" CR THEN ;

: MENUHELP ." MENU LISTS THE PROGRAMS AND ASKS WHICH TO LOAD." CR ;
MENUHELP
