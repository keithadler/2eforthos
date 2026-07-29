# ---------------------------------------------------------------------------
# Apple ][+ build system:  6502 source -> flat binary -> bootable DOS 3.3 disk
#
#   make            assemble + link every src/*.s into build/$(PROG).bin
#   make disk       lay it on a bootable disk with our own boot sector
#   make run        boot that disk in MAME, exit after $(SECS)s, save a PNG
#   make gui        boot it and leave the window up to drive by hand
#   make poke       no-disk path: type the program into the monitor (tiny only)
#   make clean
#
# Knobs:  PROG=name  ORG=0x0800  SECS=20  VOLUME=254
# ---------------------------------------------------------------------------

PROG    ?= forth
SRCDIR  ?= src
ORG     ?= 0x4000
VOLUME  ?= 254
# Sectors the loader steps between reads.  Must be coprime with 16 so that
# stepping still visits every sector.  Wider costs revolutions per track but
# gives the six-and-two decode time to finish before the next one arrives.
ILEAVE  ?= 5
SECS    ?= 42

A2KIT   := $(HOME)/.cargo/bin/a2kit
ROMS    := $(CURDIR)/roms
SHOTS   := $(CURDIR)/shots

SRCS    := $(wildcard $(SRCDIR)/*.s)
# forth.s pulls the system in with .include, so every .inc is a dependency
INCS    := $(wildcard src/*.inc)
DISKFILES := $(wildcard disk/*) $(wildcard examples/*.FTH)
# Generated into build/: the font is carved out of the Apple character ROM,
# and the boot source is src/system.fth converted to a byte table.
GENERATED := build/font.inc build/srcsecs.inc
BOOT1   := build/boot1.bin
OBJS    := $(patsubst $(SRCDIR)/%.s,build/%.o,$(SRCS))
BIN     := build/$(PROG).bin
DSK     := build/$(PROG).dsk
DOSNAME := $(shell echo $(PROG) | tr '[:lower:]' '[:upper:]').BIN

# Enhanced //e: 128K via the Extended 80-column card, which MAME already has
# as the default aux device -- that is what makes double hi-res available.
# -sl4 "" drops the Mockingboard (we have no ROM for its Votrax speech chip).
# Slot 6 keeps its default Disk II controller so -flop1 has somewhere to go.
MACHINE ?= apple2ee
# Double hi-res is a colour mode by default and one-pixel strokes fringe badly.
# MAME's monitor-type config selects B&W, which is what makes 560x192 read as
# 560 monochrome pixels.  Written before each run so it is never lost.
MONITOR ?= 4
# `make gui` boots at SPEED and then drops to true 1 MHz, because the //e
# repeats keys in hardware: held at 8x, one keypress arrives several times.
# BOOTFRAMES is how long to hurry for -- 60 frames is an emulated second.
SPEED ?= 8
BOOTFRAMES ?= 2000
# Window size as a multiple of the emulated screen.  MAME keeps the aspect
# ratio, so this is the box it fits the picture into.
SCALE ?= 2
MAME_COMMON := $(MACHINE) -rompath $(ROMS) -sl4 "" -gameio joy -skip_gameinfo \
               -snapshot_directory $(SHOTS) \
               -cfg_directory $(CURDIR)/cfg -mouse

# Only the interactive target puts anything on the display.
MAME_WINDOW := -window -nomaximize \
               -resolution $(shell echo $$((560*$(SCALE))))x$(shell echo $$((384*$(SCALE))))

# Headless, and it takes both halves: -video none on its own still opens a
# window on macOS, and a dummy SDL driver on its own fails to start OpenGL.
# MAME will still take a snapshot like this, which is the whole point -- an
# automated run has nothing to show anyone while it runs.
MAME_HEADLESS := SDL_VIDEODRIVER=dummy
MAME_NOVIDEO  := -video none -sound none

.PHONY: all roms disk dist run gui poke monitor test clean

# MAME's per-machine config: the B&W monitor, and the mouse button bound to
# the game port's button 1.  MAME maps the mouse to the analog axes by default
# but not to the button, so clicks never reached the OS -- the pointer moved
# and nothing responded to pressing it.
monitor:
	@mkdir -p cfg
	@printf '<?xml version="1.0"?>\n<mameconfig version="10">\n <system name="%s">\n  <input>\n   <port tag=":a2video:a2_video_config" type="CONFIG" mask="7" defvalue="0" value="%s" />\n   <port tag=":gameio:joy:joystick_buttons" type="P1_BUTTON1" mask="16" defvalue="0">\n    <newseq type="standard">MOUSECODE_1_BUTTON1</newseq>\n   </port>\n  </input>\n </system>\n</mameconfig>\n' \
	  '$(MACHINE)' '$(MONITOR)' > cfg/$(MACHINE).cfg

all: $(BIN)

# Apple's ROMs are not in this repository; rebuild them from AppleWin and
# apple2js, verifying every CRC against what MAME expects.
roms:
	python3 tools/fetch-roms.py --dest $(ROMS)

build:
	@mkdir -p build

build/font.inc: roms/apple2p/341-0036.chr tools/mkfont.py | build
	@python3 tools/mkfont.py $< $@ | head -1

# The system's own source goes on the disk rather than into the image, and
# the kernel streams it a sector at a time -- see tools/mkboot.py.
build/srcsecs.inc build/bootsrc.bin &: src/system.fth tools/mkboot.py | build
	@python3 tools/mkboot.py $< build/bootsrc.bin build/srcsecs.inc

roms/apple2p/341-0036.chr:
	@echo "Apple ROMs are not present.  Run: make roms" >&2; exit 1

build/%.o: $(SRCDIR)/%.s $(INCS) $(GENERATED) src/apple2.cfg | build
	ca65 -g -I src -I build -D DOS=1 -l build/$*.lst $< -o $@

# The boot loader replaces DOS entirely.  It has to know how big the kernel
# is, so that comes from the linked binary.
build/kernsecs.inc: $(BIN) | build
	@printf 'KERNSECS = %s\nKERNILEAVE = %s\n' \
	  $$(( ($$(wc -c < $(BIN)) + 255) / 256 )) '$(ILEAVE)' > $@
	@echo "kernel is $$(( ($$(wc -c < $(BIN)) + 255) / 256 )) sectors, interleave $(ILEAVE)"

$(BOOT1): boot/boot1.s build/kernsecs.inc src/d2core.inc src/apple2.cfg | build
	ca65 -g -I src -I build boot/boot1.s -o build/boot1.o
	ld65 -C src/apple2.cfg -S 0x0800 -o $@ build/boot1.o
	@echo "$@: $$(wc -c < $@ | tr -d ' ') bytes loading at 0x0800"

$(BIN): $(OBJS) src/apple2.cfg
	ld65 -C src/apple2.cfg -S $(ORG) -m build/$(PROG).map -Ln build/$(PROG).lbl -o $@ $(OBJS)
	@echo "$@: $$(wc -c < $@ | tr -d ' ') bytes loading at $(ORG)"

disk: $(DSK)

$(DSK): $(BIN) $(BOOT1) build/bootsrc.bin $(DISKFILES) src/system.fth
	@rm -f $@
	$(A2KIT) mkdsk -v $(VOLUME) -t do -o dos33 -d $@
	@python3 tools/mkdisk.py --reserve $@ 10
	@$(A2KIT) put -d $@ -f SYSTEM.FTH -t txt < src/system.fth
	@for f in $(DISKFILES); do \
	   $(A2KIT) put -d $@ -f $$(basename $$f) -t txt < $$f; done
	@python3 tools/mkdisk.py $@ $(BOOT1) $(BIN) $(ILEAVE) build/bootsrc.bin
	@$(A2KIT) catalog -d $@

# -nothrottle lets the host run the 1 MHz 6502 flat out (~17x), so $(SECS)
# emulated seconds cost about a second of wall clock.  Timing stays exact --
# the emulation is deterministic, only the real-time pacing is dropped.
# The OS writes to its own disk (delete, rename, lock), and MAME writes those
# changes back to the image.  Automated runs boot a scratch copy so they stay
# reproducible; `make gui` uses the real image so interactive changes stick.
run: $(DSK) monitor
	@rm -rf $(SHOTS)/$(MACHINE)
	@cp $(DSK) build/run.dsk
	$(MAME_HEADLESS) mame $(MAME_COMMON) $(MAME_NOVIDEO) -flop1 build/run.dsk \
	  -nothrottle -seconds_to_run $(SECS)
	@echo "screenshot -> $(SHOTS)/$(MACHINE)/0000.png"

gui: $(DSK) monitor
	BOOTSPEED=$(SPEED) BOOTFRAMES=$(BOOTFRAMES) \
	  mame $(MAME_COMMON) $(MAME_WINDOW) -flop1 $(DSK) \
	  -autoboot_delay 0 -autoboot_script tools/fastboot.lua

# Type Forth at the console and check machine state afterwards.  Each test is
# a separate boot, so the whole suite takes a few minutes.
#   make test              everything
#   make test T="arith"    named tests
# The shipped image.  build/ is scratch and is rebuilt constantly; this is
# the copy that is committed, refreshed deliberately rather than by every
# build, so it changes only when someone means it to.
dist: $(DSK)
	@mkdir -p dist
	@cp $(DSK) dist/2eforthos.dsk
	@echo "dist/2eforthos.dsk: $$(wc -c < dist/2eforthos.dsk) bytes"

test: $(DSK) monitor
	python3 tools/contest.py $(T)

# The standalone path that predates the kernel: assemble one file and run
# it on a bare machine, no disk and no Forth.  examples/hello.s is the
# whole of it.
poke:
	./run.sh examples/hello.s

clean:
	rm -rf build shots
