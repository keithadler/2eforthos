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
DISKFILES := $(wildcard disk/*)
# Generated into build/: the font is carved out of the Apple character ROM,
# and the boot source is src/system.fth converted to a byte table.
GENERATED := build/font.inc build/bootsrc.inc build/icons.inc
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
               -window -nomaximize -snapshot_directory $(SHOTS) \
               -cfg_directory $(CURDIR)/cfg -mouse \
               -resolution $(shell echo $$((560*$(SCALE))))x$(shell echo $$((384*$(SCALE))))

.PHONY: all roms disk run gui poke monitor clean

# MAME's per-machine config: the B&W monitor, and the mouse button bound to
# the game port's button 1.  MAME maps the mouse to the analog axes by
# default but not to the button, so clicks never reached the OS -- the
# pointer moved and nothing responded to pressing.
monitor:
	@mkdir -p cfg
	@printf '%s\n' \
	  '<?xml version="1.0"?>' \
	  '<mameconfig version="10">' \
	  ' <system name="$(MACHINE)">' \
	  '  <input>' \
	  '   <port tag=":a2video:a2_video_config" type="CONFIG" mask="7" defvalue="0" value="$(MONITOR)" />' \
	  '   <port tag=":gameio:joy:joystick_buttons" type="P1_BUTTON1" mask="16" defvalue="0">' \
	  '    <newseq type="standard">MOUSECODE_1_BUTTON1</newseq>' \
	  '   </port>' \
	  '  </input>' \
	  ' </system>' \
	  '</mameconfig>' > cfg/$(MACHINE).cfg
