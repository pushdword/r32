// Byte-serial AES encryption for CTR/GCM: AES-128 and AES-256, one S-box.
// Key and block bytes use FIPS197 order, first byte in the most significant
// bits. key128 occupies key_data[255:128]. No inverse cipher is required by
// CTR/GCM. No CPU ISA change, DMA or entropy-generation claim.
module x32_aes_core
    #(parameter WORD_KEYS = 0)
    (input wire clk, reset, clear,
     input wire key_start, key_256,
     input wire [255 : 0] key_data,
     input wire block_start,
     input wire [127 : 0] block_data,
     output wire busy,
     output reg key_ready,
     output reg block_done,
     output reg [127 : 0] block_result,
     input wire key_word_valid,
     input wire [2 : 0] key_word_index,
     input wire [31 : 0] key_word_value);
    localparam WIPE = 0, IDLE = 1, KEY_LOAD = 2, KEY_READ = 3, KEY_SUB = 4, KEY_GEN = 5,
               ADD_WAIT = 6, ADD_WORD = 7, SUB_BYTES = 8, SHIFT_ROWS = 9, MIX_COLUMN = 10,
               KEY_LAST_WAIT = 11, KEY_LAST_CAPTURE = 12;
    reg [3 : 0] phase;
    reg use_256, rotated;
    reg [5 : 0] wipe_index, key_index;
    reg [2 : 0] load_index;
    reg [1 : 0] word_index, sub_index;
    reg [3 : 0] byte_index, round_number;
    reg [7 : 0] rcon;
    reg [255 : 0] incoming_key;
    reg [127 : 0] state;
    reg [31 : 0] previous, temporary, key_word;
    reg [31 : 0] round_keys[0 : 63];
    wire [3 : 0] rounds = use_256 ? 4'd14 : 4'd10;
    wire [5 : 0] words = use_256 ? 6'd60 : 6'd44;
    wire [5 : 0] nk = use_256 ? 6'd8 : 6'd4;
    wire rotate_word = use_256 ? (key_index[2 : 0] == 0) : (key_index[1 : 0] == 0);
    wire extra_sub = use_256 && key_index[2 : 0] == 4;
    wire [7 : 0] substitution_input = phase == KEY_SUB ? temporary[31 : 24] : state[127 : 120];
    wire [7 : 0] substitution;
    x32_aes_sbox substitution_table(substitution_input,
                                    substitution);
    function automatic[7 : 0] xtime
        (input [7 : 0] a);
        xtime = {a[6 : 0], 1'b0} ^ (a[7] ? 8'h1b : 8'h00);
    endfunction
    function automatic[31 : 0] mix
        (input [31 : 0] column);
        reg [7 : 0] a, b, c, d, t;
        begin
            a = column[31 : 24];
            b = column[23 : 16];
            c = column[15 : 8];
            d = column[7 : 0];
            t = a ^ b ^ c ^ d;
            mix = {a ^ t ^ xtime(a ^ b), b ^ t ^ xtime(b ^ c), c ^ t ^ xtime(c ^ d),
                   d ^ t ^ xtime(d ^ a)};
        end
    endfunction
    wire [127 : 0] shifted;
    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1)
        begin : row_permutation
            localparam integer SOURCE = 4 * (((i / 4) + (i % 4)) % 4) + (i % 4);
            assign shifted[127 - i * 8 -: 8] = state[127 - SOURCE * 8 -: 8];
        end
    endgenerate
    wire [5 : 0] read_index = (phase == ADD_WAIT || phase == ADD_WORD)
                                  ? ({round_number, 2'b00} + {4'b0, word_index})
                              : (phase == KEY_LAST_WAIT || phase == KEY_LAST_CAPTURE)
                                  ? nk - 1'b1
                                  : (key_index - nk);
    wire [31 : 0] expanded = key_word ^ temporary ^ (rotated ? {rcon, 24'b0} : 32'b0);
    wire word_key_write = WORD_KEYS && key_word_valid && phase == IDLE && !reset && !clear;
    wire key_write = phase == WIPE || word_key_write ||
                     (!reset && !clear && (phase == KEY_LOAD || phase == KEY_GEN));
    wire [5 : 0] key_write_index = phase == WIPE       ? wipe_index
                                   : word_key_write    ? {3'b0, key_word_index}
                                   : phase == KEY_LOAD ? {3'b0, load_index}
                                                       : key_index;
    wire [31 : 0] key_write_data = phase == WIPE       ? 32'b0
                                   : word_key_write    ? key_word_value
                                   : phase == KEY_LOAD ? incoming_key[255 : 224]
                                                       : expanded;
    // Key RAM has one synchronous read port and one write port.
    // Reset/clear overwrites all entries in 64 cycles before IDLE.
    always @(posedge clk)
    begin
        if (reset || clear)
            key_word <= 0;
        else
            key_word <= round_keys[read_index];
        if (key_write)
            round_keys[key_write_index] <= key_write_data;
    end
    assign busy = phase != IDLE;
    always @(posedge clk)
    begin
        if (reset || clear)
        begin
            phase <= WIPE;
            wipe_index <= 0;
            key_index <= 0;
            load_index <= 0;
            word_index <= 0;
            sub_index <= 0;
            byte_index <= 0;
            round_number <= 0;
            rcon <= 0;
            use_256 <= 0;
            rotated <= 0;
            incoming_key <= 0;
            state <= 0;
            previous <= 0;
            temporary <= 0;
            key_ready <= 0;
            block_done <= 0;
            block_result <= 0;
        end
        else
        begin
            block_done <= 0;
            case (phase)
                WIPE: begin
                    if (wipe_index == 63)
                        phase <= IDLE;
                    else
                        wipe_index <= wipe_index + 1'b1;
                end
                IDLE: begin
                    if (word_key_write)
                    begin
                        key_ready <= 0;
                        block_result <= 0;
                    end
                    if (key_start)
                    begin
                        incoming_key <= WORD_KEYS ? 256'b0 : key_data;
                        use_256 <= key_256;
                        load_index <= 0;
                        key_ready <= 0;
                        block_result <= 0;
                        phase <= WORD_KEYS ? KEY_LAST_WAIT : KEY_LOAD;
                    end
                    else if (block_start && key_ready && !word_key_write)
                    begin
                        state <= block_data;
                        round_number <= 0;
                        word_index <= 0;
                        phase <= ADD_WAIT;
                    end
                end
                KEY_LAST_WAIT:
                    phase <= KEY_LAST_CAPTURE;
                KEY_LAST_CAPTURE: begin
                    previous <= key_word;
                    key_index <= nk;
                    rcon <= 1;
                    phase <= KEY_READ;
                end
                KEY_LOAD: begin
                    previous <= incoming_key[255 : 224];
                    incoming_key <= {incoming_key[223 : 0], 32'b0};
                    if (load_index == (use_256 ? 7 : 3))
                    begin
                        key_index <= nk;
                        rcon <= 1;
                        phase <= KEY_READ;
                    end
                    else
                        load_index <= load_index + 1'b1;
                end
                KEY_READ: begin
                    rotated <= rotate_word;
                    sub_index <= 0;
                    temporary <= rotate_word ? {previous[23 : 0], previous[31 : 24]} : previous;
                    phase <= (rotate_word || extra_sub) ? KEY_SUB : KEY_GEN;
                end
                KEY_SUB: begin
                    temporary <= {temporary[23 : 0], substitution};
                    if (sub_index == 3)
                        phase <= KEY_GEN;
                    else
                        sub_index <= sub_index + 1'b1;
                end
                KEY_GEN: begin
                    previous <= expanded;
                    if (rotated)
                        rcon <= xtime(rcon);
                    if (key_index == words - 1'b1)
                    begin
                        phase <= IDLE;
                        key_ready <= 1;
                        previous <= 0;
                        temporary <= 0;
                        incoming_key <= 0;
                    end
                    else
                    begin
                        key_index <= key_index + 1'b1;
                        phase <= KEY_READ;
                    end
                end
                ADD_WAIT:
                    phase <= ADD_WORD;
                ADD_WORD: begin
                    state <= {state[95 : 0], state[127 : 96] ^ key_word};
                    if (word_index == 3)
                    begin
                        word_index <= 0;
                        if (round_number == rounds)
                        begin
                            block_result <= {state[95 : 0], state[127 : 96] ^ key_word};
                            block_done <= 1;
                            state <= 0;
                            phase <= IDLE;
                        end
                        else
                        begin
                            round_number <= round_number + 1'b1;
                            byte_index <= 0;
                            phase <= SUB_BYTES;
                        end
                    end
                    else
                    begin
                        word_index <= word_index + 1'b1;
                        phase <= ADD_WAIT;
                    end
                end
                SUB_BYTES: begin
                    state <= {state[119 : 0], substitution};
                    if (byte_index == 15)
                        phase <= SHIFT_ROWS;
                    else
                        byte_index <= byte_index + 1'b1;
                end
                SHIFT_ROWS: begin
                    state <= shifted;
                    word_index <= 0;
                    phase <= round_number == rounds ? ADD_WAIT : MIX_COLUMN;
                end
                MIX_COLUMN: begin
                    state <= {state[95 : 0], mix(state[127 : 96])};
                    if (word_index == 3)
                    begin
                        word_index <= 0;
                        phase <= ADD_WAIT;
                    end
                    else
                        word_index <= word_index + 1'b1;
                end
                default: begin
                    phase <= WIPE;
                    wipe_index <= 0;
                    key_ready <= 0;
                    state <= 0;
                    block_result <= 0;
                end
            endcase
        end
    end
endmodule
