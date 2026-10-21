// GCM field multiply: product = x*y in GF(2^128), SP800-38D algorithm1.
// Bit-serial logic multiplier with operand-independent 128-cycle latency.
module x32_ghash
    (input wire clk, reset, clear, start,
     input wire [127 : 0] x, y,
     output reg busy, done,
     output wire [127 : 0] product);
    reg [127 : 0] bits_left, multiplier, accumulator;
    reg [6 : 0] count;
    // Hold product in the accumulation register from done until start or clear.
    assign product = accumulator;
    wire [127 : 0] accumulated = accumulator ^ ({128{bits_left[127]}} & multiplier);
    always @(posedge clk)
    begin
        if (reset || clear)
        begin
            busy <= 0;
            done <= 0;
            bits_left <= 0;
            multiplier <= 0;
            accumulator <= 0;
            count <= 0;
        end
        else
        begin
            done <= 0;
            if (start && !busy)
            begin
                busy <= 1;
                count <= 0;
                bits_left <= x;
                multiplier <= y;
                accumulator <= 0;
            end
            else if (busy)
            begin
                bits_left <= {bits_left[126 : 0], 1'b0};
                multiplier <= {1'b0, multiplier[127 : 1]} ^
                              (128'he1000000000000000000000000000000 & {128{multiplier[0]}});
                accumulator <= accumulated;
                if (count == 127)
                begin
                    done <= 1;
                    busy <= 0;
                    bits_left <= 0;
                    multiplier <= 0;
                end
                else
                    count <= count + 1'b1;
            end
        end
    end
endmodule
