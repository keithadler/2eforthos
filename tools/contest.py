#!/usr/bin/env python3
"""Run the console tests.

Each test types Forth at the prompt and then asserts against machine state --
the data stack, a variable's cell, a stretch of the graphics screen.  Checking
state rather than the screen is what makes these worth having: a screenshot
tells you something changed, the stack tells you what the system believes.

    python3 tools/contest.py            run everything
    python3 tools/contest.py arith      run named tests
    python3 tools/contest.py --list
"""

import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DISK = ROOT / "build" / "run.dsk"
LBL  = ROOT / "build" / "forth.lbl"
ZP   = ROOT / "src" / "zp.inc"

# Raster row 96 of the hi-res screen, which is where the line tests draw:
# $2000 + $400*(96 mod 8) + $80*((96/8) mod 8) + $28*(96/64)
ROW96 = 0x2228

TESTS = {

"boot": """
    check NFILE 5
    depth 0
""",

"arith": """
    type 2 3 +
    stack 5
    type 7 *
    stack 35
    type 100 SWAP -
    stack 65
    type DUP DUP + SWAP -
    stack 65
""",

# Division is unsigned and comes as a pair, so both halves get checked.
"division": """
    type 17 5 /MOD
    stack 3 2
    type 2DROP 1000 7 /
    stack 142
    type DROP 1000 7 MOD
    stack 6
""",

"stack-words": """
    type 1 2 3
    stack 3 2 1
    type ROT
    stack 1 3 2
    type NIP
    stack 1 2
    type OVER
    stack 2 1 2
    type DEPTH
    stack 3 2 1 2
""",

"compare": """
    type 3 4 <
    stack -1
    type DROP 4 3 <
    stack 0
    type DROP 5 5 =
    stack -1
    type DROP -7 ABS
    stack 7
    type DROP 3 9 MIN 4 2 MAX
    stack 4 3
""",

# A definition made at the prompt has to survive and run.
"colon": """
    type : SQ DUP * ;
    type 12 SQ
    stack 144
    type : CUBE DUP SQ * ;
    type 5 CUBE
    stack 125 144
""",

"loops": """
    type : SUMN 0 SWAP 0 DO I + LOOP ;
    type 10 SUMN
    stack 45
    type : CNT 0 BEGIN 1+ DUP 7 < 0= UNTIL ;
    type CNT
    stack 7 45
""",

"variables": """
    type VARIABLE FOO 42 FOO !
    type FOO @
    stack 42
    type DROP 8 FOO +! FOO @
    stack 50
    check FOO 50
""",

# The catalog is read from the disk at boot, not compiled in.
"catalog": """
    check NFILE 5
    type NFILE @
    stack 5
    type DROP FREE
    depth 1
""",

# The graphics screen is a thing the language turns on, and comes back from.
"graphics": """
    type HGR
    mem 2228 0
    type HCLS
    mem 2228 0
    type 3 HCOLOR 0 559 96 HLINE
    nonzero 2228 40
    type TEXT
    type 6 7 *
    stack 42
    shot
""",

# Drawing the same shape twice in XOR mode has to leave the screen alone.
"xor": """
    type HGR HCLS
    mem 2228 0
    type 3 HCOLOR -1 HXOR
    type 100 200 96 HLINE
    nonzero 2228 40
    type 100 200 96 HLINE
    mem 2228 0
    type 0 HXOR TEXT
""",

"shapes": """
    type HGR HCLS 3 HCOLOR
    type 40 200 40 120 HFRAME
    nonzero 2228 40
    type HCLS 280 96 60 HCIRCLE
    nonzero 2228 40
    type HCLS 280 96 60 HDISC
    nonzero 2228 40
    type TEXT
""",

# A line that pops more than it pushes must be caught, not left to run wild.
"underflow": """
    type 1 2 3
    stack 3 2 1
    type DROP DROP DROP DROP DROP
    depth 0
    type 9 9 +
    stack 18
""",

# The console commands have to leave nothing on the stack behind them.
"commands": """
    type CAT
    depth 0
    shot
    type HELP
    depth 0
    shot
    type 99 LOCK
    depth 0
""",

"raw-sectors": """
    type 17 0 2048 DREAD
    stack 0
    type DROP 2049 C@
    stack 17
""",
}


def run(name, script, keep_shots=False):
    shots = ROOT / "shots"
    if not keep_shots:
        subprocess.run(["rm", "-rf", str(shots)], check=False)
    subprocess.run(["cp", str(ROOT / "build" / "forth.dsk"), str(DISK)], check=True)

    syms = {}
    for line in LBL.read_text().splitlines():
        m = re.match(r"al\s+([0-9A-Fa-f]+)\s+\.?(\w+)$", line.strip())
        if m:
            syms[m.group(2)] = int(m.group(1), 16)
    if "LATESTV" not in syms:
        sys.exit("LATESTV not in build/forth.lbl -- build first")
    # The stack pointer and its bounds are assembly-time equates, so they are
    # in the source rather than the label file.
    for line in ZP.read_text().splitlines():
        m = re.match(r"(\w+)\s*=\s*\$([0-9A-Fa-f]+)", line.strip())
        if m:
            syms.setdefault(m.group(1), int(m.group(2), 16))
    wanted = ("XSAV", "DSTACK_TOP", "DSTACK_BOT")
    missing = [n for n in wanted if n not in syms]
    if missing:
        sys.exit(f"cannot find {', '.join(missing)}")
    symarg = ",".join(f"{n}={syms[n]}" for n in wanted)

    env = dict(os.environ, TEST=script, LATESTV=str(syms["LATESTV"]),
               SYMS=symarg)
    cmd = [
        "mame", "apple2ee", "-rompath", str(ROOT / "roms"), "-sl4", "",
        "-gameio", "joy", "-cfg_directory", str(ROOT / "cfg"),
        "-flop1", str(DISK), "-skip_gameinfo", "-window", "-nomaximize",
        "-nothrottle", "-seconds_to_run", "180", "-autoboot_delay", "0",
        "-autoboot_script", str(ROOT / "tools" / "contest.lua"),
        "-snapshot_directory", str(shots),
    ]
    # MAME's Lua print goes to stderr, so both streams have to be read.
    proc = subprocess.run(cmd, cwd=ROOT, env=env, capture_output=True, text=True)
    out = proc.stdout + proc.stderr

    print(f"\n=== {name} ===")
    passed = failed = 0
    for line in out.splitlines():
        if line.startswith(("PASS", "FAIL", "     ")):
            print("  " + line)
            if line.startswith("PASS"):
                passed += 1
            elif line.startswith("FAIL"):
                failed += 1
    if not passed and not failed and "RESULT " not in out:
        print("  no results -- the console may not have come up")
        return 0, 1
    return passed, failed


def main(argv):
    if "--list" in argv:
        print("\n".join(TESTS))
        return 0
    names = [a for a in argv[1:] if not a.startswith("-")] or list(TESTS)
    total_p = total_f = 0
    for name in names:
        if name not in TESTS:
            print(f"no such test: {name}")
            return 2
        p, f = run(name, TESTS[name])
        total_p += p
        total_f += f
    print(f"\n{'=' * 40}\n{total_p} passed, {total_f} failed")
    return 1 if total_f else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
