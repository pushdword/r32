// SPDX-License-Identifier: MIT
// Fixed registered partial-product multiply and 32-step restoring divide.
// Keep the partial-product registers outside DSP absorption: native packing
// must preserve the start/result latency and independent register enables.
module r32_muldiv
    (input wire clk, reset, start,
     input wire [5 : 0] operation,
     input wire [31 : 0] a, b,
     output reg busy, done,
     output reg [31 : 0] result);
    reg [5 : 0] op, count;
    reg [31 : 0] original, q, divisor;
    reg [32 : 0] remainder, trial;
    reg [31 : 0] next_q;
    reg sign_q, sign_r, neg_a, neg_b;
    (* syn_preserve = 1 *) reg [31 : 0] p0, p1, p2, p3;
    reg [31 : 0] saved_a, saved_b;
    reg [63 : 0] product;
    always @*
    begin
        trial = {remainder[31 : 0], q[31]};
        next_q = {q[30 : 0], 1'b0};
        if (trial >= {1'b0, divisor})
        begin
            trial = trial - {1'b0, divisor};
            next_q[0] = 1;
        end
        product = {32'b0, p0} + ({32'b0, p1} << 16) + ({32'b0, p2} << 16) + ({32'b0, p3} << 32);
        if (op == 11)
        begin
            if (neg_a)
                product = product - ({32'b0, saved_b} << 32);
            if (neg_b)
                product = product - ({32'b0, saved_a} << 32);
        end
    end
    always @(posedge clk)
    begin
        if (reset)
        begin
            busy <= 0;
            done <= 0;
            result <= 0;
            count <= 0;
            op <= 0;
            original <= 0;
            q <= 0;
            divisor <= 0;
            remainder <= 0;
            sign_q <= 0;
            sign_r <= 0;
            neg_a <= 0;
            neg_b <= 0;
            p0 <= 0;
            p1 <= 0;
            p2 <= 0;
            p3 <= 0;
            saved_a <= 0;
            saved_b <= 0;
        end
        else
        begin
            done <= 0;
            if (start && !busy)
            begin
                op <= operation;
                busy <= 1;
                count <= 0;
                original <= a;
                saved_a <= a;
                saved_b <= b;
                neg_a <= a[31];
                neg_b <= b[31];
                if (operation <= 12)
                begin
                    p0 <= a[15 : 0] * b[15 : 0];
                    p1 <= a[31 : 16] * b[15 : 0];
                    p2 <= a[15 : 0] * b[31 : 16];
                    p3 <= a[31 : 16] * b[31 : 16];
                end
                else
                begin
                    sign_q <= (operation == 13 || operation == 15) && (a[31] ^ b[31]);
                    sign_r <= (operation == 13 || operation == 15) && a[31];
                    q <= ((operation == 13 || operation == 15) && a[31]) ? (~a + 1'b1) : a;
                    divisor <= ((operation == 13 || operation == 15) && b[31]) ? (~b + 1'b1) : b;
                    remainder <= 0;
                end
            end
            else if (busy)
            begin
                if (op <= 12)
                begin
                    result <= op == 10 ? product[31 : 0] : product[63 : 32];
                    busy <= 0;
                    done <= 1;
                end
                else if (divisor == 0)
                begin
                    result <= op <= 14 ? 32'hffffffff : original;
                    busy <= 0;
                    done <= 1;
                end
                else
                begin
                    q <= next_q;
                    remainder <= trial;
                    count <= count + 1'b1;
                    if (count == 31)
                    begin
                        result <= op <= 14 ? (sign_q ? (~next_q + 1'b1) : next_q)
                                           : (sign_r ? (~trial[31 : 0] + 1'b1) : trial[31 : 0]);
                        busy <= 0;
                        done <= 1;
                    end
                end
            end
        end
    end
endmodule
