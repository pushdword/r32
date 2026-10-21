// SPDX-License-Identifier: MIT
`timescale 1ns / 1ps
module tb;
    reg clk = 0, reset = 1, valid = 0, ready = 0;
    reg [11 : 0] address = 0;
    wire q0, q1, v0, v1, e0, e1;
    wire [31 : 0] d0, d1;
    x32_hw_table #(.RAM_WORDS(8192),
                   .CLOCK_HZ(30000000),
                   .CPU_CLOCK_HZ(50000000),
                   .ENABLE_BOARD_IO(1),
                   .ENABLE_KEYBOARD(1),
                   .ENABLE_PMOD(1),
                   .ENABLE_VIDEO_MODES(1))
        old_table(clk,
                  reset,
                  valid,
                  q0,
                  address,
                  32'b0,
                  4'hf,
                  1'b0,
                  v0,
                  ready,
                  d0,
                  e0);
    x32_hw_table #(.RAM_WORDS(8192),
                   .CLOCK_HZ(30000000),
                   .CPU_CLOCK_HZ(50000000),
                   .ENABLE_BOARD_IO(1),
                   .ENABLE_KEYBOARD(1),
                   .ENABLE_PMOD(1),
                   .ENABLE_VIDEO_MODES(1),
                   .ENABLE_CRYPTO(1),
                   .ENABLE_CURVE(1))
        new_table(clk,
                  reset,
                  valid,
                  q1,
                  address,
                  32'b0,
                  4'hf,
                  1'b0,
                  v1,
                  ready,
                  d1,
                  e1);
    always
        #5 clk = ~clk;
    integer i;
    reg [31 : 0] expected, held;
    initial
    begin
        repeat (3) @(negedge clk)
            ;
        reset = 0;
        for (i = 0; i < 96; i = i + 1)
        begin
            @(negedge clk);
            address = i * 4;
            valid = 1;
            while (!q0 || !q1) @(negedge clk)
                ;
            @(negedge clk);
            valid = 0;
            while (!v0 || !v1) @(negedge clk)
                ;
            if (e1)
                $fatal(1, "New table error");
            if (i < 80)
            begin
                if (e0)
                    $fatal(1, "Base record error");
                if (i == 4)
                begin
                    if (d0 !== 9 || d1 !== 11)
                        $fatal(1, "Count");
                end
                else if (i == 5)
                begin
                    if (d0 !== 320 || d1 !== 384)
                        $fatal(1, "Length");
                end
                else if (d0 !== d1)
                    $fatal(1, "Base changed %0d", i);
                if (i == 14 && d1 !== 50000000)
                    $fatal(1, "CPU clock");
            end
            else
            begin
                if (!e0)
                    $fatal(1, "Base accepts new record");
                case (i - 80)
                    0:
                        expected = 12;
                    1:
                        expected = 0;
                    2:
                        expected = 1;
                    3:
                        expected = 32'hf0003000;
                    4:
                        expected = 140;
                    5:
                        expected = 32'hffffffff;
                    6:
                        expected = 30000000;
                    7:
                        expected = 3;
                    8:
                        expected = 13;
                    9:
                        expected = 0;
                    10:
                        expected = 1;
                    11:
                        expected = 32'hf0003100;
                    12:
                        expected = 192;
                    13:
                        expected = 32'hffffffff;
                    14:
                        expected = 30000000;
                    15:
                        expected = 7;
                endcase
                if (d1 !== expected)
                    $fatal(1, "Crypto record %0d", i);
            end
            held = d1;
            repeat (3)
            begin
                @(negedge clk);
                if (!v1 || d1 !== held)
                    $fatal(1, "Held table response");
            end
            ready = 1;
            @(negedge clk);
            ready = 0;
        end
        $display("PASS_R32_CRYPTO_HWDT words=96 base_records=9 crypto_records=2");
        $finish;
    end
    initial
    begin
        #100000;
        $fatal(1, "Timeout");
    end
endmodule
