CRYPTO_SOURCES := $(wildcard rtl/vendor/crypto/*.sv)
.PHONY: check-crypto
check-crypto: $(OUT)/crypto-aes.vvp $(OUT)/crypto-curve.vvp $(OUT)/crypto-route.vvp $(OUT)/crypto-hwdt.vvp $(OUT)/crypto-soc.vvp
	$(VVP) "$(OUT)/crypto-aes.vvp"
	$(VVP) "$(OUT)/crypto-curve.vvp"
	$(VVP) "$(OUT)/crypto-route.vvp"
	$(VVP) "$(OUT)/crypto-hwdt.vvp"
	$(VVP) "$(OUT)/crypto-soc.vvp"
$(OUT)/crypto-aes.vvp: $(CRYPTO_SOURCES) tests/crypto/tb_aes.sv
	mkdir -p "$(@D)"
	$(IVERILOG) -g2012 -s tb_crypto_bus -o "$@" $^
$(OUT)/crypto-curve.vvp: $(CRYPTO_SOURCES) tests/crypto/tb_curve.sv
	mkdir -p "$(@D)"
	$(IVERILOG) -g2012 -s tb -o "$@" $^
$(OUT)/crypto-route.vvp: $(CRYPTO_SOURCES) rtl/gui/r32_crypto_bus.v tests/crypto/tb_route.sv
	mkdir -p "$(@D)"
	$(IVERILOG) -g2012 -s tb -o "$@" $^
$(OUT)/crypto-hwdt.vvp: rtl/vendor/platform/rtl/SoC/Bus/x32_hw_table.sv tests/crypto/tb_hwdt.sv
	mkdir -p "$(@D)"
	$(IVERILOG) -g2012 -s tb -o "$@" $^
$(OUT)/crypto-soc.vvp: $(FPGA_SOURCES) tests/crypto/tb_soc.sv tests/crypto/boot.hex
	mkdir -p "$(@D)"
	$(IVERILOG) -g2012 -s tb -o "$@" $(FPGA_SOURCES) tests/crypto/tb_soc.sv
