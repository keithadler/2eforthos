#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Assemble a 6502 source file and run it on an emulated Apple ][+ (MAME).
#
#   ./run.sh                 # builds and runs src/hello.s
#   ./run.sh src/other.s     # builds and runs something else
#   SECS=30 ./run.sh         # give the emulator longer before it exits
#   GUI=1 ./run.sh           # leave the window up to drive by hand
#
# The binary is poked into memory at $0300 through the Apple's own monitor
# ("CALL -151"), exactly the way you would have typed it in in 1979, then
# started with the monitor's "G" (go) command.  A screenshot of the final
# state lands in shots/apple2p/.
# ---------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")"

SRC="${1:-src/hello.s}"
NAME="$(basename "$SRC" .s)"
SECS="${SECS:-20}"
ORG=768                                  # $0300

mkdir -p build
ca65 -g -l "build/$NAME.lst" "$SRC" -o "build/$NAME.o"   # note: no -D DOS
ld65 -C src/apple2.cfg -S 0x0300 "build/$NAME.o" -o "build/$NAME.bin"
echo "built build/$NAME.bin ($(wc -c < "build/$NAME.bin" | tr -d ' ') bytes) -> \$0300"

# Turn the raw binary into a monitor typing session.
CMD="$(python3 - "build/$NAME.bin" "$ORG" <<'PY'
import sys
data = open(sys.argv[1], 'rb').read()
base = int(sys.argv[2])
out = ["CALL -151"]                                   # drop into the monitor
for i in range(0, len(data), 8):
    row = " ".join(f"{b:02X}" for b in data[i:i+8])
    out.append(f"{base+i:04X}: {row}")                # poke 8 bytes per line
out.append(f"{base:04X}G")                            # ...and run it
sys.stdout.write("\\n".join(out) + "\\n")             # \n == RETURN to MAME
PY
)"

MAME_ARGS=(
  apple2p
  -rompath        "$PWD/roms"
  -sl4 "" -sl6 ""                        # no Mockingboard, no Disk II
  -skip_gameinfo -window -nomaximize
  -autoboot_delay 3
  -autoboot_command "$CMD"
  -snapshot_directory "$PWD/shots"
)
[ "${GUI:-0}" = "1" ] || MAME_ARGS+=(-seconds_to_run "$SECS")

rm -rf shots/apple2p
exec mame "${MAME_ARGS[@]}"
