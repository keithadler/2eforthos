\ CHART.FTH -- bar and pie charts on the lo-res screen.
\
\ Lo-res is 40x48 in sixteen colours and it is the text page seen
\ differently: two blocks to a byte, no shifting, no aux memory.  For blocky
\ things it is enormously faster than 560x192, which is why charts belong
\ here rather than in hi-res.
\
\ Note GR keeps four lines of text at the bottom, so rows 40-47 are the
\ console's and anything drawn there gets scrolled over.  Charts use 0-39.
\
\ Type BARS, or STACKED.  FORGET CHT-- to reclaim the space.

: CHT-- ;

\ Seven values to plot, and a colour each.
DATA: 12 +VAL 28 +VAL 7 +VAL 34 +VAL 19 +VAL 25 +VAL 3 +VAL ;DATA
CREATE HUES 1 C, 2 C, 3 C, 5 C, 6 C, 9 C, 12 C,

\ A bar grows upward from row 39, so a bar h tall starts at row 40-h.  Four
\ columns wide, drawn as four adjacent bars -- there is no filled rectangle
\ in lo-res and at this size a loop of four is not worth avoiding.
\
\ Written with variables rather than stack juggling.  The first version of
\ this word shuffled six items and drew one-column bars at the wrong heights,
\ which is what stack juggling gets you when nobody is checking.
VARIABLE BC VARIABLE BH
: BAR ( col height hue -- )
  GCOLOR!  BH !  BC !
  4 0 ?DO  BC @ I +  40 BH @ -  BH @  GBAR  LOOP ;

: BARS
  GR 0 GCLS RESTORE-DATA
  DATA# 0 ?DO
    READ-VAL                        ( height )
    I 5 * 1+ SWAP                   ( col height )
    HUES I + C@ BAR
  LOOP
  15 GCOLOR! 0 39 39 GHLIN ;        \ a baseline

\ The same numbers as one column of coloured segments, stacked upward.
VARIABLE SYT VARIABLE SEG
: STACKED
  GR 0 GCLS RESTORE-DATA
  40 SYT !
  DATA# 0 ?DO
    READ-VAL 4 / 1+ SEG !
    HUES I + C@ GCOLOR!
    SYT @ SEG @ - SYT !
    18 SYT @ SEG @ GBAR
    19 SYT @ SEG @ GBAR
    20 SYT @ SEG @ GBAR
    21 SYT @ SEG @ GBAR
  LOOP ;

." LOADED.  TYPE BARS OR STACKED" CR
