SHELL := sh
.DEFAULT_GOAL := all
ARCH := r32
BOARD ?= tang25k
SDK ?=
OUT ?= build/$(ARCH)
ifeq ($(filter build/%,$(OUT)),)
$(error OUT must be a directory below build/)
endif
ifneq ($(findstring ..,$(OUT)),)
$(error OUT cannot contain parent-directory components)
endif
HOSTCXX ?= c++
HOSTCXXFLAGS ?= -O2 -std=c++17
HOSTEXE := $(if $(filter Windows_NT,$(OS)),.exe,)
IVERILOG ?= iverilog
VVP ?= vvp
GOWIN ?= gw_sh
DEVICE ?= GW5A-LV25MG121NC1/I0
FPGA_PLACE ?= 3
TOP ?= $(if $(filter tang25k-crypto,$(BOARD)),r32_tang25k_crypto_top,r32_tang25k_soc_top)
BOOT_IMAGE ?=
include mk/sources.mk
.PHONY: all sim check fpga clean
all: $(OUT)/core.vvp
$(OUT)/core.vvp: $(CORE_SOURCES)
	mkdir -p "$(@D)"
	$(IVERILOG) -g2012 -s r32_core -o "$@" $(CORE_SOURCES)
$(OUT)/fpga-build$(HOSTEXE): tools/fpga.cpp
	mkdir -p "$(@D)"
	$(HOSTCXX) $(HOSTCXXFLAGS) "$<" -o "$@"
fpga: $(OUT)/fpga-build$(HOSTEXE)
	env R32_FPGA_PLACE="$(FPGA_PLACE)" "$<" "$(GOWIN)" "$(OUT)/fpga" "$(TOP)" "$(DEVICE)" "$(CST)" "$(SDC)" "$(BOOT_IMAGE)" $(FPGA_SOURCES)
clean:
	rm -rf -- "$(OUT)"

include mk/cases.mk
include mk/genisis.mk
include mk/crypto.mk
sim: $(addprefix case-,$(R32_CASES))
$(OUT)/core-test.vvp: $(CORE_SOURCES) tests/tb_core.v
	mkdir -p "$(@D)"
	$(IVERILOG) -g2012 -s tb_core -o "$@" $^
check: all sim $(OUT)/mmu-test.vvp
	$(VVP) "$(OUT)/mmu-test.vvp" +VECTORS=tests/vectors/mmu.dat
$(OUT)/mmu-test.vvp: rtl/mmu/r32_mmu.v tests/tb_mmu.v
	mkdir -p "$(@D)"
	$(IVERILOG) -g2012 -s tb_mmu -o "$@" $^

PROBE_CC = "$(if $(strip $(SDK)),$(SDK)/bin/,)r32-clang$(HOSTEXE)"
PROBE_LD = "$(if $(strip $(SDK)),$(SDK)/bin/,)r32-ld.lld$(HOSTEXE)"
PROBE_CPPFLAGS ?=
.PHONY: video-probe
video-probe: $(OUT)/video-probe.elf
$(OUT)/video-probe-start.o: tests/video_probe/start.s
	mkdir -p "$(@D)"
	$(PROBE_CC) -c "$<" -o "$@"
$(OUT)/video-probe.o: tests/video_probe/probe.c
	mkdir -p "$(@D)"
	$(PROBE_CC) $(PROBE_CPPFLAGS) -Oz -ffreestanding -fno-builtin -c "$<" -o "$@"
$(OUT)/video-probe.elf: $(OUT)/video-probe-start.o $(OUT)/video-probe.o tests/video_probe/probe.ld
	$(PROBE_LD) -m r32elf -T tests/video_probe/probe.ld $(OUT)/video-probe-start.o $(OUT)/video-probe.o -o "$@"
