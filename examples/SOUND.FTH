\ SOUND.FTH -- the speaker.
\
\ TONE takes a delay and a count of half-cycles, so a bigger number is a
\ lower note.  Dividing a constant by the delay keeps every note the same
\ length however high it is.
\
\ Type SCALE, SIREN or CHIRP.  FORGET SND-- to reclaim the space.
: SND-- ;
: NOTE ( delay -- ) DUP 30000 SWAP / TONE ;
: SCALE 60 240 DO I NOTE -20 +LOOP ;
: CHIRP 20 0 DO I 8 * 40 + NOTE LOOP ;
: SWEEP 60 240 DO I NOTE -10 +LOOP  240 60 DO I NOTE 10 +LOOP ;
: SIREN 3 0 DO SWEEP LOOP ;
." LOADED.  TYPE SCALE, CHIRP OR SIREN" CR
