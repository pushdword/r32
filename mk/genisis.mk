GENISIS_CC = "$(if $(strip $(SDK)),$(SDK)/bin/,)r32-clang$(HOSTEXE)"
GENISIS_LD = "$(if $(strip $(SDK)),$(SDK)/bin/,)r32-ld.lld$(HOSTEXE)"
GENISIS_TOOL ?= $(OUT)/genisis-tool$(HOSTEXE)
GENISIS_DIR := firmware/genisis
GENISIS_OUT := $(OUT)/genisis
GENISIS_UNITS := resident platform enumerate post video fat_ro recovery sd_write boot_gui ui input setup pmod rtc w5500 dhcp
GENISIS_OBJECTS := $(GENISIS_OUT)/entry.o $(GENISIS_OUT)/memory.o $(addprefix $(GENISIS_OUT)/,$(addsuffix .o,$(GENISIS_UNITS)))
GENISIS_HEADERS := $(wildcard $(GENISIS_DIR)/include/*.h) $(GENISIS_DIR)/description.h $(GENISIS_DIR)/fat_ro/fat_ro.h
GENISIS_FLAGS := -Oz -ffreestanding -fno-builtin -fno-stack-protector -ffunction-sections -fdata-sections -I$(GENISIS_DIR)/include -I$(GENISIS_DIR) -I$(GENISIS_DIR)/fat_ro -DGENISIS_BOARD_IO=1 -DGENISIS_PMOD_DRIVERS=1
.PHONY: genisis check-genisis
genisis: $(GENISIS_OUT)/image.stamp
$(GENISIS_TOOL): tools/genisis.cpp
	mkdir -p "$(@D)"
	$(HOSTCXX) $(HOSTCXXFLAGS) "$<" -o "$@"
$(GENISIS_OUT)/%.o: $(GENISIS_DIR)/%.c $(GENISIS_HEADERS) $(GENISIS_TOOL)
	mkdir -p "$(@D)"
	$(GENISIS_CC) $(GENISIS_FLAGS) -S "$<" -o "$(@:.o=.direct.s)"
	"$(GENISIS_TOOL)" longcalls "$(@:.o=.direct.s)" "$(@:.o=.s)"
	$(GENISIS_CC) -c "$(@:.o=.s)" -o "$@"
$(GENISIS_OUT)/fat_ro.o: $(GENISIS_DIR)/fat_ro/fat_ro.c $(GENISIS_HEADERS) $(GENISIS_TOOL)
	mkdir -p "$(@D)"
	$(GENISIS_CC) $(GENISIS_FLAGS) -S "$<" -o "$(@:.o=.direct.s)"
	"$(GENISIS_TOOL)" longcalls "$(@:.o=.direct.s)" "$(@:.o=.s)"
	$(GENISIS_CC) -c "$(@:.o=.s)" -o "$@"
$(GENISIS_OUT)/sd_write.o: $(GENISIS_DIR)/sd.c
$(GENISIS_OUT)/%.o: $(GENISIS_DIR)/%.s
	mkdir -p "$(@D)"
	$(GENISIS_CC) -c "$<" -o "$@"
$(GENISIS_OUT)/genisis.elf: $(GENISIS_OBJECTS) $(GENISIS_DIR)/firmware.ld
	$(GENISIS_LD) -m r32elf --gc-sections -T $(GENISIS_DIR)/firmware.ld $(GENISIS_OBJECTS) -o "$@"
$(GENISIS_OUT)/image.stamp: $(GENISIS_OUT)/genisis.elf $(GENISIS_TOOL)
	"$(GENISIS_TOOL)" image "$<" "$(GENISIS_OUT)/bram.bin" "$(GENISIS_OUT)/firmware.hex" "$(GENISIS_OUT)/genisis.r32"
	touch "$@"
$(OUT)/genisis-test$(HOSTEXE): tests/genisis_image.cpp tools/genisis.cpp
	mkdir -p "$(@D)"
	$(HOSTCXX) $(HOSTCXXFLAGS) "$<" -o "$@"
check-genisis: $(OUT)/genisis-test$(HOSTEXE)
	env "$<"
