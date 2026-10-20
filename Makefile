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
TOP ?= r32_tang25k_soc_top
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
	"$<" "$(GOWIN)" "$(OUT)/fpga" "$(TOP)" "$(DEVICE)" "$(CST)" "$(SDC)" "$(BOOT_IMAGE)" $(FPGA_SOURCES)
clean:
	rm -rf -- "$(OUT)"

include mk/cases.mk
sim: $(addprefix case-,$(R32_CASES))
$(OUT)/core-test.vvp: $(CORE_SOURCES) tests/tb_core.v
	mkdir -p "$(@D)"
	$(IVERILOG) -g2012 -s tb_core -o "$@" $^
check: all sim $(OUT)/mmu-test.vvp
	$(VVP) "$(OUT)/mmu-test.vvp" +VECTORS=tests/vectors/mmu.dat
$(OUT)/mmu-test.vvp: rtl/mmu/r32_mmu.v tests/tb_mmu.v
	mkdir -p "$(@D)"
	$(IVERILOG) -g2012 -s tb_mmu -o "$@" $^
