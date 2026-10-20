R32_CASES := hello dependencies memory branches atomics precise_alignment precise_illegal precise_load_error wrong_path csr sret csr_swap ipc random_integer muldiv fpu
.PHONY: case-hello
case-hello: $(OUT)/core-test.vvp
	$(VVP) "$<" +ROM=tests/vectors/hello/rom.mem +RAM=tests/vectors/hello/ram.mem +STALLS=0 +EXPECTED=tests/vectors/hello/expected.mem +COUNT=109
	$(VVP) "$<" +ROM=tests/vectors/hello/rom.mem +RAM=tests/vectors/hello/ram.mem +STALLS=1 +EXPECTED=tests/vectors/hello/expected.mem +COUNT=109
.PHONY: case-dependencies
case-dependencies: $(OUT)/core-test.vvp
	$(VVP) "$<" +ROM=tests/vectors/dependencies/rom.mem +RAM=tests/vectors/dependencies/ram.mem +STALLS=0 +EXPECTED=tests/vectors/dependencies/expected.mem +COUNT=12
	$(VVP) "$<" +ROM=tests/vectors/dependencies/rom.mem +RAM=tests/vectors/dependencies/ram.mem +STALLS=1 +EXPECTED=tests/vectors/dependencies/expected.mem +COUNT=12
.PHONY: case-memory
case-memory: $(OUT)/core-test.vvp
	$(VVP) "$<" +ROM=tests/vectors/memory/rom.mem +RAM=tests/vectors/memory/ram.mem +STALLS=0 +EXPECTED=tests/vectors/memory/expected.mem +COUNT=14
	$(VVP) "$<" +ROM=tests/vectors/memory/rom.mem +RAM=tests/vectors/memory/ram.mem +STALLS=1 +EXPECTED=tests/vectors/memory/expected.mem +COUNT=14
.PHONY: case-branches
case-branches: $(OUT)/core-test.vvp
	$(VVP) "$<" +ROM=tests/vectors/branches/rom.mem +RAM=tests/vectors/branches/ram.mem +STALLS=0 +EXPECTED=tests/vectors/branches/expected.mem +COUNT=31
	$(VVP) "$<" +ROM=tests/vectors/branches/rom.mem +RAM=tests/vectors/branches/ram.mem +STALLS=1 +EXPECTED=tests/vectors/branches/expected.mem +COUNT=31
.PHONY: case-atomics
case-atomics: $(OUT)/core-test.vvp
	$(VVP) "$<" +ROM=tests/vectors/atomics/rom.mem +RAM=tests/vectors/atomics/ram.mem +STALLS=0 +EXPECTED=tests/vectors/atomics/expected.mem +COUNT=10
	$(VVP) "$<" +ROM=tests/vectors/atomics/rom.mem +RAM=tests/vectors/atomics/ram.mem +STALLS=1 +EXPECTED=tests/vectors/atomics/expected.mem +COUNT=10
.PHONY: case-precise_alignment
case-precise_alignment: $(OUT)/core-test.vvp
	$(VVP) "$<" +ROM=tests/vectors/precise_alignment/rom.mem +RAM=tests/vectors/precise_alignment/ram.mem +STALLS=0 +EXPECTED=tests/vectors/precise_alignment/expected.mem +COUNT=3 +FAULT=1 +FAULT_PC=c +FAULT_CAUSE=5 +FAULT_ADDRESS=10000001
	$(VVP) "$<" +ROM=tests/vectors/precise_alignment/rom.mem +RAM=tests/vectors/precise_alignment/ram.mem +STALLS=1 +EXPECTED=tests/vectors/precise_alignment/expected.mem +COUNT=3 +FAULT=1 +FAULT_PC=c +FAULT_CAUSE=5 +FAULT_ADDRESS=10000001
.PHONY: case-precise_illegal
case-precise_illegal: $(OUT)/core-test.vvp
	$(VVP) "$<" +ROM=tests/vectors/precise_illegal/rom.mem +RAM=tests/vectors/precise_illegal/ram.mem +STALLS=0 +EXPECTED=tests/vectors/precise_illegal/expected.mem +COUNT=1 +FAULT=1 +FAULT_PC=4 +FAULT_CAUSE=0 +FAULT_ADDRESS=4
	$(VVP) "$<" +ROM=tests/vectors/precise_illegal/rom.mem +RAM=tests/vectors/precise_illegal/ram.mem +STALLS=1 +EXPECTED=tests/vectors/precise_illegal/expected.mem +COUNT=1 +FAULT=1 +FAULT_PC=4 +FAULT_CAUSE=0 +FAULT_ADDRESS=4
.PHONY: case-precise_load_error
case-precise_load_error: $(OUT)/core-test.vvp
	$(VVP) "$<" +ROM=tests/vectors/precise_load_error/rom.mem +RAM=tests/vectors/precise_load_error/ram.mem +STALLS=0 +EXPECTED=tests/vectors/precise_load_error/expected.mem +COUNT=2 +FAULT=1 +FAULT_PC=8 +FAULT_CAUSE=4 +FAULT_ADDRESS=90000000
	$(VVP) "$<" +ROM=tests/vectors/precise_load_error/rom.mem +RAM=tests/vectors/precise_load_error/ram.mem +STALLS=1 +EXPECTED=tests/vectors/precise_load_error/expected.mem +COUNT=2 +FAULT=1 +FAULT_PC=8 +FAULT_CAUSE=4 +FAULT_ADDRESS=90000000
