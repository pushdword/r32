// PMOD1 transport, not a declaration that an external module is present.
// SPI offsets 0..20 reuse x32_spi. CTRL24: RESET_N/SCL_LOW/SDA_LOW.
// INPUT28: synchronized SCL/SDA/INT_N. ID32=PMD1, CYCLES36 wraps at 32 bits.
// RAW_BLOCK40/FIFO44 extend SPI with exactly 1..512 payload bytes, no CRC.
// I2C outputs only sink low; the board pads release high through pull-ups.
module x32_pmod_devices
    #(parameter [31 : 0] CLOCK_HZ = 50000000)
    (input wire clk, reset, req_valid,
     output wire req_ready,
     input wire [5 : 0] offset,
     input wire [31 : 0] wdata,
     input wire [3 : 0] be,
     input wire write,
     output wire rsp_valid,
     input wire rsp_ready,
     output wire [31 : 0] rdata,
     output wire error,
     input wire [3 : 0] pins_in,
     output wire [5 : 0] pins_out);
    wire spi_access = offset < 24 || offset == 40 || offset == 44;
    wire [4 : 0] spi_offset = offset == 40 ? 5'd24 : offset == 44 ? 5'd28 : offset[4 : 0];
    wire sv, sr, se;
    wire [31 : 0] sd;
    reg gv, ge;
    reg [31 : 0] gd, cycles;
    reg [2 : 0] control;
    (* ASYNC_REG = "TRUE" *) reg [2 : 0] input_meta, input_sync;
    wire known = offset == 24 || offset == 28 || offset == 32 || offset == 36;
    wire bad = !known || be != 4'hf || (!write && wdata != 0) ||
               (write && (offset != 24 || wdata > 7));
    // A bus master holds the request until accepted. There is at most one
    // response outstanding, so its source stays unambiguous under stalls.
    reg response_gpio;
    // A synchronous FIFO read has one cycle with no response valid yet.
    // Keep GPIO requests behind that pending SPI response as well.
    assign req_ready = !reset && !sv && !gv && sr;
    assign rsp_valid = response_gpio ? gv : sv;
    assign rdata = response_gpio ? gd : sd;
    assign error = response_gpio ? ge : se;
    assign pins_out[5 : 3] = {control[2], control[1], control[0]};
    x32_spi #(.CLOCK_HZ(CLOCK_HZ),
              .ENABLE_RX_BLOCK(1),
              .RAW_BLOCK(1))
        spi(.clk(clk),
            .reset(reset),
            .req_valid(req_valid && spi_access && !gv),
            .req_ready(sr),
            .req_offset(spi_offset),
            .req_wdata(wdata),
            .req_be(be),
            .req_write(write),
            .rsp_valid(sv),
            .rsp_ready(rsp_ready && !response_gpio),
            .rsp_rdata(sd),
            .rsp_error(se),
            .sck(pins_out[0]),
            .mosi(pins_out[1]),
            .cs_n(pins_out[2]),
            .miso(pins_in[0]),
            .card_detect_n(pins_in[3]));
    always @(posedge clk)
    begin
        if (reset)
        begin
            control <= 0;
            cycles <= 0;
            input_meta <= 7;
            input_sync <= 7;
            gv <= 0;
            gd <= 0;
            ge <= 0;
            response_gpio <= 0;
        end
        else
        begin
            cycles <= cycles + 1'b1;
            input_meta <= pins_in[3 : 1];
            input_sync <= input_meta;
            if (gv && rsp_ready && response_gpio)
                gv <= 0;
            if (req_valid && req_ready)
            begin
                response_gpio <= !spi_access;
                if (!spi_access)
                begin
                    gv <= 1;
                    ge <= bad;
                    gd <= 0;
                    if (!bad)
                    begin
                        if (write)
                            control <= wdata[2 : 0];
                        else
                            case (offset)
                                24:
                                    gd <= {29'b0, control};
                                28:
                                    gd <= {29'b0, input_sync};
                                32:
                                    gd <= 32'h31444d50;
                                36:
                                    gd <= cycles;
                                default: begin
                                end
                            endcase
                    end
                end
            end
        end
    end
endmodule
