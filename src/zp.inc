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
DSTACK_TOP  = $A0               ; X when the stack is empty  (40 cells)

; $A0-$AF is a deliberate gap.  The deepest primitive reaches 7,X, so an
; empty-stack fetch lands here rather than on IP -- which matters because
; `@` on an empty stack would otherwise store its result *into* IP and send
; the inner interpreter somewhere random.  A mistyped line should produce an
; error, not a crash.

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

; --- hi-res text -----------------------------------------------------------
TPTR        = $D4               ; 2  glyph pointer into FONT
TCOL        = $D6               ; 1  text column, 0..39
TROW        = $D7               ; 1  text row, 0..23
TIDX        = $D8               ; 1
TY          = $D9               ; 1  first raster row of the cell
TINVF       = $DA               ; 1  $7F for inverse video, else $00

; --- disk ------------------------------------------------------------------
; RWTS itself works below $0050, so none of this collides with it.
IOBP        = $DB               ; 2  pointer to DOS's IOB
RTRK        = $DD               ; 1
RSEC        = $DE               ; 1
RCMD        = $DF               ; 1  1 = read, 2 = write
