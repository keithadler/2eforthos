# ---------------------------------------------------------------------------
# Apple ][+ build system:  6502 source -> flat binary -> bootable DOS 3.3 disk
#
#   make            assemble + link every src/*.s into build/$(PROG).bin
#   make disk       wrap it in a bootable DOS 3.3 .dsk that auto-BRUNs it
#   make run        boot that disk in MAME, exit after $(SECS)s, save a PNG
#   make gui        boot it and leave the window up to drive by hand
#   make poke       no-disk path: type the program into the monitor (tiny only)
#   make clean
#
# Knobs:  PROG=name  ORG=0x0800  SECS=20  VOLUME=254
# ---------------------------------------------------------------------------

PROG    ?= forth
SRCDIR  ?= src
ORG     ?= 0x6000
VOLUME  ?= 254
SECS    ?= 32

A2KIT   := $(HOME)/.cargo/bin/a2kit
ROMS    := $(CURDIR)/roms
SHOTS   := $(CURDIR)/shots

SRCS    := $(wildcard $(SRCDIR)/*.s)
# forth.s pulls the system in with .include, so every .inc is a dependency
INCS    := $(wildcard src/*.inc)
OBJS    := $(patsubst $(SRCDIR)/%.s,build/%.o,$(SRCS))
BIN     := build/$(PROG).bin
DSK     := build/$(PROG).dsk
DOSNAME := $(shell echo $(PROG) | tr '[:lower:]' '[:upper:]').BIN

# -sl4 "" drops the Mockingboard (we have no ROM for its Votrax speech chip).
# Slot 6 keeps its default Disk II controller so -flop1 has somewhere to go.
MAME_COMMON := apple2p -rompath $(ROMS) -sl4 "" -gameio joy -skip_gameinfo \
               -window -nomaximize -snapshot_directory $(SHOTS)

.PHONY: all roms disk run gui poke clean

all: $(BIN)

# Apple's ROMs are not in this repository; rebuild them from AppleWin and
# apple2js, verifying every CRC against what MAME expects.
roms:
	python3 tools/fetch-roms.py --dest $(ROMS)

build:
	@mkdir -p build

build/%.o: $(SRCDIR)/%.s $(INCS) src/apple2.cfg | build
	ca65 -g -I src -D DOS=1 -l build/$*.lst $< -o $@

$(BIN): $(OBJS) src/apple2.cfg
	ld65 -C src/apple2.cfg -S $(ORG) -m build/$(PROG).map -o $@ $(OBJS)
	@echo "$@: $$(wc -c < $@ | tr -d ' ') bytes loading at $(ORG)"

disk: $(DSK)

$(DSK): $(BIN)
	@rm -f $@
	$(A2KIT) mkdsk -v $(VOLUME) -t do -o dos33 -b -d $@
	$(A2KIT) put -d $@ -f $(DOSNAME) -t bin -a $$(( $(ORG) )) < $(BIN)
	@printf '10 PRINT CHR$$(4);"MAXFILES 1"\n20 PRINT CHR$$(4);"BRUN %s"\n' '$(DOSNAME)' \
	  | $(A2KIT) tokenize -t atxt -a 2049 \
	  | $(A2KIT) put -d $@ -f HELLO -t atok
	@$(A2KIT) catalog -d $@

# -nothrottle lets the host run the 1 MHz 6502 flat out (~17x), so $(SECS)
# emulated seconds cost about a second of wall clock.  Timing stays exact --
# the emulation is deterministic, only the real-time pacing is dropped.
run: $(DSK)
	@rm -rf $(SHOTS)/apple2p
	mame $(MAME_COMMON) -flop1 $(DSK) -nothrottle -seconds_to_run $(SECS)
	@echo "screenshot -> $(SHOTS)/apple2p/0000.png"

gui: $(DSK)
	mame $(MAME_COMMON) -flop1 $(DSK)

poke:
	./run.sh $(SRCDIR)/$(PROG).s

clean:
	rm -rf build shots
