// X25519, Edwards25519 base multiply and double-scalar verification.
// Execute arithmetic and secret-dependent swaps in SYS30 for each CPU command.
// Verify returns encode([s]B - [h]A). The caller hashes, reduces and compares.
module x32_curve_core
    (input wire clk, reset, clear, start,
     input wire [1 : 0] command,
     output wire busy,
     output reg done, valid,
     output reg [31 : 0] cycles,
     input wire host_write,
     input wire [9 : 0] host_address,
     input wire [15 : 0] host_data,
     output wire [15 : 0] host_read);
    localparam INITIAL = 0, IDLE = 1, FETCH = 2, DECODE = 3, WAIT_FIELD = 4, META_READ = 5,
               META_CAPTURE = 6, META_WRITE = 7;
    reg [2 : 0] state;
    reg [8 : 0] pc;
    wire [31 : 0] instruction;
    wire [3 : 0] opcode = instruction[31 : 28];
    wire [5 : 0] dst = instruction[27 : 22], sa = instruction[21 : 16], sb = instruction[15 : 10];
    wire [9 : 0] immediate = instruction[9 : 0];
    reg [8 : 0] returns[0 : 3];
    reg [2 : 0] depth;
    reg [7 : 0] bit_index;
    reg [5 : 0] scalar_source;
    reg [1 : 0] mode;
    reg condition, equality, parity, encoded_sign;
    reg [3 : 0] meta_opcode;
    reg [9 : 0] meta_kind;
    reg [9 : 0] meta_address;
    reg [15 : 0] meta_data;
    wire f_busy, f_done, f_equal;
    wire [15 : 0] f_read;
    wire f_start = state == DECODE && opcode >= 1 && opcode <= 5;
    wire meta_access = state == META_READ || state == META_CAPTURE || state == META_WRITE;
    wire [9 : 0] f_address = meta_access ? meta_address : host_address;
    wire f_write = state == META_WRITE || (state == IDLE && host_write);
    wire [15 : 0] f_data = state == META_WRITE ? meta_data : host_data;
    x32_curve_field field(clk,
                          reset,
                          clear,
                          f_start,
                          opcode[2 : 0],
                          dst,
                          sa,
                          sb,
                          condition,
                          f_busy,
                          f_done,
                          f_equal,
                          f_write,
                          f_address,
                          f_data,
                          f_read);
    x32_curve_program program_rom(clk,
                                  pc,
                                  instruction);
    assign host_read = f_read;
    assign busy = state != IDLE || f_busy;
    wire branch = dst == 0 || (dst == 1 && equality) || (dst == 2 && !equality) ||
                  (dst == 3 && parity == encoded_sign) || (dst == 4 && !condition);
    always @(posedge clk)
    begin
        if (reset || clear)
        begin
            state <= INITIAL;
            pc <= 0;
            depth <= 0;
            bit_index <= 0;
            scalar_source <= 0;
            mode <= 0;
            condition <= 0;
            equality <= 0;
            parity <= 0;
            encoded_sign <= 0;
            meta_opcode <= 0;
            meta_kind <= 0;
            meta_address <= 0;
            meta_data <= 0;
            done <= 0;
            valid <= 0;
            cycles <= 0;
            returns[0] <= 0;
            returns[1] <= 0;
            returns[2] <= 0;
            returns[3] <= 0;
        end
        else
        begin
            if (state != IDLE && state != INITIAL)
                cycles <= cycles + 1'b1;
            case (state)
                INITIAL:
                    if (!f_busy)
                        state <= IDLE;
                IDLE:
                    if (start)
                    begin
                        mode <= command;
                        pc <= command == 1 ? 9'd0 : command == 2 ? 9'd1 : 9'd2;
                        state <= FETCH;
                        done <= 0;
                        valid <= 0;
                        cycles <= 0;
                        depth <= 0;
                    end
                FETCH:
                    state <= DECODE;
                DECODE: begin
                    pc <= pc + 1'b1;
                    state <= FETCH;
                    if (opcode >= 1 && opcode <= 5)
                        state <= WAIT_FIELD;
                    else
                        case (opcode)
                            6: begin
                                meta_opcode <= 6;
                                meta_kind <= 0;
                                meta_address <= {sa == 0 ? scalar_source : sa, bit_index[7 : 4]};
                                state <= META_READ;
                            end
                            7:
                                bit_index <= immediate[7 : 0];
                            8:
                                if (bit_index != 0)
                                begin
                                    bit_index <= bit_index - 1'b1;
                                    pc <= immediate[8 : 0];
                                end
                            9:
                                if (branch)
                                    pc <= immediate[8 : 0];
                            10: begin
                                if (depth >= 4)
                                begin
                                    done <= 1;
                                    valid <= 0;
                                    state <= IDLE;
                                end
                                else
                                begin
                                    returns[depth[1 : 0]] <= pc + 1'b1;
                                    depth <= depth + 1'b1;
                                    pc <= immediate[8 : 0];
                                end
                            end
                            11: begin
                                if (depth == 0)
                                begin
                                    done <= 1;
                                    valid <= 0;
                                    state <= IDLE;
                                end
                                else
                                begin
                                    pc <= returns[depth - 1'b1];
                                    depth <= depth - 1'b1;
                                end
                            end
                            12:
                                condition <= immediate == 0 ? (bit_index != 2 && bit_index != 4)
                                                            : (bit_index != 1);
                            13, 14: begin
                                if (opcode == 14 && immediate == 2)
                                    scalar_source <= sa;
                                else
                                begin
                                    meta_opcode <= opcode;
                                    meta_kind <= immediate;
                                    meta_address <=
                                        {sa, (immediate == 0 && opcode == 13) ? 4'd0 : 4'd15};
                                    state <= META_READ;
                                end
                            end
                            15: begin
                                done <= 1;
                                valid <= immediate == 0;
                                state <= IDLE;
                            end
                            default: begin
                                done <= 1;
                                valid <= 0;
                                state <= IDLE;
                            end
                        endcase
                end
                WAIT_FIELD:
                    if (f_done)
                    begin
                        equality <= f_equal;
                        state <= FETCH;
                    end
                META_READ:
                    state <= META_CAPTURE;
                META_CAPTURE: begin
                    state <= FETCH;
                    if (meta_opcode == 6)
                    begin
                        if (mode == 1 && bit_index >= 254)
                            condition <= 1;
                        else if (mode == 1 && bit_index < 3)
                            condition <= 0;
                        else
                            condition <= f_read[bit_index[3 : 0]];
                    end
                    else if (meta_opcode == 13)
                    begin
                        if (meta_kind == 0)
                            parity <= f_read[0];
                        else
                            encoded_sign <= f_read[15];
                    end
                    else
                    begin
                        meta_data <= {meta_kind == 1 ? parity : 1'b0, f_read[14 : 0]};
                        state <= META_WRITE;
                    end
                end
                META_WRITE: begin
                    meta_data <= 0;
                    state <= FETCH;
                end
                default:
                    state <= INITIAL;
            endcase
        end
    end
endmodule
