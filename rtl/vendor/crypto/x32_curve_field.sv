// Shared radix-2^16 arithmetic modulo 2^255-19. One 16x16 multiplier,
// synchronous field RAM (64*16 limbs), and column-wise product accumulation.
// Operands are canonical. MUL/ADD/SUB/CSWAP/EQUAL have data-independent cycles.
// Enable the external limb port only while idle. Reset/clear wipes secret
// field and scratch RAM before ready. Public constants occupy r0..r7.
module x32_curve_field
    (input wire clk, reset, clear, start,
     input wire [2 : 0] operation,
     input wire [5 : 0] destination, source_a, source_b,
     input wire swap,
     output wire busy,
     output reg done, equal,
     input wire external_write,
     input wire [9 : 0] external_address,
     input wire [15 : 0] external_data,
     output reg [15 : 0] external_read);
    localparam WIPE = 0, IDLE = 1, READ_A = 2, CAPTURE_A = 3, READ_B = 4, CAPTURE_B = 5, SIMPLE = 6,
               SIMPLE_WRITE = 7, SWAP_SECOND = 8, MULTIPLY = 9, ACCUMULATE = 10, PRODUCT_WRITE = 11,
               HIGH_CLEAR = 12, SUB_READ = 13, SUB_CAPTURE = 14, SUB_CORRECT = 15, FOLD_HIGH = 16,
               FOLD_HIGH_CAPTURE = 17, FOLD_LOW = 18, FOLD_LOW_CAPTURE = 19, FOLD_WRITE = 20,
               CARRY_READ = 21, CARRY_CAPTURE = 22, CARRY_WRITE = 23, TRIAL_READ = 24,
               TRIAL_CAPTURE = 25, TRIAL_WRITE = 26, COPY_READ = 27, COPY_CAPTURE = 28,
               COPY_WRITE = 29, COMPLETE = 30;
    reg [4 : 0] state;
    (* syn_ramstyle = "block_ram" *) reg [15 : 0] fields[0 : 1023];
    reg [15 : 0] scratch[0 : 47];
    reg [9 : 0] f_address, f_write_address, wipe_index;
    reg [5 : 0] s_address, s_write_address;
    reg [15 : 0] f_data, s_data, f_write_data, s_write_data;
    reg f_write, s_write;
    reg [2 : 0] op;
    reg [5 : 0] dst, sa, sb;
    reg selected, borrow, correct_sub, trial_borrow, unequal;
    reg [3 : 0] limb, pair;
    reg [4 : 0] column;
    reg [1 : 0] fold_round;
    reg [15 : 0] av, bv, high_limb;
    reg [31 : 0] product;
    reg [39 : 0] accumulator;
    reg [23 : 0] carry;
    reg [16 : 0] simple_result;
    reg [23 : 0] reduction_result;
    function automatic[15 : 0] prime_word
        (input [3 : 0] i);
        prime_word = i == 0 ? 16'hffed : i == 15 ? 16'h7fff : 16'hffff;
    endfunction
    function automatic[15 : 0] initial_word
        (input [9 : 0] address);
        reg [255 : 0] value;
        begin
            case (address[9 : 4])
                1:
                    value = 256'd1;
                2:
                    value = 256'd121665;
                3:
                    value = 256'h52036cee2b6ffe738cc740797779e89800700a4d4141d8ab75eb4dca135978a3;
                4:
                    value = 256'h2406d9dc56dffce7198e80f2eef3d13000e0149a8283b156ebd69b9426b2f159;
                5:
                    value = 256'h2b8324804fc1df0b2b4d00993dfbd7a72f431806ad2fe478c4ee1b274a0ea0b0;
                6:
                    value = 256'h216936d3cd6e53fec0a4e231fdd6dc5c692cc7609525a7b2c9562d608f25d51a;
                7:
                    value = 256'h6666666666666666666666666666666666666666666666666666666666666658;
                default:
                    value = 0;
            endcase
            initial_word = value[address[3 : 0] * 16 +: 16];
        end
    endfunction
    assign busy = state != IDLE;
    always @*
    begin
        simple_result = 0;
        if (op == 1)
            simple_result = {1'b0, av} + {1'b0, bv} + carry[0];
        else if (op == 2)
            simple_result = {1'b0, av} - {1'b0, bv} - {16'b0, borrow};
        reduction_result = 0;
        case (state)
            SUB_CORRECT:
                reduction_result = {8'b0, s_data} +
                                   (correct_sub ? {8'b0, prime_word(limb)} : 24'b0) + carry;
            FOLD_WRITE:
                reduction_result = {8'b0, s_data} + ({8'b0, high_limb} * 24'd38) + carry;
            CARRY_WRITE:
                reduction_result = {8'b0, s_data} + carry;
            TRIAL_WRITE:
                reduction_result = {8'b0, s_data} - {8'b0, prime_word(limb)} -
                                   {23'b0, trial_borrow};
            default:
                reduction_result = 0;
        endcase
        f_address = external_address;
        f_write = 0;
        f_write_address = external_address;
        f_write_data = external_data;
        s_address = {2'b0, limb};
        s_write = 0;
        s_write_address = {2'b0, limb};
        s_write_data = 0;
        case (state)
            WIPE: begin
                f_write = 1;
                f_write_address = wipe_index;
                f_write_data = initial_word(wipe_index);
                if (wipe_index < 48)
                begin
                    s_write = 1;
                    s_write_address = wipe_index[5 : 0];
                end
            end
            IDLE: begin
                f_write = external_write;
            end
            READ_A:
                f_address = {sa, op == 3 ? pair : limb};
            READ_B:
                f_address = {sb, op == 3 ? column[3 : 0] - pair : limb};
            SIMPLE_WRITE: begin
                if (op <= 2)
                begin
                    s_write = 1;
                    s_write_data = simple_result[15 : 0];
                end
                else if (op == 4)
                begin
                    f_write = 1;
                    f_write_address = {sa, limb};
                    f_write_data = selected ? bv : av;
                end
            end
            SWAP_SECOND: begin
                f_write = 1;
                f_write_address = {sb, limb};
                f_write_data = selected ? av : bv;
            end
            PRODUCT_WRITE: begin
                s_write = 1;
                s_write_address = {1'b0, column};
                s_write_data = accumulator[15 : 0];
            end
            HIGH_CLEAR: begin
                s_write = 1;
                s_write_address = {1'b0, column};
                s_write_data = column == 16 ? {15'b0, carry[0]} : 16'b0;
            end
            SUB_READ:
                s_address = {2'b0, limb};
            SUB_CORRECT: begin
                s_write = 1;
                s_write_data = reduction_result[15 : 0];
            end
            FOLD_HIGH:
                s_address = 6'd16 + {2'b0, limb};
            FOLD_LOW:
                s_address = {2'b0, limb};
            FOLD_WRITE: begin
                s_write = 1;
                s_write_data =
                    limb == 15 ? {1'b0, reduction_result[14 : 0]} : reduction_result[15 : 0];
            end
            CARRY_READ:
                s_address = {2'b0, limb};
            CARRY_WRITE: begin
                s_write = 1;
                s_write_data =
                    limb == 15 ? {1'b0, reduction_result[14 : 0]} : reduction_result[15 : 0];
            end
            TRIAL_READ:
                s_address = {2'b0, limb};
            TRIAL_WRITE: begin
                s_write = 1;
                s_write_address = 6'd32 + {2'b0, limb};
                s_write_data = reduction_result[15 : 0];
            end
            COPY_READ, COPY_CAPTURE, COPY_WRITE: begin
                s_address = (trial_borrow ? 6'd0 : 6'd32) + {2'b0, limb};
                if (state == COPY_WRITE)
                begin
                    f_write = 1;
                    f_write_address = {dst, limb};
                    f_write_data = s_data;
                end
            end
            default: begin
            end
        endcase
    end
    always @(posedge clk)
    begin
        f_data <= fields[f_address];
        external_read <= fields[external_address];
        s_data <= scratch[s_address];
        if (f_write)
            fields[f_write_address] <= f_write_data;
        if (s_write)
            scratch[s_write_address] <= s_write_data;
    end
    always @(posedge clk)
    begin
        if (reset || clear)
        begin
            state <= WIPE;
            wipe_index <= 0;
            done <= 0;
            equal <= 0;
            op <= 0;
            dst <= 0;
            sa <= 0;
            sb <= 0;
            selected <= 0;
            borrow <= 0;
            correct_sub <= 0;
            trial_borrow <= 0;
            unequal <= 0;
            limb <= 0;
            pair <= 0;
            column <= 0;
            fold_round <= 0;
            av <= 0;
            bv <= 0;
            high_limb <= 0;
            product <= 0;
            accumulator <= 0;
            carry <= 0;
        end
        else
        begin
            done <= 0;
            case (state)
                WIPE:
                    if (wipe_index == 1023)
                        state <= IDLE;
                    else
                        wipe_index <= wipe_index + 1'b1;
                IDLE:
                    if (start)
                    begin
                        op <= operation;
                        dst <= destination;
                        sa <= source_a;
                        sb <= source_b;
                        selected <= swap;
                        limb <= 0;
                        pair <= 0;
                        column <= 0;
                        accumulator <= 0;
                        carry <= 0;
                        borrow <= 0;
                        unequal <= 0;
                        equal <= 0;
                        state <= READ_A;
                    end
                READ_A:
                    state <= CAPTURE_A;
                CAPTURE_A: begin
                    av <= f_data;
                    state <= READ_B;
                end
                READ_B:
                    state <= CAPTURE_B;
                CAPTURE_B: begin
                    bv <= f_data;
                    state <= op == 3 ? MULTIPLY : SIMPLE;
                end
                MULTIPLY: begin
                    product <= av * bv;
                    state <= ACCUMULATE;
                end
                ACCUMULATE: begin
                    accumulator <= accumulator + {8'b0, product};
                    if (pair == (column < 16 ? column[3 : 0] : 4'd15))
                        state <= PRODUCT_WRITE;
                    else
                    begin
                        pair <= pair + 1'b1;
                        state <= READ_A;
                    end
                end
                PRODUCT_WRITE: begin
                    accumulator <= accumulator >> 16;
                    if (column == 31)
                    begin
                        limb <= 0;
                        carry <= 0;
                        state <= FOLD_HIGH;
                    end
                    else if (column == 30)
                    begin
                        column <= 31;
                    end
                    else
                    begin
                        column <= column + 1'b1;
                        pair <= column < 15 ? 4'd0 : column[3 : 0] + 2;
                        state <= READ_A;
                    end
                end
                SIMPLE:
                    state <= SIMPLE_WRITE;
                SIMPLE_WRITE: begin
                    if (op == 1)
                        carry <= {23'b0, simple_result[16]};
                    if (op == 2)
                        borrow <= simple_result[16];
                    if (op == 5)
                        unequal <= unequal || (av != bv);
                    if (op == 4)
                        state <= SWAP_SECOND;
                    else if (limb != 15)
                    begin
                        limb <= limb + 1'b1;
                        state <= READ_A;
                    end
                    else if (op == 1)
                    begin
                        column <= 16;
                        state <= HIGH_CLEAR;
                    end
                    else if (op == 2)
                    begin
                        correct_sub <= simple_result[16];
                        limb <= 0;
                        carry <= 0;
                        state <= SUB_READ;
                    end
                    else
                        state <= COMPLETE;
                end
                SWAP_SECOND:
                    if (limb == 15)
                        state <= COMPLETE;
                    else
                    begin
                        limb <= limb + 1'b1;
                        state <= READ_A;
                    end
                HIGH_CLEAR:
                    if (column == 31)
                    begin
                        limb <= 0;
                        carry <= 0;
                        state <= FOLD_HIGH;
                    end
                    else
                        column <= column + 1'b1;
                SUB_READ:
                    state <= SUB_CAPTURE;
                SUB_CAPTURE:
                    state <= SUB_CORRECT;
                SUB_CORRECT: begin
                    carry <= reduction_result >> 16;
                    if (limb == 15)
                    begin
                        carry <= 0;
                        column <= 16;
                        state <= HIGH_CLEAR;
                    end
                    else
                    begin
                        limb <= limb + 1'b1;
                        state <= SUB_READ;
                    end
                end
                FOLD_HIGH:
                    state <= FOLD_HIGH_CAPTURE;
                FOLD_HIGH_CAPTURE: begin
                    high_limb <= s_data;
                    state <= FOLD_LOW;
                end
                FOLD_LOW:
                    state <= FOLD_LOW_CAPTURE;
                FOLD_LOW_CAPTURE:
                    state <= FOLD_WRITE;
                FOLD_WRITE: begin
                    if (limb == 15)
                    begin
                        carry <= reduction_result >> 15;
                        limb <= 0;
                        fold_round <= 0;
                        state <= CARRY_READ;
                    end
                    else
                    begin
                        carry <= reduction_result >> 16;
                        limb <= limb + 1'b1;
                        state <= FOLD_HIGH;
                    end
                end
                CARRY_READ: begin
                    if (limb == 0)
                        carry <= carry * 24'd19;
                    state <= CARRY_CAPTURE;
                end
                CARRY_CAPTURE:
                    state <= CARRY_WRITE;
                CARRY_WRITE: begin
                    if (limb == 15)
                    begin
                        limb <= 0;
                        carry <= reduction_result >> 15;
                        if (fold_round == 1)
                        begin
                            trial_borrow <= 0;
                            state <= TRIAL_READ;
                        end
                        else
                        begin
                            fold_round <= fold_round + 1'b1;
                            state <= CARRY_READ;
                        end
                    end
                    else
                    begin
                        carry <= reduction_result >> 16;
                        limb <= limb + 1'b1;
                        state <= CARRY_READ;
                    end
                end
                TRIAL_READ:
                    state <= TRIAL_CAPTURE;
                TRIAL_CAPTURE:
                    state <= TRIAL_WRITE;
                TRIAL_WRITE: begin
                    trial_borrow <= reduction_result[23];
                    if (limb == 15)
                    begin
                        limb <= 0;
                        state <= COPY_READ;
                    end
                    else
                    begin
                        limb <= limb + 1'b1;
                        state <= TRIAL_READ;
                    end
                end
                COPY_READ:
                    state <= COPY_CAPTURE;
                COPY_CAPTURE:
                    state <= COPY_WRITE;
                COPY_WRITE:
                    if (limb == 15)
                        state <= COMPLETE;
                    else
                    begin
                        limb <= limb + 1'b1;
                        state <= COPY_READ;
                    end
                COMPLETE: begin
                    done <= 1;
                    equal <= !unequal;
                    state <= IDLE;
                    av <= 0;
                    bv <= 0;
                    high_limb <= 0;
                    product <= 0;
                    accumulator <= 0;
                    carry <= 0;
                end
                default: begin
                    state <= WIPE;
                    wipe_index <= 0;
                end
            endcase
        end
    end
endmodule
