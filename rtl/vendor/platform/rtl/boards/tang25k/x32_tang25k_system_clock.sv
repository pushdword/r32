// Dual-core profile: 50 MHz oscillator -> 1.2 GHz VCO -> 30 MHz system clock.
// Video and USB retain their independent 40/200 MHz and 12 MHz clocks.
module x32_tang25k_system_clock
    (input wire clk, reset,
     output wire locked, system_clk);
    wire [5 : 0] unused_clocks;
    wire unused_feedback;
    wire [7 : 0] unused_mdr;
    PLLA #(.FCLKIN("50"),
           .IDIV_SEL(1),
           .FBDIV_SEL(1),
           .MDIV_SEL(24),
           .ODIV0_SEL(40),
           .CLKOUT0_EN("TRUE"),
           .CLKFB_SEL("INTERNAL"))
        pll(.CLKIN(clk),
            .CLKFB(1'b0),
            .RESET(reset),
            .PLLPWD(1'b0),
            .RESET_I(1'b0),
            .RESET_O(1'b0),
            .PSSEL(3'b0),
            .PSDIR(1'b0),
            .PSPULSE(1'b0),
            .SSCPOL(1'b0),
            .SSCON(1'b0),
            .SSCMDSEL(7'b0),
            .SSCMDSEL_FRAC(3'b0),
            .MDCLK(1'b0),
            .MDOPC(2'b0),
            .MDAINC(1'b0),
            .MDWDI(8'b0),
            .MDRDO(unused_mdr),
            .LOCK(locked),
            .CLKOUT0(system_clk),
            .CLKOUT1(unused_clocks[0]),
            .CLKOUT2(unused_clocks[1]),
            .CLKOUT3(unused_clocks[2]),
            .CLKOUT4(unused_clocks[3]),
            .CLKOUT5(unused_clocks[4]),
            .CLKOUT6(unused_clocks[5]),
            .CLKFBOUT(unused_feedback));
endmodule
