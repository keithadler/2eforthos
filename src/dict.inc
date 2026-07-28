; ---------------------------------------------------------------------------
; dict.inc -- dictionary layout and the macros that build it
;
; A header is:
;       +0  .word  link to the previous header ($0000 ends the chain)
;       +2  .byte  name length in bits 0-5, flags in bits 6-7
;       +3  .byte  name, uppercase ASCII, high bit clear
;   +3+len  code field
;
; The code field of a primitive IS its machine code; the code field of a
; colon word is `JSR DOCOL` followed by the thread.  Thread cells are code
; field addresses, so the inner interpreter ends in a plain JMP (W) -- this
; is direct-threaded code, and a primitive costs no bytes beyond its own.
;
; ca65 cannot carry a label address forward in a .set variable, so headers
; are chained through generated identifiers HDR0000, HDR0001, ... counted by
; WCNT.  LASTHDR always names the most recently defined one.
; ---------------------------------------------------------------------------

F_IMMED   = $80                 ; execute even while compiling
F_HIDDEN  = $40                 ; invisible to FIND (a definition in progress)
F_LENMASK = $3F

WCNT .set 0

; Emit the label and link field only.  Split out so that a word whose name
; contains a double quote can spell its own name out in bytes.
.macro  headlink
        .ident(.sprintf("HDR%04d", WCNT)):
        .if WCNT = 0
                .word   $0000
        .else
                .word   .ident(.sprintf("HDR%04d", WCNT-1))
        .endif
        WCNT .set WCNT + 1
.endmacro

.macro  head nm, fl
        headlink
        .byte   .strlen(nm) | fl
        .byte   nm
.endmacro

; A primitive: header, then the label, then machine code ending in NEXT.
.macro  prim nm, lbl, fl
        head    nm, fl
        lbl:
.endmacro

; A colon definition written in assembly: header, label, JSR DOCOL, thread.
.macro  colon nm, lbl, fl
        head    nm, fl
        lbl:
        jsr     DOCOL
.endmacro

.define LASTHDR .ident(.sprintf("HDR%04d", WCNT-1))
