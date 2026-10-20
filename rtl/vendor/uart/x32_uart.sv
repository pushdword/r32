// 8N1 UART, one-byte RX holding register. No clock generated in fabric.
// RX errors are pulses; the bus adapter holds sticky overrun/framing status.
module x32_uart
    #(parameter integer CLKS_PER_BIT = 434)
    (input wire clk, reset, rx,
     input wire tx_valid,
     input wire [7 : 0] tx_data,
     output wire tx_ready,
     output wire tx,
     output reg rx_valid,
     output reg [7 : 0] rx_data,
     input wire rx_ready,
     output reg overrun, framing_error);
    localparam integer CW = $clog2(CLKS_PER_BIT + 1);
    reg [CW - 1 : 0] tx_count, rx_count;
    reg [9 : 0] tx_shift;
    reg [3 : 0] tx_left;
    reg rx_meta, rx_sync;
    reg [1 : 0] rx_state;
    reg [2 : 0] rx_bit;
    reg [7 : 0] rx_shift;
    assign tx_ready = tx_left == 0;
    assign tx = tx_left == 0 ? 1'b1 : tx_shift[0];
    always @(posedge clk)
    begin
        if (reset)
        begin
            tx_count <= 0;
            tx_shift <= 10'h3ff;
            tx_left <= 0;
            rx_meta <= 1;
            rx_sync <= 1;
            rx_state <= 0;
            rx_count <= 0;
            rx_bit <= 0;
            rx_shift <= 0;
            rx_valid <= 0;
            rx_data <= 0;
            overrun <= 0;
            framing_error <= 0;
        end
        else
        begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
            overrun <= 0;
            framing_error <= 0;
            if (tx_valid && tx_ready)
            begin
                tx_shift <= {1'b1, tx_data, 1'b0};
                tx_left <= 10;
                tx_count <= CW'(CLKS_PER_BIT - 1);
            end
            else if (tx_left != 0)
            begin
                if (tx_count == 0)
                begin
                    tx_shift <= {1'b1, tx_shift[9 : 1]};
                    tx_left <= tx_left - 1;
                    tx_count <= CW'(CLKS_PER_BIT - 1);
                end
                else
                    tx_count <= tx_count - 1;
            end
            if (rx_ready)
                rx_valid <= 0;
            case (rx_state)
                0:
                    if (!rx_sync)
                    begin
                        rx_state <= 1;
                        rx_count <= CW'(CLKS_PER_BIT / 2 - 1);
                    end
                1:
                    if (rx_count != 0)
                        rx_count <= rx_count - 1;
                    else if (rx_sync)
                        rx_state <= 0;
                    else
                    begin
                        rx_state <= 2;
                        rx_count <= CW'(CLKS_PER_BIT - 1);
                        rx_bit <= 0;
                    end
                2:
                    if (rx_count != 0)
                        rx_count <= rx_count - 1;
                    else
                    begin
                        rx_shift[rx_bit] <= rx_sync;
                        rx_count <= CW'(CLKS_PER_BIT - 1);
                        if (rx_bit == 7)
                            rx_state <= 3;
                        else
                            rx_bit <= rx_bit + 1;
                    end
                3:
                    if (rx_count != 0)
                        rx_count <= rx_count - 1;
                    else
                    begin
                        rx_state <= 0;
                        if (!rx_sync)
                            framing_error <= 1;
                        else if (rx_valid && !rx_ready)
                            overrun <= 1;
                        else
                        begin
                            rx_data <= rx_shift;
                            rx_valid <= 1;
                        end
                    end
            endcase
        end
    end
endmodule
