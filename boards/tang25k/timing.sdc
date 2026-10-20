create_clock -name cpu_clk -period 20 [get_ports {clk}]
create_generated_clock -name sys_clk -source [get_ports {clk}] -multiply_by 3 -divide_by 5 [get_pins {system_clock/pll/CLKOUT0}]
# Exact shared X32 two-mode TMDS envelope; Education ignores PLL fractional tap.
create_clock -name serializer_clk -period 3.076923 [get_pins {clocks/select_clock/CLKOUT}]
create_generated_clock -name pixel_clk -source [get_pins {clocks/select_clock/CLKOUT}] -divide_by 5 [get_pins {clocks/pixels/CLKOUT}]
create_generated_clock -name sdram_clk -source [get_pins {system_clock/pll/CLKOUT0}] -divide_by 1 -invert [get_ports {sdram_clk}]
set_clock_uncertainty -setup 0.300 -to [get_clocks {cpu_clk sys_clk serializer_clk pixel_clk sdram_clk}]
set_clock_uncertainty -hold 0.300 -to [get_clocks {cpu_clk sys_clk serializer_clk pixel_clk sdram_clk}]
set_input_delay -clock sdram_clk -max 9.400 [get_ports {sdram_dq[*]}]
set_input_delay -clock sdram_clk -min 0.000 [get_ports {sdram_dq[*]}]
set_output_delay -clock sdram_clk -max 3.500 [get_ports {sdram_address[*] sdram_bank[*] sdram_ras_n sdram_cas_n sdram_we_n sdram_dqm[*] sdram_dq[*]}]
set_output_delay -clock sdram_clk -max 8.500 [get_ports {sdram_rank}]
set_output_delay -clock sdram_clk -min -2.800 [get_ports {sdram_rank sdram_address[*] sdram_bank[*] sdram_ras_n sdram_cas_n sdram_we_n sdram_dqm[*] sdram_dq[*]}]
set_max_delay -to [get_ports {uart_tx sd_sck sd_mosi sd_cs_n eth_sck eth_mosi eth_cs_n eth_reset_n rtc_scl rtc_sda}] 20.000
set_min_delay -to [get_ports {uart_tx sd_sck sd_mosi sd_cs_n eth_sck eth_mosi eth_cs_n eth_reset_n rtc_scl rtc_sda}] 0.000
# Exact first D only: stage1 to stage2 remains timed.
set_false_path -to [get_pins {button_meta_s0/D}]
set_false_path -to [get_pins {clocks/mode_meta_s0/D}]
set_false_path -to [get_pins {soc/memory_bridge/request_meta_s0/D}]
set_false_path -to [get_pins {soc/memory_bridge/response_meta_s0/D}]
set_false_path -to [get_pins {soc/irq_bridge/irq_meta_0_s0/D}]
set_false_path -to [get_pins {soc/irq_bridge/irq_meta_1_s0/D}]
set_false_path -to [get_pins {soc/irq_bridge/irq_meta_2_s0/D}]
set_false_path -to [get_pins {soc/irq_bridge/ack_meta_0_s0/D}]
set_false_path -to [get_pins {soc/irq_bridge/ack_meta_1_s0/D}]
set_false_path -to [get_pins {soc/bus/boot_uart/uart/rx_meta_s0/D}]
set_false_path -to [get_pins {soc/bus/video/lock_meta_s0/D}]
set_false_path -to [get_pins {soc/bus/video/frame_meta_s0/D}]
set_false_path -to [get_pins {soc/bus/video/enable_meta_s0/D}]
set_false_path -to [get_pins {soc/bus/video/mode_meta_s0/D}]
set_false_path -to [get_pins {soc/bus/spi/cd_meta_s0/D}]
set_false_path -to [get_pins {soc/bus/pmod/input_meta_0_s0/D}]
set_false_path -to [get_pins {soc/bus/pmod/input_meta_1_s0/D}]
set_false_path -to [get_pins {soc/bus/pmod/input_meta_2_s0/D}]
# Asynchronous assertion only; three local stages synchronize release.
set_false_path -to [get_pins {cpu_release_0_s0/PRESET}]
set_false_path -to [get_pins {cpu_release_1_s0/PRESET}]
set_false_path -to [get_pins {cpu_release_2_s0/PRESET}]
set_false_path -to [get_pins {system_release_0_s0/PRESET}]
set_false_path -to [get_pins {system_release_1_s0/PRESET}]
set_false_path -to [get_pins {system_release_2_s0/PRESET}]
set_false_path -to [get_pins {pixel_reset_pipe_0_s0/PRESET}]
set_false_path -to [get_pins {pixel_reset_pipe_1_s0/PRESET}]
set_false_path -to [get_pins {pixel_reset_pipe_2_s0/PRESET}]
# Held payload: 2FF toggle plus settle cycle precedes capture.
set_max_delay -from [get_regs {soc/memory_bridge/request_hold*_s0}] -to [get_regs {soc/memory_bridge/request_capture*_s0}] 30.000000
set_false_path -hold -from [get_regs {soc/memory_bridge/request_hold*_s0}] -to [get_regs {soc/memory_bridge/request_capture*_s0}]
# Held payload: 2FF toggle plus settle cycle precedes capture.
set_max_delay -from [get_regs {soc/memory_bridge/response_hold*_s0}] -to [get_regs {soc/memory_bridge/response_capture*_s0}] 19.000000
set_false_path -hold -from [get_regs {soc/memory_bridge/response_hold*_s0}] -to [get_regs {soc/memory_bridge/response_capture*_s0}]
set_max_delay -from [get_ports {sd_miso}] -to [get_regs {soc/bus/spi/rx_*}] 10.000
set_min_delay -from [get_ports {sd_miso}] -to [get_regs {soc/bus/spi/rx_*}] 0.000
set_max_delay -from [get_ports {eth_miso}] -to [get_regs {soc/bus/pmod/spi/rx_*}] 10.000
set_min_delay -from [get_ports {eth_miso}] -to [get_regs {soc/bus/pmod/spi/rx_*}] 0.000
