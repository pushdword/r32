// AES-GCM MMIO v1, one4KiB packet RAM, 32-bit FIFO transfers, no DMA.
// Registers: ID0/VERSION4/CAPS8/STATUS12/COMMAND16/MODE20/LENGTH24/AADLEN28,
// KEY32..60/NONCE64..72/TAG80..92/AAD96..124/INPUT128/OUTPUT132/LEFT136.
// COMMAND1 starts,2 wipes. MODE bit0 decrypt/bit1 AES256. All data registers
// contain four consecutive wire-order bytes in a little-endian CPU word.
// STATUS: busy0/done1/auth_ok2/auth_failure3/wiping4. Full aligned words only.
// Decrypted RAM is inaccessible before successful authentication. Failed tags
// trigger a complete1024-word overwrite before DONE is published.
module x32_crypto_bus
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
    localparam WIPE = 0, IDLE = 1, READ_REQUEST = 2, READ_CAPTURE = 3, READ_READY = 4,
               WRITE_WORD = 5, WRITE_READY = 6;
    reg [2 : 0] state;
    reg [9 : 0] wipe_index, word_address;
    reg [1 : 0] word_index;
    reg [127 : 0] block_buffer;
    reg [255 : 0] aad_registers;
    reg [95 : 0] nonce_registers;
    reg [127 : 0] tag_registers;
    reg [7 : 0] key_mask, aad_mask;
    reg [2 : 0] nonce_mask;
    reg [3 : 0] tag_mask;
    reg [1 : 0] mode;
    reg [12 : 0] length;
    reg [5 : 0] aad_length;
    reg [10 : 0] input_words, output_words;
    reg completed, authenticated, authentication_failure, wipe_failure, read_pending;
    reg [31 : 0] packet[0 : 1023], ram_word;
    wire engine_busy, engine_done, engine_auth;
    wire [127 : 0] engine_tag;
    wire engine_read, engine_write;
    wire [7 : 0] engine_read_index, engine_write_index;
    wire [127 : 0] engine_output;
    wire [10 : 0] expected_words = (length + 13'd3) >> 2;
    wire [3 : 0] expected_aad_words = (aad_length + 6'd3) >> 2;
    wire [7 : 0] needed_aad_mask = 8'hff >> (8 - expected_aad_words);
    wire device_busy = state != IDLE || engine_busy;
    wire accepted = req_valid && req_ready;
    reg invalid;
    reg [31 : 0] read_value;
    function automatic[31 : 0] byte_reverse
        (input [31 : 0] n);
        byte_reverse = {n[7 : 0], n[15 : 8], n[23 : 16], n[31 : 24]};
    endfunction
    always @*
    begin
        invalid = req_be != 4'hf || req_offset[1 : 0] != 0;
        read_value = 0;
        if (req_write)
        begin
            if (req_offset == 16)
            begin
                if (req_wdata == 1)
                    invalid = invalid || device_busy || completed ||
                              input_words != expected_words || key_mask[3 : 0] != 4'hf ||
                              (mode[1] && key_mask != 8'hff) || nonce_mask != 3'b111 ||
                              (mode[0] && tag_mask != 4'hf) ||
                              (aad_mask & needed_aad_mask) != needed_aad_mask;
                else if (req_wdata != 2)
                    invalid = 1;
            end
            else if (req_offset == 20)
                invalid = invalid || device_busy || completed || req_wdata > 3;
            else if (req_offset == 24)
                invalid =
                    invalid || device_busy || completed || input_words != 0 || req_wdata > 4096;
            else if (req_offset == 28)
                invalid = invalid || device_busy || completed || req_wdata > 32;
            else if ((req_offset >= 32 && req_offset <= 72) ||
                     (req_offset >= 80 && req_offset <= 124))
                invalid = invalid || device_busy || completed;
            else if (req_offset == 128)
                invalid = invalid || device_busy || completed || input_words >= expected_words;
            else
                invalid = 1;
        end
        else
        begin
            case (req_offset)
                0:
                    read_value = 32'h31434741;
                4:
                    read_value = 1;
                8:
                    read_value = 3; // AES128/256 GCM, fixed96-bit IV, full128-bit tag.
                12:
                    read_value = {27'b0,         state == WIPE, authentication_failure,
                                  authenticated, completed,     device_busy};
                24:
                    read_value = {19'b0, length};
                28:
                    read_value = {26'b0, aad_length};
                80, 84, 88, 92: begin
                    invalid = invalid || device_busy || !completed || !authenticated;
                    read_value = byte_reverse(tag_registers[127 - req_offset[3 : 2] * 32 -: 32]);
                end
                132:
                    invalid = invalid || device_busy || !completed || !authenticated ||
                              output_words >= expected_words;
                136:
                    read_value = {21'b0, expected_words - output_words};
                default:
                    invalid = 1;
            endcase
        end
    end
    wire start_command = accepted && !invalid && req_write && req_offset == 16 && req_wdata == 1;
    wire clear_command = accepted && !invalid && req_write && req_offset == 16 && req_wdata == 2;
    wire input_write = accepted && !invalid && req_write && req_offset == 128;
    wire output_read = accepted && !invalid && !req_write && req_offset == 132;
    wire key_word_write = accepted && !invalid && req_write && req_offset >= 32 && req_offset <= 60;
    // KEY writes preload the cipher's key RAM directly. There is no256-bit
    // MMIO key bank or a second256-bit input shift register in this profile.
    x32_gcm_engine #(.WORD_KEYS(1))
        engine(clk,
               reset,
               clear_command,
               start_command,
               mode[0],
               mode[1],
               256'b0,
               nonce_registers,
               aad_registers,
               aad_length,
               length,
               tag_registers,
               engine_busy,
               engine_done,
               engine_auth,
               engine_tag,
               engine_read,
               engine_read_index,
               state == READ_READY,
               block_buffer,
               engine_write,
               engine_write_index,
               engine_output,
               state == WRITE_READY,
               key_word_write,
               req_offset[4 : 2],
               byte_reverse(req_wdata));
    wire [9 : 0] ram_address = state == READ_REQUEST ? word_address : output_words[9 : 0];
    wire [31 : 0] input_mask = input_words + 1'b1 == expected_words && length[1 : 0] != 0
                                   ? (32'hffffffff >> (32 - {length[1 : 0], 3'b000}))
                                   : 32'hffffffff;
    wire packet_write = state == WIPE || input_write || state == WRITE_WORD;
    wire [9 : 0] packet_write_address = state == WIPE ? wipe_index
                                        : input_write ? input_words[9 : 0]
                                                      : word_address;
    wire [31 : 0] packet_write_data = state == WIPE ? 32'b0
                                      : input_write ? (req_wdata & input_mask)
                                                    : byte_reverse(block_buffer[127 : 96]);
    always @(posedge clk)
    begin
        ram_word <= packet[ram_address];
        if (packet_write)
            packet[packet_write_address] <= packet_write_data;
    end
    assign req_ready = !reset && !rsp_valid && !read_pending;
    always @(posedge clk)
    begin
        if (reset)
        begin
            state <= WIPE;
            wipe_index <= 0;
            word_address <= 0;
            word_index <= 0;
            block_buffer <= 0;
            aad_registers <= 0;
            nonce_registers <= 0;
            tag_registers <= 0;
            key_mask <= 0;
            aad_mask <= 0;
            nonce_mask <= 0;
            tag_mask <= 0;
            mode <= 0;
            length <= 0;
            aad_length <= 0;
            input_words <= 0;
            output_words <= 0;
            completed <= 0;
            authenticated <= 0;
            authentication_failure <= 0;
            wipe_failure <= 0;
            read_pending <= 0;
            rsp_valid <= 0;
            rsp_rdata <= 0;
            rsp_error <= 0;
        end
        else
        begin
            if (rsp_valid && rsp_ready)
                rsp_valid <= 0;
            if (read_pending)
            begin
                read_pending <= 0;
                rsp_valid <= 1;
                rsp_rdata <= ram_word;
                rsp_error <= 0;
            end
            case (state)
                WIPE: begin
                    if (wipe_index == 1023)
                    begin
                        state <= IDLE;
                        block_buffer <= 0;
                        word_address <= 0;
                        word_index <= 0;
                        if (wipe_failure)
                        begin
                            completed <= 1;
                            authentication_failure <= 1;
                        end
                    end
                    else
                        wipe_index <= wipe_index + 1'b1;
                end
                IDLE: begin
                    if (engine_read)
                    begin
                        word_address <= {engine_read_index, 2'b00};
                        word_index <= 0;
                        block_buffer <= 0;
                        state <= READ_REQUEST;
                    end
                    else if (engine_write)
                    begin
                        word_address <= {engine_write_index, 2'b00};
                        word_index <= 0;
                        block_buffer <= engine_output;
                        state <= WRITE_WORD;
                    end
                end
                READ_REQUEST:
                    state <= READ_CAPTURE;
                READ_CAPTURE: begin
                    block_buffer <=
                        {block_buffer[95 : 0],
                         {1'b0, word_address} < expected_words ? byte_reverse(ram_word) : 32'b0};
                    if (word_index == 3)
                        state <= READ_READY;
                    else
                    begin
                        word_index <= word_index + 1'b1;
                        word_address <= word_address + 1'b1;
                        state <= READ_REQUEST;
                    end
                end
                READ_READY: begin
                    state <= IDLE;
                    block_buffer <= 0;
                end
                WRITE_WORD: begin
                    block_buffer <= {block_buffer[95 : 0], 32'b0};
                    if (word_index == 3)
                        state <= WRITE_READY;
                    else
                    begin
                        word_index <= word_index + 1'b1;
                        word_address <= word_address + 1'b1;
                    end
                end
                WRITE_READY: begin
                    state <= IDLE;
                    block_buffer <= 0;
                end
                default: begin
                    state <= WIPE;
                    wipe_index <= 0;
                    wipe_failure <= 0;
                    completed <= 0;
                    authenticated <= 0;
                end
            endcase
            if (engine_done)
            begin
                if (engine_auth)
                begin
                    completed <= 1;
                    authenticated <= 1;
                    tag_registers <= engine_tag;
                end
                else
                begin
                    state <= WIPE;
                    wipe_index <= 0;
                    wipe_failure <= 1;
                    authenticated <= 0;
                    completed <= 0;
                    tag_registers <= 0;
                end
            end
            if (accepted)
            begin
                rsp_valid <= 1;
                rsp_error <= invalid;
                rsp_rdata <= invalid ? 0 : read_value;
                if (output_read)
                begin
                    rsp_valid <= 0;
                    read_pending <= 1;
                    output_words <= output_words + 1'b1;
                end
                if (!invalid && req_write)
                begin
                    if (req_offset == 20)
                        mode <= req_wdata[1 : 0];
                    else if (req_offset == 24)
                        length <= req_wdata[12 : 0];
                    else if (req_offset == 28)
                        aad_length <= req_wdata[5 : 0];
                    else if (req_offset >= 32 && req_offset <= 60)
                    begin
                        key_mask[req_offset[4 : 2]] <= 1;
                    end
                    else if (req_offset >= 64 && req_offset <= 72)
                    begin
                        nonce_registers[95 - req_offset[3 : 2] * 32 -: 32] <=
                            byte_reverse(req_wdata);
                        nonce_mask[req_offset[3 : 2]] <= 1;
                    end
                    else if (req_offset >= 80 && req_offset <= 92)
                    begin
                        tag_registers[127 - req_offset[3 : 2] * 32 -: 32] <=
                            byte_reverse(req_wdata);
                        tag_mask[req_offset[3 : 2]] <= 1;
                    end
                    else if (req_offset >= 96 && req_offset <= 124)
                    begin
                        aad_registers[255 - req_offset[4 : 2] * 32 -: 32] <=
                            byte_reverse(req_wdata);
                        aad_mask[req_offset[4 : 2]] <= 1;
                    end
                    else if (input_write)
                        input_words <= input_words + 1'b1;
                end
            end
            if (start_command)
            begin
                nonce_registers <= 0;
                aad_registers <= 0;
                tag_registers <= 0;
                key_mask <= 0;
                nonce_mask <= 0;
                aad_mask <= 0;
                tag_mask <= 0;
                output_words <= 0;
                authenticated <= 0;
                authentication_failure <= 0;
                wipe_failure <= 0;
            end
            if (clear_command)
            begin
                state <= WIPE;
                wipe_index <= 0;
                word_address <= 0;
                word_index <= 0;
                block_buffer <= 0;
                aad_registers <= 0;
                nonce_registers <= 0;
                tag_registers <= 0;
                key_mask <= 0;
                aad_mask <= 0;
                nonce_mask <= 0;
                tag_mask <= 0;
                mode <= 0;
                length <= 0;
                aad_length <= 0;
                input_words <= 0;
                output_words <= 0;
                completed <= 0;
                authenticated <= 0;
                authentication_failure <= 0;
                wipe_failure <= 0;
            end
        end
    end
endmodule
