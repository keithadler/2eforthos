#!/usr/bin/env python3
"""Run the desktop UI tests.

Each test is a short script of pointer moves, clicks and keystrokes, followed
by assertions against the OS's own variables.  Checking state rather than
pixels is what makes these worth having: a screenshot tells you something
changed, a variable tells you what the system believes.

    python3 tools/uitest.py            run everything
    python3 tools/uitest.py drag calc  run named tests
    python3 tools/uitest.py --list
"""

import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DISK = ROOT / "build" / "run.dsk"
LBL  = ROOT / "build" / "forth.lbl"

# Where the icons sit, so tests can aim at them.  Byte column 70 is x=490,
# and each icon is 14 wide by 16 tall with its caption beneath.
CALC_ICON = (495, 30)
DISK_ICON = (495, 70)

TESTS = {

"pointer": """
    point 200 100
    checka PX 200 3
    point 480 60
    checka PX 480 3
    point 480 150
    checka PX 480 3
""",

# x drifting when y moves is the game port crosstalk; the pointer must be
# independent on the two axes.
"crosstalk": """
    point 425 170
    checka PX 425 3
    point 425 120
    checka PX 425 3
    point 425 60
    checka PX 425 3
    point 425 30
    checka PX 425 3
""",

"icon-select": """
    point 495 30
    click
    unclick
    check ISEL 0
    point 495 70
    click
    unclick
    check ISEL 1
""",

# Two clicks close together in time and place open the application.
"double-click": """
    point 495 30
    click
    unclick
    click
    unclick
    wait 120
    check CALCON -1
    shot
""",

# The calculator has to be a real window, or it cannot be picked up.
"calc-is-window": """
    point 495 30
    click
    unclick
    click
    unclick
    wait 120
    check CALCON -1
    check NWIN 2
    show CALCWIN
""",

# Grab the title bar, carry it somewhere else, drop it, and check the window
# actually went there.  The calculator opens at 154,40; the pointer moves by
# about (60,56), so that is where its corner should end up.
"drag": """
    point 495 30
    click
    unclick
    click
    unclick
    wait 120
    checkwin 1 X1 154
    point 200 44
    click
    unclick
    wait 30
    point 260 100
    wait 90
    click
    unclick
    wait 150
    checkwin 1 X1 214 6
    checkwin 1 Y1 96 6
    checkwin 1 X2 410 6
    checkwin 1 Y2 184 6
    check NWIN 2
    check CALCON -1
    shot
""",

# Dragging must not leave the outline behind: it is XORed on, so an odd
# number of draws would burn it into the desktop.  BSHOWN records whether one
# is still up.
"drag-clean": """
    point 495 30
    click
    unclick
    click
    unclick
    wait 120
    point 200 44
    click
    unclick
    wait 30
    point 300 120
    wait 90
    click
    unclick
    wait 150
    check BSHOWN 0
    check GRAB -1
    shot
""",

# The keyboard has to carry a window too, since the machine may have no
# mouse at all.  IJKL step the pointer ten pixels at a time.
"drag-keyboard": """
    point 495 30
    click
    unclick
    click
    unclick
    wait 120
    point 200 44
    click
    unclick
    wait 150
    key L
    key L
    key L
    key K
    key K
    wait 60
    click
    unclick
    wait 150
    check BSHOWN 0
    checkwin 1 X1 184 6
    checkwin 1 Y1 60 6
""",

"calc-arithmetic": """
    point 495 30
    click
    unclick
    click
    unclick
    wait 120
    key 12
    check ENT 12
    key +
    key 30
    key =
    wait 60
    check ACC 42
    shot
""",

"calc-close": """
    point 495 30
    click
    unclick
    click
    unclick
    wait 120
    check CALCON -1
    key Q
    wait 120
    check CALCON 0
    check NWIN 1
""",

# The list starts three text rows below the window top, so with the explorer
# at y=16 a click at y=44 lands on the first entry and every eight pixels
# below that is the next one.
"explorer-select": """
    point 100 44
    click
    unclick
    wait 120
    check ESEL 0
    point 100 60
    click
    unclick
    wait 120
    check ESEL 2
    point 100 76
    click
    unclick
    wait 120
    check ESEL 4
""",

# There are five files and room for eighteen, so a click past the end of the
# list must leave the selection alone rather than run off it.
"explorer-bounds": """
    point 100 76
    click
    unclick
    wait 120
    check ESEL 4
    point 100 140
    click
    unclick
    wait 120
    check ESEL 4
    point 100 20
    click
    unclick
    wait 120
    check ESEL 4
""",

# The whole catalog fits, so scrolling has nowhere to go and must stay put
# rather than walk the list off the top.
"explorer-scroll": """
    key D
    key D
    wait 120
    check ETOP 0
    key U
    wait 120
    check ETOP 0
""",

# The list starts three text rows below the window top, so a click at y=60
# lands on entry 2 and one at y=84 on entry 5.
"probe": """
    show NFILE
    show EROWS
    show EROW
    show ETROW
    show NFREE
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
    wanted = ("PX", "PY", "PVIS", "MAXIS", "TICKS")
    symarg = ",".join(f"{n}={syms[n]}" for n in wanted if n in syms)

    env = dict(os.environ, TEST=script, LATESTV=str(syms["LATESTV"]),
               SYMS=symarg)
    cmd = [
        "mame", "apple2ee", "-rompath", str(ROOT / "roms"), "-sl4", "",
        "-gameio", "joy", "-cfg_directory", str(ROOT / "cfg"), "-mouse",
        "-flop1", str(DISK), "-skip_gameinfo", "-window", "-nomaximize",
        "-nothrottle", "-seconds_to_run", "150", "-autoboot_delay", "0",
        "-autoboot_script", str(ROOT / "tools" / "uitest.lua"),
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
        print("  no results -- the machine may not have reached the desktop")
        return 0, 1
    return passed, failed


def main(argv):
    if "--list" in argv:
        print("\n".join(TESTS))
        return 0
    names = ([a for a in argv[1:] if not a.startswith("-")]
             or [n for n in TESTS if n != "probe"])
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
