\ GFX.FTH -- shapes, flood fill and a sprite.
\
\ Type GFX to draw it, TEXT to come back to the console, and
\ FORGET GFX-- to give the dictionary space back.
: GFX-- ;
CREATE STAR $18 C, $3C C, $7E C, $FF C, $7E C, $3C C, $18 C,
: RINGS 4 0 DO 280 96 20 I 20 * + HCIRCLE LOOP ;
: BARS 8 0 DO I 60 * 20 + DUP 40 + 165 180 HBOX LOOP ;
: GFX HGR HCLS 3 HCOLOR
  40 200 20 80 HFRAME
  120 50 HFILL
  RINGS BARS
  STAR 8 7 500 20 BLIT
  2 1 TAT T." 2E FORTH OS  GRAPHICS" ;
." LOADED.  TYPE GFX" CR
