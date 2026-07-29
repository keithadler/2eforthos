\ DISKIO.FTH -- the disk, at both levels.
\
\ Type SHOWVTOC, or WRITEONE to make a file.
\ FORGET DSK-- to reclaim the space.

: DSK-- ;

\ The bottom level is one sector at a time.  DREAD takes a track, a sector
\ and somewhere to put it.  Sector numbers are DOS's, not the order they are
\ physically written in -- DREAD translates.
\
\ Track 17 sector 0 is the VTOC, which names the first catalog sector and
\ carries the free-space bitmap.

: SHOWVTOC
  17 0 SECBUF DREAD DROP
  ." FIRST CATALOG SECTOR IS TRACK " SECBUF 1+ C@ .
  ." SECTOR " SECBUF 2 + C@ . CR
  ." TRACKS PER DISK " SECBUF 52 + C@ . 
  ." SECTORS PER TRACK " SECBUF 53 + C@ . CR
  ." FREE SECTORS " FREE . CR ;

\ The top level is files.  SAVE takes an address and a length and asks for a
\ name; it allocates the sectors, writes a track/sector list, writes the
\ data, and adds a catalog entry.  LOAD reads a text file back and hands it
\ to the interpreter, so a saved file of Forth is a program.

\ A quoted string ends at the first closing quote, so a one-liner typed this
\ way cannot contain another one.  Keep the saved definition quote-free, or
\ write the file on the host and put it in examples/.

: WRITEONE
  ." THIS ADDS A FILE TO THE DISK.  IT WILL ASK FOR A NAME." CR
  S" : GREETING 1234 . CR ;" SAVE ;

." LOADED.  TYPE SHOWVTOC OR WRITEONE" CR
