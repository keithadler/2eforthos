; ---------------------------------------------------------------------------
; lc.inc -- the language card
;
; Included before anything else, because the cold start uses it on its second
; instruction.
; ---------------------------------------------------------------------------

; --- the language card -----------------------------------------------------
; Sixteen kilobytes of RAM at $D000-$FFFF, which is also where the monitor
; ROM lives.  The card is banked in for the life of the session and the ROM
; switched back only around the twelve places that call into it -- there are
; only twelve, which is what makes this affordable.  Everything below $C000
; is untouched by the switch, so main code and data stay visible either way.
;
; A single read selects; the write-enabling switches need two.
LCRAM   = $C08B               ; read card and write it -- needs two accesses
LCROM   = $C08A               ; read ROM, card write protected
LCWRITE = $C089               ; read ROM, write card -- needs two accesses
LCDICT  = $D000               ; where the system's own dictionary is compiled
LCTOP   = $FFF9               ; ...up to, leaving the CPU's vectors alone

.macro  ROMIN
        bit     LCROM
.endmacro

.macro  ROMOUT
        bit     LCRAM                   ; the write-enabling selections only
        bit     LCRAM                   ; take on the second consecutive read
.endmacro
