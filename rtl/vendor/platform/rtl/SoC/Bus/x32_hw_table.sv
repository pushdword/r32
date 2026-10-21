// Read-only hardware description generated from this SoC's composition.
// Return a bus error for writes and reads that are not aligned full dwords.
module x32_hw_table
    #(parameter integer RAM_WORDS = 4096,
      parameter [31 : 0] CPU_CLOCK_HZ = 50000000, CLOCK_HZ = 50000000, UART_BAUD = 115200,
      parameter [31 : 0] MAGIC = 32'h54445748,
      parameter ENABLE_BOARD_IO = 0,
      parameter ENABLE_KEYBOARD = 0,
      parameter integer CORE_COUNT = 1,
      parameter ENABLE_PMOD = 0,
      parameter ENABLE_BIOS_FLASH = 0,
      parameter ENABLE_VIDEO_MODES = 0,
      parameter ENABLE_CRYPTO = 0,
      parameter ENABLE_CURVE = 0)
    (input wire clk, reset, req_valid,
     output wire req_ready,
     input wire [11 : 0] req_offset,
     input wire [31 : 0] req_wdata,
     input wire [3 : 0] req_be,
     input wire req_write,
     output reg rsp_valid,
     input wire rsp_ready,
     output reg [31 : 0] rsp_rdata,
     output reg rsp_error);
    localparam [31 : 0] NONE = 32'hffffffff;
    localparam integer BASE_COUNT = ENABLE_KEYBOARD ? 8 : ENABLE_BOARD_IO ? 7 : 5;
    localparam integer PMOD_INDEX = 8 + (BASE_COUNT + (CORE_COUNT == 2 ? 2 : 0)) * 8;
    localparam integer FLASH_INDEX = PMOD_INDEX + (ENABLE_PMOD ? 8 : 0);
    localparam integer CRYPTO_INDEX = FLASH_INDEX + (ENABLE_BIOS_FLASH ? 8 : 0);
    localparam integer CURVE_INDEX = CRYPTO_INDEX + (ENABLE_CRYPTO ? 8 : 0);
    localparam integer RECORD_COUNT = BASE_COUNT + (CORE_COUNT == 2 ? 2 : 0) +
                                      (ENABLE_PMOD ? 1 : 0) + (ENABLE_BIOS_FLASH ? 1 : 0) +
                                      (ENABLE_CRYPTO ? 1 : 0) + (ENABLE_CURVE ? 1 : 0);
    wire [31 : 0] word_index = {22'b0, req_offset[11 : 2]};
    reg [31 : 0] word_data;
    always_comb
    begin
        word_data = 0;
        case (word_index)
            0:
                word_data = MAGIC;
            1:
                word_data = 1;
            2, 3:
                word_data = 32;
            4:
                word_data = RECORD_COUNT;
            5:
                word_data = 32 + RECORD_COUNT * 32;
            6:
                word_data = CLOCK_HZ;
            // CPU clock is in parameter0. The CPU record has no memory window or IRQ.
            8:
                word_data = 1;
            10:
                word_data = 1;
            13:
                word_data = NONE;
            14:
                word_data = CPU_CLOCK_HZ;
            // On-chip boot RAM, size follows the actual synthesis parameter.
            16:
                word_data = 2;
            18:
                word_data = 1;
            20:
                word_data = 32'(RAM_WORDS * 4);
            21:
                word_data = NONE;
            // External memory controller, two 32 MiB ranks.
            24:
                word_data = 3;
            26:
                word_data = 1;
            27:
                word_data = 32'h10000000;
            28:
                word_data = 32'h04000000;
            29:
                word_data = NONE;
            // UART v1: DATA/STATUS/CONTROL, nominal baud in parameter0.
            32:
                word_data = 4;
            34:
                word_data = 1;
            35:
                word_data = 32'hf0000000;
            36:
                word_data = 12;
            37:
                word_data = NONE;
            38:
                word_data = UART_BAUD;
            // Timer v1: eight registers, IRQ32, clock in parameter0.
            40:
                word_data = 5;
            42:
                word_data = 1;
            43:
                word_data = 32'hf0001000;
            44:
                word_data = 32;
            45:
                word_data = 32;
            46:
                word_data = CLOCK_HZ;
            // Text/TMDS controller with HPD/DDC unavailable.
            48:
                word_data = 6;
            50:
                word_data = 1;
            51:
                word_data = 32'hf0010000;
            52:
                word_data = ENABLE_VIDEO_MODES ? 32768 : 16384;
            53:
                word_data = NONE;
            54:
                word_data = 40000000;
            // SD SPI byte transport, physical active-low card-detect present.
            56:
                word_data = 7;
            58:
                word_data = 1;
            59:
                word_data = 32'hf0004000;
            60:
                word_data = 32;
            61:
                word_data = NONE;
            62:
                word_data = CLOCK_HZ;
            63:
                word_data = 1;
            // USB low-speed boot keyboard event controller, polled, no IRQ.
            64:
                word_data = 8;
            66:
                word_data = 1;
            67:
                word_data = 32'hf0005000;
            68:
                word_data = 32;
            69:
                word_data = NONE;
            70:
                word_data = 12000000;
            71:
                word_data = 1;
            default:
                word_data = 0;
        endcase
        if (CORE_COUNT == 2 && word_index >= 8 + BASE_COUNT * 8)
        begin
            word_data = 0;
            case (word_index - (8 + BASE_COUNT * 8))
                // A second CPU instance, then a platform control interface.
                0:
                    word_data = 1;
                1:
                    word_data = 1;
                2:
                    word_data = 1;
                5:
                    word_data = NONE;
                6:
                    word_data = CLOCK_HZ;
                8:
                    word_data = 9;
                10:
                    word_data = 1;
                11:
                    word_data = 32'hf0006000;
                12:
                    word_data = 64;
                13:
                    word_data = 33;
                14:
                    word_data = 2;
                default:
                    word_data = 0;
            endcase
        end
        if (ENABLE_PMOD && word_index >= PMOD_INDEX)
        begin
            word_data = 0;
            case (word_index - PMOD_INDEX)
                // Physical transport, not external RTC/Ethernet presence.
                0:
                    word_data = 10;
                2:
                    word_data = 1;
                3:
                    word_data = 32'hf0007000;
                4:
                    word_data = 64;
                5:
                    word_data = NONE;
                6:
                    word_data = CLOCK_HZ;
                7:
                    word_data = 3;
                default:
                    word_data = 0;
            endcase
        end
        if (ENABLE_BIOS_FLASH && word_index >= FLASH_INDEX)
        begin
            word_data = 0;
            case (word_index - FLASH_INDEX)
                0:
                    word_data = 11;
                2:
                    word_data = 1;
                3:
                    word_data = 32'he0000000;
                4:
                    word_data = 32'h01000000;
                5:
                    word_data = NONE;
                6:
                    word_data = 1000000;
                7:
                    word_data = 1;
                default:
                    word_data = 0;
            endcase
        end
        if (ENABLE_CRYPTO && word_index >= CRYPTO_INDEX)
        begin
            word_data = 0;
            case (word_index - CRYPTO_INDEX)
                // Optional AES128/256 GCM FIFO, polled, SYS clock domain.
                0:
                    word_data = 12;
                2:
                    word_data = 1;
                3:
                    word_data = 32'hf0003000;
                4:
                    word_data = 140;
                5:
                    word_data = NONE;
                6:
                    word_data = CLOCK_HZ;
                7:
                    word_data = 3;
                default:
                    word_data = 0;
            endcase
        end
        if (ENABLE_CURVE && word_index >= CURVE_INDEX)
        begin
            word_data = 0;
            case (word_index - CURVE_INDEX)
                0:
                    word_data = 13;
                2:
                    word_data = 1;
                3:
                    word_data = 32'hf0003100;
                4:
                    word_data = 192;
                5:
                    word_data = NONE;
                6:
                    word_data = CLOCK_HZ;
                7:
                    word_data = 7;
                default:
                    word_data = 0;
            endcase
        end
    end
    wire invalid = req_offset[1 : 0] != 0 || 32'(req_offset) >= 32 + RECORD_COUNT * 32 ||
                   req_write || req_be != 4'hf || req_wdata != 0;
    assign req_ready = !reset && !rsp_valid;
    always @(posedge clk)
    begin
        if (reset)
        begin
            rsp_valid <= 0;
            rsp_rdata <= 0;
            rsp_error <= 0;
        end
        else if (rsp_valid && rsp_ready)
            rsp_valid <= 0;
        else if (req_valid && req_ready)
        begin
            rsp_valid <= 1;
            rsp_error <= invalid;
            rsp_rdata <= invalid ? 0 : word_data;
        end
    end
endmodule
