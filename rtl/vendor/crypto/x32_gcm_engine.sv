// Bounded AES-GCM packet engine. Fixed96-bit nonces, full128-bit tags,
// payload0..4096B and AAD0..32B. Key/block byte order follows FIPS197.
// The enclosing bus device MUST withhold decrypted output until done/auth_ok,
// and overwrite its packet RAM on authentication failure or abort.
// Capture parameters and key_data on the accepted start edge.
// The wrapper can then erase its staging registers.
module x32_gcm_engine
    #(parameter WORD_KEYS = 0)
    (input wire clk, reset, clear, start, decrypt, key_256,
     input wire [255 : 0] key_data,
     input wire [95 : 0] nonce,
     input wire [255 : 0] aad,
     input wire [5 : 0] aad_bytes,
     input wire [12 : 0] payload_bytes,
     input wire [127 : 0] expected_tag,
     output wire busy,
     output reg done, auth_ok,
     output reg [127 : 0] tag,
     output wire read_valid,
     output wire [7 : 0] read_index,
     input wire read_ready,
     input wire [127 : 0] read_data,
     output wire write_valid,
     output wire [7 : 0] write_index,
     output wire [127 : 0] write_data,
     input wire write_ready,
     input wire key_word_valid,
     input wire [2 : 0] key_word_index,
     input wire [31 : 0] key_word_value);
    localparam IDLE = 0, KEY_WAIT = 2, H_START = 3, H_WAIT = 4, J_START = 5, J_WAIT = 6,
               AAD_START = 7, AAD_WAIT = 8, READ = 9, CTR_START = 10, CTR_WAIT = 11,
               HASH_START = 12, HASH_WAIT = 13, WRITE = 14, LEN_START = 15, LEN_WAIT = 16,
               FINISH = 17, KEY_CLEAR = 18, KEY_CLEAR_WAIT = 19;
    reg [4 : 0] phase;
    reg mode_decrypt;
    reg [255 : 0] aad_copy;
    reg [95 : 0] nonce_copy;
    reg [5 : 0] aad_length, aad_remaining;
    reg [12 : 0] payload_length, remaining;
    reg [7 : 0] block_index;
    reg [31 : 0] counter;
    reg [127 : 0] h, tag_mask, output_block, cipher_block, tag_copy;
    wire aes_busy, aes_key_ready, aes_done;
    wire [127 : 0] aes_result;
    wire aes_start = phase == H_START || phase == J_START || phase == CTR_START;
    wire [127 : 0] aes_input = phase == H_START   ? 128'b0
                               : phase == J_START ? {nonce_copy, 32'd1}
                                                  : {nonce_copy, counter};
    // Capture the key directly in the cipher on packet acceptance. Keeping
    // another256-bit copy here adds routing and registers without useful work.
    wire begin_packet =
             phase == IDLE && start && !aes_busy && aad_bytes <= 32 && payload_bytes <= 4096;
    x32_aes_core #(.WORD_KEYS(WORD_KEYS))
        cipher(clk,
               reset,
               clear || phase == KEY_CLEAR,
               begin_packet,
               key_256,
               key_data,
               aes_start,
               aes_input,
               aes_busy,
               aes_key_ready,
               aes_done,
               aes_result,
               key_word_valid,
               key_word_index,
               key_word_value);
    function automatic[127 : 0] byte_mask
        (input [4 : 0] bytes);
        integer i;
        begin
            byte_mask = 0;
            for (i = 0; i < 16; i = i + 1)
                if (i < bytes)
                    byte_mask[127 - i * 8 -: 8] = 8'hff;
        end
    endfunction
    wire [4 : 0] block_bytes = remaining >= 16 ? 5'd16 : remaining[4 : 0];
    wire [4 : 0] aad_block_bytes = aad_remaining >= 16 ? 5'd16 : aad_remaining[4 : 0];
    wire [127 : 0] mask = byte_mask(block_bytes);
    wire [127 : 0] length_block = {55'b0, aad_length, 3'b0, 48'b0, payload_length, 3'b0};
    wire hash_start = phase == AAD_START || phase == HASH_START || phase == LEN_START;
    wire hash_busy, hash_done;
    wire [127 : 0] hash_product;
    // The held GHASH result is consumed on the next start edge, before that
    // edge initializes its next accumulation. Avoid another128-bit snapshot.
    wire [127 : 0] hash_input =
                       hash_product ^
                       (phase == AAD_START    ? (aad_copy[255 : 128] & byte_mask(aad_block_bytes))
                        : phase == HASH_START ? cipher_block
                                              : length_block);
    x32_ghash authentication(clk,
                             reset,
                             clear || phase == KEY_CLEAR,
                             hash_start,
                             hash_input,
                             h,
                             hash_busy,
                             hash_done,
                             hash_product);
    assign busy = phase != IDLE || aes_busy;
    assign read_valid = phase == READ;
    assign read_index = block_index;
    assign write_valid = phase == WRITE;
    assign write_index = block_index;
    assign write_data = output_block;
    always @(posedge clk)
    begin
        if (reset || clear)
        begin
            phase <= IDLE;
            done <= 0;
            auth_ok <= 0;
            tag <= 0;
            mode_decrypt <= 0;
            aad_copy <= 0;
            nonce_copy <= 0;
            aad_length <= 0;
            aad_remaining <= 0;
            payload_length <= 0;
            remaining <= 0;
            block_index <= 0;
            counter <= 0;
            h <= 0;
            tag_mask <= 0;
            output_block <= 0;
            cipher_block <= 0;
            tag_copy <= 0;
        end
        else
        begin
            done <= 0;
            case (phase)
                IDLE:
                    if (begin_packet)
                    begin
                        mode_decrypt <= decrypt;
                        aad_copy <= aad;
                        nonce_copy <= nonce;
                        aad_length <= aad_bytes;
                        aad_remaining <= aad_bytes;
                        payload_length <= payload_bytes;
                        remaining <= payload_bytes;
                        block_index <= 0;
                        counter <= 2;
                        h <= 0;
                        tag_mask <= 0;
                        tag_copy <= expected_tag;
                        output_block <= 0;
                        cipher_block <= 0;
                        tag <= 0;
                        auth_ok <= 0;
                        phase <= KEY_WAIT;
                    end
                KEY_WAIT:
                    if (!aes_busy && aes_key_ready)
                        phase <= H_START;
                H_START:
                    phase <= H_WAIT;
                H_WAIT:
                    if (aes_done)
                    begin
                        h <= aes_result;
                        phase <= J_START;
                    end
                J_START:
                    phase <= J_WAIT;
                J_WAIT:
                    if (aes_done)
                    begin
                        tag_mask <= aes_result;
                        phase <= aad_remaining ? AAD_START : remaining ? READ : LEN_START;
                    end
                AAD_START:
                    phase <= AAD_WAIT;
                AAD_WAIT:
                    if (hash_done)
                    begin
                        aad_copy <= {aad_copy[127 : 0], 128'b0};
                        if (aad_remaining > 16)
                        begin
                            aad_remaining <= aad_remaining - 6'd16;
                            phase <= AAD_START;
                        end
                        else
                        begin
                            aad_remaining <= 0;
                            phase <= remaining ? READ : LEN_START;
                        end
                    end
                READ:
                    if (read_ready)
                    begin
                        cipher_block <= read_data & mask;
                        phase <= CTR_START;
                    end
                CTR_START:
                    phase <= CTR_WAIT;
                CTR_WAIT:
                    if (aes_done)
                    begin
                        output_block <= (cipher_block ^ aes_result) & mask;
                        if (!mode_decrypt)
                            cipher_block <= (cipher_block ^ aes_result) & mask;
                        phase <= HASH_START;
                    end
                HASH_START:
                    phase <= HASH_WAIT;
                HASH_WAIT:
                    if (hash_done)
                    begin
                        cipher_block <= 0;
                        phase <= WRITE;
                    end
                WRITE:
                    if (write_ready)
                    begin
                        output_block <= 0;
                        block_index <= block_index + 1'b1;
                        counter <= counter + 1'b1;
                        if (remaining > 16)
                        begin
                            remaining <= remaining - 13'd16;
                            phase <= READ;
                        end
                        else
                        begin
                            remaining <= 0;
                            phase <= LEN_START;
                        end
                    end
                LEN_START:
                    phase <= LEN_WAIT;
                LEN_WAIT:
                    if (hash_done)
                        phase <= FINISH;
                FINISH: begin
                    tag <= tag_mask ^ hash_product;
                    auth_ok <= !mode_decrypt || ((tag_mask ^ hash_product ^ tag_copy) == 128'b0);
                    h <= 0;
                    tag_mask <= 0;
                    tag_copy <= 0;
                    aad_copy <= 0;
                    nonce_copy <= 0;
                    output_block <= 0;
                    cipher_block <= 0;
                    phase <= KEY_CLEAR;
                end
                KEY_CLEAR:
                    phase <= KEY_CLEAR_WAIT;
                KEY_CLEAR_WAIT:
                    if (!aes_busy)
                    begin
                        done <= 1;
                        phase <= IDLE;
                    end
                default: begin
                    phase <= KEY_CLEAR;
                    auth_ok <= 0;
                    tag <= 0;
                end
            endcase
        end
    end
    wire unused_hash_busy = hash_busy;
endmodule
