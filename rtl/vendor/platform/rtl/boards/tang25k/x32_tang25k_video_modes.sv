// One fixed PLLA with two taps and the GW5A glitch-free DCS selector.
//50MHz*26=1300MHz VCO; /6.5=200MHz, /4=325MHz (UG306 ODIV0 fraction4/8).
// A mode change holds the pixel/TMDS pipeline reset before switching.
// System/USB clocks, CPU resets and SDRAM are independent and never changed.
module x32_tang25k_video_modes
    (input wire clk, reset, mode1024,
     output wire locked, serializer_clk, pixel_clk);
    wire pll_lock;
    wire [1 : 0] serial_clocks;
    wire [4 : 0] unused_clocks;
    wire unused_feedback;
    wire [7 : 0] unused_mdr;
    PLLA #(.FCLKIN("50"),
           .IDIV_SEL(1),
           .FBDIV_SEL(1),
           .MDIV_SEL(26),
           .ODIV0_SEL(6),
           .ODIV0_FRAC_SEL(4),
           .ODIV1_SEL(4),
           .CLKOUT0_EN("TRUE"),
           .CLKOUT1_EN("TRUE"),
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
            .LOCK(pll_lock),
            .CLKOUT0(serial_clocks[0]),
            .CLKOUT1(serial_clocks[1]),
            .CLKOUT2(unused_clocks[0]),
            .CLKOUT3(unused_clocks[1]),
            .CLKOUT4(unused_clocks[2]),
            .CLKOUT5(unused_clocks[3]),
            .CLKOUT6(unused_clocks[4]),
            .CLKFBOUT(unused_feedback));
    (* ASYNC_REG = "TRUE" *) reg mode_meta, mode_sync;
    reg selected;
    reg [5 : 0] hold;
    always @(posedge clk or posedge reset)
    begin
        if (reset)
        begin
            mode_meta <= 0;
            mode_sync <= 0;
            selected <= 0;
            hold <= 63;
        end
        else
        begin
            mode_meta <= mode1024;
            mode_sync <= mode_meta;
            if (selected != mode_sync)
            begin
                if (hold == 0)
                    hold <= 63;
                else if (hold == 62)
                begin
                    selected <= mode_sync;
                    hold <= 61;
                end
                else
                    hold <= hold - 1'b1;
            end
            else if (hold != 0)
                hold <= hold - 1'b1;
        end
    end
    // One-hot selection; both fixed taps keep running during the transition.
    DCS #(.DCS_MODE("RISING"))
        select_clock(.CLKIN0(serial_clocks[0]),
                     .CLKIN1(serial_clocks[1]),
                     .CLKIN2(1'b0),
                     .CLKIN3(1'b0),
                     .CLKSEL(selected ? 4'b0010 : 4'b0001),
                     .SELFORCE(1'b0),
                     .CLKOUT(serializer_clk));
    assign locked = pll_lock && (hold == 0) && !reset;
    CLKDIV #(.DIV_MODE("5"))
        pixels(.HCLKIN(serializer_clk),
               .RESETN(locked),
               .CALIB(1'b0),
               .CLKOUT(pixel_clk));
endmodule
