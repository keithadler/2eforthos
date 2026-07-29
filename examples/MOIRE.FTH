\ MOIRE.FTH -- interference patterns, and the dither colours.
\
\ Two fans of lines drawn in XOR mode: where a line from one centre crosses
\ a line from the other, the two cancel, and what is left is the pattern the
\ crossings make rather than the lines themselves.
\
\ Type MOIRE or BANDS.  FORGET MOI-- to reclaim the space.
: MOI-- ;
: FAN ( cx cy -- )
  560 0 DO 2DUP I 0 HLINE2  2DUP I 191 HLINE2  12 +LOOP 2DROP ;
: MOIRE HGR HCLS 3 HCOLOR -1 HXOR
  180 96 FAN  380 96 FAN
  0 HXOR ;
: BANDS HGR HCLS
  8 0 DO I HCOLOR  I 70 * DUP 66 +  0 191 HBOX LOOP
  3 HCOLOR 0 24 TAT ;
." LOADED.  TYPE MOIRE OR BANDS" CR
