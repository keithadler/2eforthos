\ PAINT.FTH -- ForthPaint: draw on 560x192 with the paddles.
\
\ The crosshair rides the two paddle knobs (or the mouse, on an emulator
\ that maps it there) and the button puts ink down.  Number keys pick the
\ tool, letters do the rest.  Every mark is made with the same drawing
\ words you can type at the prompt -- this program is just a loop around
\ them, which is rather the point.
\
\   1 PEN    hold the button and drag
\   2 LINE   click the ends
\   3 BOX    click two corners
\   4 DISC   click centre, then edge
\   5 FILL   click inside a shape
\   W E      ink white / ink black (eraser)
\   X        XOR on and off -- drawing twice undoes
\   C        clear the sheet
\   S        save and finish: two binary files, main then aux half
\   Q        quit
\
\ Type PAINT.  RESUME loads a saved pair back: n1 n2 RESUME.

: PAINT-- ;

VARIABLE CX VARIABLE CY                 \ the crosshair
VARIABLE TOOL VARIABLE INK
VARIABLE ANCH VARIABLE AX VARIABLE AY   \ first click of a two-click tool
VARIABLE LASTB VARIABLE PX2 VARIABLE PY2 VARIABLE XR

: CROSS ( -- )                          \ XOR, so drawing it twice removes it
  -1 HXOR 3 HCOLOR
  CX @ 6 - 0 MAX  CX @ 6 + 559 MIN  CY @ HLINE
  CX @  CY @ 4 - 0 MAX  CY @ 4 + 191 MIN  HVLINE
  0 HXOR ;

: AIM ( -- )                            \ paddles to pixels
  0 PADDLE 559 255 */ CX !
  1 PADDLE 191 255 */ CY ! ;

: INK! ( -- ) INK @ HCOLOR ;

\ One press of the button, by tool.  Two-click tools remember the first
\ click in ANCH and finish on the second.
: 2CLICK? ( -- f )                      \ true on the finishing click
  ANCH @ 0= IF CX @ AX ! CY @ AY ! -1 ANCH ! 0 ELSE 0 ANCH ! -1 THEN ;

: DIST ( -- r )                         \ crosshair to anchor, roughly
  CX @ AX @ - ABS  CY @ AY @ - ABS  MAX ;

: PRESS ( -- )
  INK!
  TOOL @ CASE
    1 OF PX2 @ PY2 @ CX @ CY @ HLINE2 ENDOF
    2 OF 2CLICK? IF AX @ AY @ CX @ CY @ HLINE2 THEN ENDOF
    3 OF 2CLICK? IF AX @ CX @ MIN  AX @ CX @ MAX
                    AY @ CY @ MIN  AY @ CY @ MAX  HFRAME THEN ENDOF
    4 OF 2CLICK? IF AX @ AY @ DIST HDISC THEN ENDOF
    5 OF CX @ CY @ HFILL ENDOF
  ENDCASE ;

: KEYS ( -- f )                         \ true means keep painting
  KEY? 0= IF -1 EXIT THEN
  KEYC CASE
    49 OF 1 TOOL ! ENDOF  50 OF 2 TOOL ! ENDOF
    51 OF 3 TOOL ! ENDOF  52 OF 4 TOOL ! ENDOF
    53 OF 5 TOOL ! ENDOF
    87 OF 3 INK ! ENDOF   69 OF 0 INK ! ENDOF
    88 OF XR @ 0= DUP XR ! HXOR ENDOF
    67 OF HCLS ENDOF
    83 OF 2 EXIT ENDOF                  \ save
    81 OF 0 EXIT ENDOF                  \ quit
  ENDCASE -1 ;

: PSAVE ( -- )                          \ two files: main half, then aux
  TEXT
  ." MAIN HALF -- " $2000 8192 BSAVE
  AUXBANK $2000 HERE 8192 MOVE MAINBANK
  ." AUX HALF -- " HERE 8192 BSAVE
  ." SAVED.  n1 n2 RESUME BRINGS IT BACK." CR ;

: PLOOP ( -- n )                        \ 0 quit, 2 save
  BEGIN
    VBL CROSS AIM CROSS                 \ off, move, on
    BTN DUP LASTB @ 0= AND IF CROSS PRESS CROSS THEN LASTB !
    CX @ PX2 !  CY @ PY2 !
    KEYS DUP -1 <>
  UNTIL ;

: PAINT ( -- )
  HGR 0 HXOR 0 XR ! 1 TOOL ! 3 INK ! 0 ANCH ! 0 LASTB !
  280 CX ! 96 CY !
  PLOOP
  2 = IF PSAVE ELSE TEXT THEN ;

: RESUME ( n1 n2 -- )                   \ a saved pair, back on the easel
  HGR
  SWAP $2000 BLOAD DROP                 \ main half straight onto the screen
  HERE BLOAD DROP                       \ aux half staged in the dictionary
  AUXBANK HERE $2000 8192 MOVE MAINBANK ;

: PHELP ." PAINT DRAWS.  PADDLES AIM, BUTTON INKS, 1-5 TOOLS." CR ;
PHELP
