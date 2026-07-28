; ---------------------------------------------------------------------------
; zp.inc -- zero page allocation
;
; $00-$4F is left alone: the monitor keeps its text-window state there
; ($20-$2F, and CH/CV at $24/$25) and DOS 3.3's RWTS uses $40-$4B.  We call
; both, so those stay untouched.
;
; $50-$CF was Applesoft's.  Forth replaces Applesoft, so it is all ours.
; ---------------------------------------------------------------------------

; --- data stack ------------------------------------------------------------
; Cells are 16-bit, little-endian, held in zero page and addressed through X.
; TOS is at (0,X)/(1,X); pushing is DEX DEX.  X = DSTACK_TOP means empty, and
; since a push decrements X first, the sentinel cell itself is never written.
DSTACK_BOT  = $50               ; lowest cell address (overflow guard)
DSTACK_TOP  = $B0               ; X when the stack is empty  (48 cells)

; --- Forth kernel ----------------------------------------------------------
IP          = $B0               ; 2  interpreter pointer (next thread cell)
W           = $B2               ; 2  work register (current word's CFA)
TMP1        = $B4               ; 2
TMP2        = $B6               ; 2
XSAV        = $B8               ; 1  parks the stack pointer across ROM calls
YSAV        = $B9               ; 1

; --- hi-res driver ---------------------------------------------------------
HX          = $BA               ; 2  x, 0..279 (16-bit: 280 > 255)
HX2         = $BC               ; 2  second x for spans
HY          = $BE               ; 1  y, 0..191
HY2         = $BF               ; 1
HBASE       = $C0               ; 2  base address of the current raster row
HPTR        = $C2               ; 2  scratch pointer for table indexing
HCOLE       = $C4               ; 1  colour byte for even byte-columns
HCOLO       = $C5               ; 1  colour byte for odd byte-columns
HCOLB       = $C6               ; 1  the one selected for the column in hand
HMASK       = $C7               ; 1  which bits of that byte to touch
HTMP        = $C8               ; 1
HTMP2       = $C9               ; 1
HB1         = $CA               ; 1  first byte-column of a span
HB2         = $CB               ; 1  last byte-column of a span
HLM         = $CC               ; 1  left edge mask
HRM         = $CD               ; 1  right edge mask

; --- outer interpreter -----------------------------------------------------
SRC         = $CE               ; 2  general source pointer
UTMP        = $D0               ; 2
UTMP2       = $D2               ; 2
