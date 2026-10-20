// Independent PLLA: 50 MHz reference -> 1200 MHz VCO -> /100 = 12 MHz USB LS.
// Keeps the already working video PLL coefficients and clock tree unchanged.
module x32_tang25k_usb_clock(input wire clk,reset,output wire locked,usb_clk);
    wire [5:0] unused_clocks;wire unused_feedback;wire [7:0] unused_mdr;
    PLLA #(.FCLKIN("50"),.IDIV_SEL(1),.FBDIV_SEL(1),.MDIV_SEL(24),
        .ODIV0_SEL(100),.CLKOUT0_EN("TRUE"),.CLKFB_SEL("INTERNAL")) pll(
        .CLKIN(clk),.CLKFB(1'b0),.RESET(reset),.PLLPWD(1'b0),.RESET_I(1'b0),.RESET_O(1'b0),
        .PSSEL(3'b0),.PSDIR(1'b0),.PSPULSE(1'b0),.SSCPOL(1'b0),.SSCON(1'b0),
        .SSCMDSEL(7'b0),.SSCMDSEL_FRAC(3'b0),.MDCLK(1'b0),.MDOPC(2'b0),.MDAINC(1'b0),.MDWDI(8'b0),
        .MDRDO(unused_mdr),.LOCK(locked),.CLKOUT0(usb_clk),.CLKOUT1(unused_clocks[0]),
        .CLKOUT2(unused_clocks[1]),.CLKOUT3(unused_clocks[2]),.CLKOUT4(unused_clocks[3]),
        .CLKOUT5(unused_clocks[4]),.CLKOUT6(unused_clocks[5]),.CLKFBOUT(unused_feedback));
endmodule
