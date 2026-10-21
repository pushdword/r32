// Curve25519 MMIO, SYS domain. No DMA or CPU-ISA changes.
// ID0/VERSION4/CAPS8/STATUS12/COMMAND16/CYCLES24. Commands1 X25519,
// 2 Ed25519 base,3 Ed25519 verify point,4 abort+wipe. Inputs at64..159:
// scalar-h[32], scalar-s[32], point[32]. Output encoded point at160..191.
// Pack consecutive bytes into little-endian words. Verify returns [s]B-[h]A.
// The caller handles SHA512, order reduction, canonical S and the R comparison.
module x32_curve_bus
    (input wire clk, reset, req_valid,
     output wire req_ready,
     input wire [7 : 0] req_offset,
     input wire [31 : 0] req_wdata,
     input wire [3 : 0] req_be,
     input wire req_write,
     output reg rsp_valid,
     input wire rsp_ready,
     output reg [31 : 0] rsp_rdata,
     output reg rsp_error);
    localparam IDLE = 0, WRITE_LOW = 1, WRITE_HIGH = 2, READ_LOW = 3, READ_LOW_CAPTURE = 4,
               READ_HIGH = 5, READ_HIGH_CAPTURE = 6;
    reg [2 : 0] state;
    reg [31 : 0] write_data;
    reg [9 : 0] word_address;
    reg [15 : 0] low_half;
    reg [23 : 0] input_mask;
    wire core_busy, core_done, core_valid;
    wire [31 : 0] core_cycles;
    reg invalid;
    reg [31 : 0] value;
    wire accepted = req_valid && req_ready;
    wire input_word = req_offset >= 64 && req_offset < 160;
    wire output_word = req_offset >= 160 && req_offset < 192;
    wire complete_inputs = req_wdata == 1
                               ? (input_mask[7 : 0] == 8'hff && input_mask[23 : 16] == 8'hff)
                           : req_wdata == 2 ? input_mask[7 : 0] == 8'hff
                                            : input_mask == 24'hffffff;
    always @*
    begin
        invalid = req_be != 15 || req_offset[1 : 0] != 0;
        value = 0;
        if (req_write)
        begin
            if (req_offset == 16)
            begin
                if (req_wdata >= 1 && req_wdata <= 3)
                    invalid = invalid || core_busy || core_done || !complete_inputs;
                else if (req_wdata != 4)
                    invalid = 1;
            end
            else if (input_word)
                invalid = invalid || core_busy || core_done;
            else
                invalid = 1;
        end
        else
            case (req_offset)
                0:
                    value = 32'h31565243;
                4:
                    value = 1;
                8:
                    value = 7;
                12:
                    value = {28'b0, core_done && !core_valid, core_valid, core_done, core_busy};
                24:
                    value = core_cycles;
                default:
                    invalid = invalid || !output_word || core_busy || !core_done || !core_valid;
            endcase
    end
    wire core_start = accepted && !invalid && req_write && req_offset == 16 && req_wdata != 4;
    wire core_clear = accepted && !invalid && req_write && req_offset == 16 && req_wdata == 4;
    wire host_write = state == WRITE_LOW || state == WRITE_HIGH;
    wire high_half = state == WRITE_HIGH || state == READ_HIGH || state == READ_HIGH_CAPTURE;
    wire [9 : 0] host_address = word_address + {9'b0, high_half};
    wire [15 : 0] host_data = high_half ? write_data[31 : 16] : write_data[15 : 0];
    wire [15 : 0] host_read;
    x32_curve_core core(clk,
                        reset,
                        core_clear,
                        core_start,
                        req_wdata[1 : 0],
                        core_busy,
                        core_done,
                        core_valid,
                        core_cycles,
                        host_write,
                        host_address,
                        host_data,
                        host_read);
    assign req_ready = !reset && state == IDLE && !rsp_valid;
    always @(posedge clk)
    begin
        if (reset)
        begin
            state <= IDLE;
            write_data <= 0;
            word_address <= 0;
            low_half <= 0;
            input_mask <= 0;
            rsp_valid <= 0;
            rsp_rdata <= 0;
            rsp_error <= 0;
        end
        else
        begin
            if (rsp_valid && rsp_ready)
                rsp_valid <= 0;
            case (state)
                WRITE_LOW:
                    state <= WRITE_HIGH;
                WRITE_HIGH: begin
                    state <= IDLE;
                    rsp_valid <= 1;
                    write_data <= 0;
                end
                READ_LOW:
                    state <= READ_LOW_CAPTURE;
                READ_LOW_CAPTURE: begin
                    low_half <= host_read;
                    state <= READ_HIGH;
                end
                READ_HIGH:
                    state <= READ_HIGH_CAPTURE;
                READ_HIGH_CAPTURE: begin
                    state <= IDLE;
                    rsp_valid <= 1;
                    rsp_rdata <= {host_read, low_half};
                    low_half <= 0;
                end
                default: begin
                end
            endcase
            if (accepted)
            begin
                rsp_valid <= 1;
                rsp_rdata <= invalid ? 32'b0 : value;
                rsp_error <= invalid;
                if (!invalid && req_write && input_word)
                begin
                    state <= WRITE_LOW;
                    rsp_valid <= 0;
                    write_data <= req_wdata;
                    word_address <= 10'd448 + ({2'b0, req_offset} - 10'd64) / 2;
                    input_mask[(req_offset - 64) / 4] <= 1;
                end
                else if (!invalid && !req_write && output_word)
                begin
                    state <= READ_LOW;
                    rsp_valid <= 0;
                    word_address <= 10'd496 + ({2'b0, req_offset} - 10'd160) / 2;
                end
                if (core_start || core_clear)
                    input_mask <= 0;
            end
        end
    end
endmodule
