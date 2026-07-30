\ MENUS.FTH -- the AppleWorks kind of menu: a bar you move with the arrows.
\
\ MENU asks "WHICH NUMBER?" and that is a prompt, not a menu.  What made
\ AppleWorks usable by people who did not program was a highlighted line
\ you moved with the arrow keys, Return to choose and Escape to back out
\ -- no numbers to read off and retype, and nothing to get wrong.
\
\ This is that, on top of CPUT and CINV, which write the console screen
\ directly because the firmware's own output sets the high bit on every
\ character and the high bit is what makes text normal rather than
\ inverse.
\
\ Type MENUS and this loads itself.
\
\   addr len col row CTYPE    write a string on the console
\   n toprow MENU-PICK        run the bar, return the choice or -1
\   'MI                       holds a word ( i -- addr len ) giving item i
\   PICK                      choose a program off this drive and load it
\
\ The arrow keys on a //e are $0B up and $0A down, which are also Ctrl-K
\ and Ctrl-J; Return is $0D and Escape $1B.

: MENUS-- ;

VARIABLE MA VARIABLE ML VARIABLE MC VARIABLE MR
VARIABLE MSEL VARIABLE MN VARIABLE MTOP VARIABLE MCH VARIABLE 'MI
36 CONSTANT MW                          \ how wide the highlight runs

: CTYPE ( addr len col row -- )
  MR ! MC ! ML ! MA !
  ML @ 0 ?DO
    MA @ I + C@ 127 AND  MC @ I +  MR @  CPUT
  LOOP ;

\ The whole line is highlighted, not just the text -- a bar that stops at
\ the end of the word looks like a mistake rather than a selection.
: MROW ( i -- )
  'MI @ 0= IF DROP EXIT THEN
  DUP MSEL @ = IF -1 ELSE 0 THEN CINV
  DUP 'MI @ EXECUTE                     ( i addr len )
  ROT MTOP @ + MR ! ML ! MA !
  MW 0 DO
    I ML @ < IF MA @ I + C@ 127 AND ELSE 32 THEN
    I 2 +  MR @  CPUT
  LOOP
  0 CINV ;

: MDRAW ( -- ) MN @ 0 DO I MROW LOOP ;

\ Only the two rows that changed are redrawn, because rewriting twenty
\ lines for every keypress is visible flicker on a 1 MHz machine.
: MMOVE ( new -- )
  0 MAX MN @ 1- MIN
  MSEL @ OVER = IF DROP EXIT THEN
  MSEL @ >R MSEL !
  R> MROW MSEL @ MROW ;

: MENU-PICK ( n toprow -- choice )
  MTOP ! MN ! 0 MSEL ! -2 MCH !
  MN @ 0= IF -1 EXIT THEN
  \ EXECUTE of address zero is a jump into the reset vectors, and the
  \ machine does not come back to say what it thought it was doing.
  'MI @ 0= IF ." SET 'MI FIRST" CR -1 EXIT THEN
  MDRAW
  BEGIN
    BEGIN KEY? UNTIL KEYC
    CASE
      11 OF MSEL @ 1- MMOVE ENDOF
      10 OF MSEL @ 1+ MMOVE ENDOF
      13 OF MSEL @ MCH ! ENDOF
      27 OF -1 MCH ! ENDOF
    ENDCASE
    MCH @ -2 <>
  UNTIL
  MCH @ ;

\ --- choosing a program off the disk ---------------------------------------
\ The catalog's names are thirty characters padded with blanks, and the
\ blanks carry the high bit like everything else the disk holds, so the
\ ordinary -TRAILING does not see them.
: CATNAME ( i -- addr len )
  CATENT 6 + 30
  BEGIN DUP 0> IF 2DUP + 1- C@ 127 AND 32 = ELSE 0 THEN WHILE 1- REPEAT ;

20 CONSTANT MMAX                        \ rows 2 to 21; the rest need paging

: PICK ( -- )
  PAGE
  S" CHOOSE A PROGRAM   ARROWS  RETURN  ESC" 2 0 CTYPE
  ['] CATNAME 'MI !
  NFILE @ MMAX MIN 2 MENU-PICK
  DUP 0< IF DROP PAGE ." NOTHING CHOSEN." CR EXIT THEN
  PAGE DUP . ." LOADING..." CR LOAD ;

: MENUS ( -- )
  ." PICK             CHOOSE A PROGRAM AND LOAD IT" CR
  ." N TOPROW MENU-PICK   THE BAR, RETURNING THE CHOICE OR -1" CR
  ." ADDR LEN COL ROW CTYPE   WRITE ON THE CONSOLE" CR ;
MENUS