.PHONY: case-wrong_path
case-wrong_path: $(OUT)/core-test.vvp
	$(VVP) "$<" +ROM=tests/vectors/wrong_path/rom.mem +RAM=tests/vectors/wrong_path/ram.mem +STALLS=0 +EXPECTED=tests/vectors/wrong_path/expected.mem +COUNT=3
	$(VVP) "$<" +ROM=tests/vectors/wrong_path/rom.mem +RAM=tests/vectors/wrong_path/ram.mem +STALLS=1 +EXPECTED=tests/vectors/wrong_path/expected.mem +COUNT=3
.PHONY: case-csr
case-csr: $(OUT)/core-test.vvp
	$(VVP) "$<" +ROM=tests/vectors/csr/rom.mem +RAM=tests/vectors/csr/ram.mem +STALLS=0 +EXPECTED=tests/vectors/csr/expected.mem +COUNT=6
	$(VVP) "$<" +ROM=tests/vectors/csr/rom.mem +RAM=tests/vectors/csr/ram.mem +STALLS=1 +EXPECTED=tests/vectors/csr/expected.mem +COUNT=6
.PHONY: case-sret
case-sret: $(OUT)/core-test.vvp
	$(VVP) "$<" +ROM=tests/vectors/sret/rom.mem +RAM=tests/vectors/sret/ram.mem +STALLS=0 +EXPECTED=tests/vectors/sret/expected.mem +COUNT=6 +FAULT=1 +FAULT_PC=18 +FAULT_CAUSE=7 +FAULT_ADDRESS=0
	$(VVP) "$<" +ROM=tests/vectors/sret/rom.mem +RAM=tests/vectors/sret/ram.mem +STALLS=1 +EXPECTED=tests/vectors/sret/expected.mem +COUNT=6 +FAULT=1 +FAULT_PC=18 +FAULT_CAUSE=7 +FAULT_ADDRESS=0
.PHONY: case-csr_swap
case-csr_swap: $(OUT)/core-test.vvp
	$(VVP) "$<" +ROM=tests/vectors/csr_swap/rom.mem +RAM=tests/vectors/csr_swap/ram.mem +STALLS=0 +EXPECTED=tests/vectors/csr_swap/expected.mem +COUNT=10
	$(VVP) "$<" +ROM=tests/vectors/csr_swap/rom.mem +RAM=tests/vectors/csr_swap/ram.mem +STALLS=1 +EXPECTED=tests/vectors/csr_swap/expected.mem +COUNT=10
.PHONY: case-ipc
case-ipc: $(OUT)/core-test.vvp
	$(VVP) "$<" +ROM=tests/vectors/ipc/rom.mem +RAM=tests/vectors/ipc/ram.mem +STALLS=0 +EXPECTED=tests/vectors/ipc/expected.mem +COUNT=129
	$(VVP) "$<" +ROM=tests/vectors/ipc/rom.mem +RAM=tests/vectors/ipc/ram.mem +STALLS=1 +EXPECTED=tests/vectors/ipc/expected.mem +COUNT=129
.PHONY: case-random_integer
case-random_integer: $(OUT)/core-test.vvp
	$(VVP) "$<" +ROM=tests/vectors/random_integer/rom.mem +RAM=tests/vectors/random_integer/ram.mem +STALLS=0 +EXPECTED=tests/vectors/random_integer/expected.mem +COUNT=648
	$(VVP) "$<" +ROM=tests/vectors/random_integer/rom.mem +RAM=tests/vectors/random_integer/ram.mem +STALLS=1 +EXPECTED=tests/vectors/random_integer/expected.mem +COUNT=648
.PHONY: case-muldiv
case-muldiv: $(OUT)/core-test.vvp
	$(VVP) "$<" +ROM=tests/vectors/muldiv/rom.mem +RAM=tests/vectors/muldiv/ram.mem +STALLS=0 +EXPECTED=tests/vectors/muldiv/expected.mem +COUNT=525
	$(VVP) "$<" +ROM=tests/vectors/muldiv/rom.mem +RAM=tests/vectors/muldiv/ram.mem +STALLS=1 +EXPECTED=tests/vectors/muldiv/expected.mem +COUNT=525
.PHONY: case-fpu
case-fpu: $(OUT)/core-test.vvp
	$(VVP) "$<" +ROM=tests/vectors/fpu/rom.mem +RAM=tests/vectors/fpu/ram.mem +STALLS=0 +EXPECTED=tests/vectors/fpu/expected.mem +COUNT=2883
	$(VVP) "$<" +ROM=tests/vectors/fpu/rom.mem +RAM=tests/vectors/fpu/ram.mem +STALLS=1 +EXPECTED=tests/vectors/fpu/expected.mem +COUNT=2883
