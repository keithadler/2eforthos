\ HELLO.FTH -- the smallest complete program, and how to read one.
\
\ A Forth program is a list of words separated by spaces.  There is no other
\ grammar.  Two kinds of comment are ignored:
\
\   \ ...        from the backslash to the end of the line
\   ( ... )      from the bracket to the closing one, over as many lines
\                as it takes
\
\ Both are words, so both need a space after them.  "\this" is not a comment,
\ it is a word the system has never heard of.
\
\ Load this file with the number CAT prints, then type HELLO.
\ FORGET HEL-- gives the dictionary space back.

: HEL-- ;                       \ a marker, so FORGET can find the start

\ ":" starts a definition and ";" ends it.  Between them the words are not
\ run, they are compiled -- so HELLO does nothing until you type its name.

: HELLO
  ." HELLO FROM 2E FORTH OS" CR  \ ." prints, up to the closing quote
  ." THE ANSWER IS " 6 7 * .     \ 6 and 7 are pushed, * multiplies, . prints
  CR ;

\ A word can use words defined before it, and only those: the dictionary is
\ searched backwards from the newest, so a name has to exist before it is
\ mentioned.

: TWICE HELLO HELLO ;

." LOADED.  TYPE HELLO OR TWICE" CR
