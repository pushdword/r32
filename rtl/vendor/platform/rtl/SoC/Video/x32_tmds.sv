// DVI-compatible TMDS: 8-bit transition minimization, then running-disparity
// balancing. Blue carries H/V sync during blanking; red/green use control=0.
module x32_tmds
    (input wire clk, reset, de,
     input wire [7 : 0] data,
     input wire [1 : 0] control,
     output reg [9 : 0] symbol);
    reg signed [5 : 0] disparity;
    reg [8 : 0] q;
    integer ones_data, ones_q, balance;
    reg use_xnor;
    always_comb
    begin
        ones_data = 0;
        ones_q = 0;
        for (integer i = 0; i < 8; i = i + 1)
            ones_data = ones_data + int'(data[i]);
        use_xnor = ones_data > 4 || (ones_data == 4 && !data[0]);
        q[0] = data[0];
        q[8] = !use_xnor;
        for (integer i = 1; i < 8; i = i + 1)
            q[i] = use_xnor ? ~(q[i - 1] ^ data[i]) : q[i - 1] ^ data[i];
        for (integer i = 0; i < 8; i = i + 1)
            ones_q = ones_q + int'(q[i]);
        balance = ones_q * 2 - 8;
    end
    always @(posedge clk)
    begin
        if (reset)
        begin
            symbol <= 10'b1101010100;
            disparity <= 0;
        end
        else if (!de)
        begin
            disparity <= 0;
            case (control)
                0:
                    symbol <= 10'b1101010100;
                1:
                    symbol <= 10'b0010101011;
                2:
                    symbol <= 10'b0101010100;
                3:
                    symbol <= 10'b1010101011;
            endcase
        end
        else if (disparity == 0 || balance == 0)
        begin
            symbol <= {!q[8], q[8], q[8] ? q[7 : 0] : ~q[7 : 0]};
            disparity <= 6'(int'(disparity) + (q[8] ? balance : -balance));
        end
        else if ((disparity > 0 && balance > 0) || (disparity < 0 && balance < 0))
        begin
            symbol <= {1'b1, q[8], ~q[7 : 0]};
            disparity <= 6'(int'(disparity) + int'(q[8]) * 2 - balance);
        end
        else
        begin
            symbol <= {1'b0, q[8], q[7 : 0]};
            disparity <= 6'(int'(disparity) - int'(!q[8]) * 2 + balance);
        end
    end
endmodule
