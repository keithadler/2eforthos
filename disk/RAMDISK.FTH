\ RAMDISK.FTH -- a RamWorks memory card as drive 3.
\
\ The //e's auxiliary slot took cards that extend the 64K auxiliary bank
\ to many banks -- RamWorks III carried a megabyte -- selected by writing
\ a bank number to $C073.  Bank 0 is the ordinary auxiliary memory the
\ console and the graphics screen live in; banks 1 and up are empty land.
\
\ This library makes three of those banks a disk.  LIB RAMDISK.FTH probes
\ the card, and if it answers, 3 DRIVE is a 560-sector volume exactly like
\ a floppy -- CAT, LOAD, SAVE, INIT, everything -- except that it moves at
\ memory speed and forgets everything at power-off.  Fast scratch, not
\ safe keeping.
\
\ The copy routine cannot run from main memory: RAMRD banks every read
\ from $0200-$BFFF to the card, INSTRUCTION FETCHES INCLUDED -- the first
\ version ran where it was compiled and the machine fell into the monitor
\ mid-instruction.  So the two routines are assembled by hand below and
\ then MOVEd to the bottom of the stack page, $0100-$0157, which no
\ auxiliary switch touches and which the return stack, growing down from
\ $01FF, never reaches.  This file is its own assembler.

: RAMDISK-- ;

\ --- the two transfer routines, laid down byte by byte ---------------------
\ Zero page $DB and $DD hold the main and auxiliary pointers.  Not the
\ prims' scratch at $B4: the ! that stores a pointer there parks its own
\ pointer in the same cell, and every * and /MOD between two words of
\ Forth treads on it too -- the first try handed the routine whatever the
\ arithmetic left behind, and one wild write banked the language card
\ away mid-word.  $DB-$DE are reserved for libraries in zp.inc.  AXB is
\ the bank; S80 remembers 80STORE, which the transfer must put back
\ because the console's text windows ignore the aux switches while it is
\ set.

CREATE AXB 1 ALLOT
CREATE S80 1 ALLOT

: OP, ( b -- ) C, ;
: ADR, ( a -- ) DUP 255 AND C, 256 / C, ;

\ common prologue: save and clear 80STORE, select the bank
: PRO, ( -- )
  $AD OP, $C018 ADR,                    \ LDA $C018   bit7 = 80STORE
  $8D OP, S80 ADR,                      \ STA S80
  $8D OP, $C000 ADR,                    \ STA $C000   80STORE off
  $AD OP, AXB ADR,                      \ LDA AXB
  $8D OP, $C073 ADR, ;                  \ STA $C073   bank in

\ common epilogue: bank 0, put 80STORE back if it was on, return
: EPI, ( -- )
  $A9 OP, 0 OP,                         \ LDA #0
  $8D OP, $C073 ADR,                    \ STA $C073
  $AD OP, S80 ADR,                      \ LDA S80
  $10 OP, 3 OP,                         \ BPL +3
  $8D OP, $C001 ADR,                    \ STA $C001   80STORE on again
  $60 OP, ;                             \ RTS

CREATE RDC                              \ one page, aux -> main
  PRO,
  $8D OP, $C003 ADR,                    \ STA $C003   reads come from aux
  $A0 OP, 0 OP,                         \ LDY #0
  $B1 OP, $DD OP,                       \ LDA ($DD),Y from aux
  $91 OP, $DB OP,                       \ STA ($DB),Y to main
  $C8 OP,                               \ INY
  $D0 OP, $F9 OP,                       \ BNE loop
  $8D OP, $C002 ADR,                    \ STA $C002   reads back to main
  EPI,

CREATE WRC                              \ one page, main -> aux
  PRO,
  $8D OP, $C005 ADR,                    \ STA $C005   writes go to aux
  $A0 OP, 0 OP,                         \ LDY #0
  $B1 OP, $DB OP,                       \ LDA ($DB),Y from main
  $91 OP, $DD OP,                       \ STA ($DD),Y to aux
  $C8 OP,                               \ INY
  $D0 OP, $F9 OP,                       \ BNE loop
  $8D OP, $C004 ADR,                    \ STA $C004   writes back to main
  EPI,

\ --- where a sector lives ---------------------------------------------------
\ Each bank offers $0200-$BFFF -- exactly 190 sectors -- so a standard
\ 560-sector volume is banks 1 and 2 full and most of bank 3.
190 CONSTANT BSECS
VARIABLE AXO
: D3AT ( t s -- )                       \ set AXB and the aux pointer
  SWAP 16 * +
  BSECS /MOD 1+ AXB C!
  256 * 512 + $DD ! ;

\ the routines run from the stack page, not from where they were born
$0100 CONSTANT RDX
$012C CONSTANT WRX
: AXGO ( -- ) RDC RDX 44 MOVE  WRC WRX 44 MOVE ;

: ARD ( t s addr -- ok ) $DB ! D3AT RDX CALL -1 ;
: AWR ( t s addr -- ok ) $DB ! D3AT WRX CALL -1 ;

\ --- is a card even there? --------------------------------------------------
\ Stamp the banks downward, read them back upward: on a real card each
\ bank keeps its own stamp, and on a bare machine every write landed on
\ the same 64K so nothing past "bank 1" answers right.
: BPOKE ( val bank -- )
  SWAP PAD 256 ROT FILL
  PAD $DB !  $0200 $DD !  AXB C!  WRX CALL ;
: BPEEK ( bank -- c )
  AXB C!  $0200 $DD !  PAD $DB !  RDX CALL  PAD C@ ;
\ The bank register takes seven bits, and cards ran from 256K to eight
\ megabytes -- 128 banks, which apple2ts will emulate in full.  A card
\ smaller than the register MIRRORS: bank 16 of a megabyte card is bank
\ 0 wearing a bigger number, so counting stamps alone overcounts by one
\ wrap.  Each candidate is therefore stamped alongside a canary in bank
\ 0, and the first stamp that kills the canary is the first bank that
\ is not really there.
VARIABLE NBK
: BPROBE ( -- n )
  1 NBK !
  128 1 DO
    165 0 BPOKE  I I BPOKE
    0 BPEEK 165 =  I BPEEK I =  AND
    IF I 1+ NBK ! ELSE LEAVE THEN
  LOOP NBK @ ;

\ --- formatting on first use ------------------------------------------------
\ The card holds garbage at power-on, so the first switch to drive 3 finds
\ no filesystem and makes one.  The resident DRIVE calls this through the
\ 'D3F vector before it reads the catalog.
: D3F ( -- )
  17 0 SECBUF ARD DROP
  SECBUF 1+ C@ 17 <> IF
    ." A FRESH RAM DISK -- FORMATTING." CR INIT THEN ;

\ --- installing --------------------------------------------------------------
: (INSTALL)
  AXGO
  BPROBE 4 < IF
    ." NO RAM EXPANSION FOUND -- DRIVE 3 STAYS OFF" CR EXIT THEN
  ['] ARD 'ARD !  ['] AWR 'AWR !  ['] D3F 'D3F !
  ." RAM DISK READY: " NBK @ . ." BANKS -- A "
  NBK @ 64 * . ." K CARD.  TYPE 3 DRIVE" CR ;
(INSTALL)

\ The word people type to get here -- the autoload hook maps RAMDISK to
\ this file -- and the word they get once it is here, so the second
\ mention answers instead of loading the file again.
: RAMDISK ( -- )
  'ARD @ IF ." DRIVE 3 IS READY -- TYPE 3 DRIVE" CR
  ELSE ." NO RAM EXPANSION FOUND" CR THEN ;
