# Primo Z80 assembly project. Same targets locally and in CI.
#   make            universal .ptp (runtime colour/mono detect) + -bw / -color variants + WAVs
#   make test       unit tests in a headless Z80 emulator (z88dk-ticks) + tool tests
#   make check      verify every .ptp (structure, CRCs, memory ceiling)
NAME      ?= kettoatizediken
MAX_END   ?= 0xC800
# Pinned by digest on purpose: reproducible, and a moved tag cannot change what CI runs.
Z88DK_IMG ?= z88dk/z88dk@sha256:2aab19402c1846858e5fb80b1bb7582af2a94375c41a592512a9bef4bc90719f

ifeq ($(shell command -v z88dk-z80asm 2>/dev/null),)
RUN = docker run --rm --user $(shell id -u):$(shell id -g) -v $(CURDIR):/src -w /src $(Z88DK_IMG)
endif
ASM   = $(RUN) z88dk-z80asm -b -mz80 -Isrc -m
TICKS = $(RUN) z88dk-ticks -mz80
PTP   = python3 -I tools/ptp.py
SRC   = $(wildcard src/*.asm src/*.inc)
LANGS    = hu en
VARIANTS = $(foreach l,$(LANGS),$(NAME)-$(l) $(NAME)-$(l)-bw $(NAME)-$(l)-color)
TAPE     = ketto10
flags    = $(if $(findstring hu,$(1)),-DLANG_HU) $(if $(findstring -bw,$(1)),-DTARGET_BW) $(if $(findstring -color,$(1)),-DTARGET_COLOR)

.PHONY: all test check size clean
all: $(addprefix build/,$(addsuffix .ptp,$(VARIANTS))) $(addprefix build/,$(addsuffix .wav,$(VARIANTS))) check size

build/$(NAME)-%.bin: $(SRC)
	@mkdir -p build; $(ASM) $(call flags,$*) -o$@ src/main.asm
build/%.ptp: build/%.bin              ; $(PTP) build --name "$(subst $(NAME),$(TAPE),$*)" build/$*.bin $@
build/%.wav: build/%.ptp              ; $(PTP) wav $< $@

test: | build
	python3 -I tests/test_ptp.py
	$(ASM) -obuild/test_logic.bin tests/test_logic.asm
	$(TICKS) -iochar 1 -x build/test_logic.map -pc 0x4400 -l 0x4400 -end done build/test_logic.bin | tee build/test.log
	@grep -qx "ALL PASS" build/test.log || { echo "unit tests FAILED"; exit 1; }

build: ; @mkdir -p build

check:
	@for f in build/*.ptp; do $(PTP) verify --max-end $(MAX_END) $$f || exit 1; done

size:
	@for f in build/$(NAME)*.bin; do printf "%-28s %6d bytes\n" $$f $$(wc -c < $$f); done

clean: ; rm -rf build

# Screenshots from the headless emulator: assemble with -DRENDER_TEST, stream video RAM, convert to PNG.
.PHONY: shots
SCENES = board splash help
shots: | build
	@for l in hu en; do for m in BW COLOR; do for sc in $(SCENES); do \
	  fl=""; [ $$l = hu ] && fl="-DLANG_HU"; [ $$sc = splash ] && fl="$$fl -DRS_SPLASH"; [ $$sc = help ] && fl="$$fl -DRS_HELP"; \
	  $(ASM) -DRENDER_TEST $$fl -DTARGET_$$m -obuild/r_$$m.bin src/main.asm && \
	  $(TICKS) -iochar 1 -x build/r_$$m.map -pc 0x4400 -l 0x4400 -end rt_done build/r_$$m.bin 2>/dev/null | head -c 8192 > build/dump_$$m.bin && \
	  python3 -I tools/render.py $$( [ $$m = BW ] && echo mono || echo color ) build/dump_$$m.bin build/shot-$$l-$$sc-$$m.png || exit 1; \
	  done; done; done
