// Independent text scanout, 800x600 @60.317 Hz, 40 MHz pixel clock.
// CPU R/W port and pixel read port infer dual-port BRAM. No SDRAM arbitration
// is needed, so POST can report a failed/uninitialized external RAM on screen.
// Window F0010000/16 KiB: ID0 STATUS4 TEXT_GEOMETRY8 PIXEL_GEOMETRY12
// CONTROL16 (enable), FRAME20; text cells start at +256, 3700 aligned dwords,
// low 16 bits = background/foreground nibble + ASCII byte. No HPD/DDC claim.
module x32_text_video
    (input wire clk, reset, req_valid,
     output wire req_ready,
     input wire [13 : 0] req_offset,
     input wire [31 : 0] req_wdata,
     input wire [3 : 0] req_be,
     input wire req_write,
     output reg rsp_valid,
     input wire rsp_ready,
     output reg [31 : 0] rsp_rdata,
     output reg rsp_error,
     input wire pixel_clk, pixel_reset, pll_locked,
     output wire [26 : 0] pixel);
    (* ram_style = "block" *) reg [15 : 0] cells[0 : 4095];
    reg [7 : 0] font[0 : 2047];
    initial
    begin
        for (integer i = 0; i < 4096; i = i + 1)
            cells[i] = 16'h0f20;
        $readmemh("rtl/vendor/platform/rtl/SoC/Video/font8x16.hex", font);
    end
    reg enabled, lock_meta, lock_sync, frame_meta, frame_sync, frame_previous;
    reg read_pending;
    reg [11 : 0] held_index;
    reg [15 : 0] cpu_read_word;
    reg [31 : 0] frames;
    wire text_access = req_offset >= 256 && req_offset < 15056;
    wire known = text_access || req_offset == 0 || req_offset == 4 || req_offset == 8 ||
                 req_offset == 12 || req_offset == 16 || req_offset == 20;
    wire invalid = !known || req_offset[1 : 0] != 0 || req_be != 4'hf ||
                   (!req_write && req_wdata != 0) ||
                   (req_write &&
                    ((!text_access && req_offset != 16) || (text_access && |req_wdata[31 : 16]) ||
                     (req_offset == 16 && req_wdata > 1)));
    wire [11 : 0] cpu_index = req_offset[13 : 2] - 12'd64;
    wire [11 : 0] ram_cpu_index = read_pending ? held_index : cpu_index;
    // Memory ports deliberately have no resets/response muxes on their data
    // registers: this is a real synchronous dual-port BRAM, not thousands of
    // flip-flops and LUTs. The bus controller adds the response latency.
    always @(posedge clk)
    begin
        // GW5A DPB supports write-first/no-change, not read-before-write.
        // This bypass makes the CPU port's collision behavior explicit.
        if (req_valid && req_ready && !invalid && text_access && req_write)
        begin
            cells[ram_cpu_index] <= req_wdata[15 : 0];
            cpu_read_word <= req_wdata[15 : 0];
        end
        else
            cpu_read_word <= cells[ram_cpu_index];
    end
    reg frame_toggle;
    assign req_ready = !reset && !rsp_valid && !read_pending;
    always @(posedge clk)
    begin
        if (reset)
        begin
            enabled <= 1;
            lock_meta <= 0;
            lock_sync <= 0;
            frame_meta <= 0;
            frame_sync <= 0;
            frame_previous <= 0;
            frames <= 0;
            rsp_valid <= 0;
            rsp_rdata <= 0;
            rsp_error <= 0;
            read_pending <= 0;
            held_index <= 0;
        end
        else
        begin
            lock_meta <= pll_locked;
            lock_sync <= lock_meta;
            frame_meta <= frame_toggle;
            frame_sync <= frame_meta;
            frame_previous <= frame_sync;
            if (frame_previous != frame_sync)
                frames <= frames + 1'b1;
            if (rsp_valid && rsp_ready)
                rsp_valid <= 0;
            if (read_pending)
            begin
                rsp_valid <= 1;
                rsp_rdata <= {16'b0, cpu_read_word};
                rsp_error <= 0;
                read_pending <= 0;
            end
            if (req_valid && req_ready)
            begin
                rsp_valid <= 1;
                rsp_error <= invalid;
                rsp_rdata <= 0;
                if (!invalid)
                begin
                    if (text_access)
                    begin
                        if (!req_write)
                        begin
                            read_pending <= 1;
                            held_index <= cpu_index;
                            rsp_valid <= 0;
                        end
                    end
                    else if (req_write)
                        enabled <= req_wdata[0];
                    else
                        case (req_offset)
                            0:
                                rsp_rdata <= 32'h31545854; // TXT1.
                            4:
                                rsp_rdata <= {30'b0, enabled, lock_sync};
                            8:
                                rsp_rdata <= 32'h00250064; // 37 rows, 100 columns.
                            12:
                                rsp_rdata <= 32'h02580320; // 600 lines, 800 pixels.
                            16:
                                rsp_rdata <= {31'b0, enabled};
                            20:
                                rsp_rdata <= frames;
                            default: begin
                            end
                        endcase
                end
            end
        end
    end
    reg [10 : 0] x;
    reg [9 : 0] y;
    reg enable_meta, enable_sync;
    wire active = x < 800 && y < 600;
    wire visible_text = active && y < 592;
    wire [11 : 0] text_index = 12'(y[9 : 4]) * 12'd100 + 12'(x[9 : 3]);
    reg [15 : 0] character_word;
    reg [7 : 0] glyph;
    reg [2 : 0] x1, x2;
    reg [3 : 0] y1;
    reg [7 : 0] attribute2;
    reg hs1, vs1, de1, text1, hs2, vs2, de2, text2;
    always @(posedge pixel_clk)
    begin
        character_word <= cells[visible_text ? text_index : 12'd0];
        glyph <= font[{character_word[7] ? 7'd63 : character_word[6 : 0], y1}];
    end
    always @(posedge pixel_clk)
    begin
        if (pixel_reset)
        begin
            x <= 0;
            y <= 0;
            frame_toggle <= 0;
            enable_meta <= 0;
            enable_sync <= 0;
            x1 <= 0;
            x2 <= 0;
            y1 <= 0;
            attribute2 <= 8'h0f;
            hs1 <= 0;
            vs1 <= 0;
            de1 <= 0;
            text1 <= 0;
            hs2 <= 0;
            vs2 <= 0;
            de2 <= 0;
            text2 <= 0;
        end
        else
        begin
            enable_meta <= enabled;
            enable_sync <= enable_meta;
            if (x == 1055)
            begin
                x <= 0;
                if (y == 627)
                begin
                    y <= 0;
                    frame_toggle <= !frame_toggle;
                end
                else
                    y <= y + 1'b1;
            end
            else
                x <= x + 1'b1;
            x1 <= x[2 : 0];
            y1 <= y[3 : 0];
            hs1 <= x >= 840 && x < 968;
            vs1 <= y >= 601 && y < 605;
            de1 <= active;
            text1 <= visible_text && enable_sync;
            attribute2 <= character_word[15 : 8];
            x2 <= x1;
            hs2 <= hs1;
            vs2 <= vs1;
            de2 <= de1;
            text2 <= text1;
        end
    end
    wire lit = text2 && glyph[7 - x2];
    wire [3 : 0] color = lit ? attribute2[3 : 0] : attribute2[7 : 4];
    wire [7 : 0] red = {8{color[2]}} & (color[3] ? 8'hff : 8'haa);
    wire [7 : 0] green = {8{color[1]}} & (color[3] ? 8'hff : 8'haa);
    wire [7 : 0] blue = {8{color[0]}} & (color[3] ? 8'hff : 8'haa);
    assign pixel = {de2, vs2, hs2, red, green, blue};
endmodule
