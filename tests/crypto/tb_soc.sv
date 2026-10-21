// SPDX-License-Identifier: MIT
`timescale 1ns / 1ps
module tb;
    reg clk = 0, reset = 1, req_valid = 0, req_write = 0, rsp_ready = 0;
    reg [11 : 0] req_offset = 0;
    reg [31 : 0] req_wdata = 0;
    reg [3 : 0] req_be = 15;
    wire req_ready, rsp_valid, rsp_error;
    wire [31 : 0] rsp_rdata;
    r32_soc_bus #(.INIT_FILE("tests/crypto/boot.hex"),
                  .ENABLE_CRYPTO(1))
        dut(.clk(clk),
            .reset(reset),
            .uart_rx(1'b1),
            .iv(1'b0),
            .rr(1'b1),
            .ia(32'b0),
            .dv(req_valid),
            .dr(req_ready),
            .da(32'hf0003000 + req_offset),
            .dd(req_wdata),
            .db(req_be),
            .dw(req_write),
            .ds(rsp_valid),
            .dsr(rsp_ready),
            .rd(rsp_rdata),
            .de(rsp_error),
            .timer_accept(1'b0),
            .ipi_accept(1'b0),
            .sdram_dq_in(16'b0),
            .pixel_clk(clk),
            .pixel_reset(reset),
            .video_locked(1'b1),
            .pmod_inputs(4'b0),
            .sd_miso(1'b1),
            .sd_cd_n(1'b0),
            .keyboard_clock_ready(1'b0),
            .keyboard_present(1'b0),
            .keyboard_error(1'b0),
            .keyboard_report(1'b0),
            .keyboard_data(64'b0));
    always
        #5 clk = ~clk;
    integer checks = 0;
    task access
        (input [11 : 0] off,
         input [31 : 0] expected,
         input bad);
        integer n;
        begin
            @(negedge clk);
            req_valid = 1;
            req_offset = off;
            #1;
            n = 0;
            while (!req_ready)
            begin
                @(negedge clk);
                n = n + 1;
                if (n > 50)
                    $fatal(1, "Request timeout");
            end
            @(negedge clk);
            req_valid = 0;
            req_offset = ~off;
            n = 0;
            while (!rsp_valid)
            begin
                @(negedge clk);
                n = n + 1;
                if (n > 50)
                    $fatal(1, "Response timeout");
            end
            repeat (5)
            begin
                if (rsp_error !== bad || rsp_rdata !== expected || !rsp_valid || req_ready)
                    $fatal(1, "Route/response %03x", off);
                @(negedge clk);
                req_offset = req_offset + 256;
                req_valid = 1;
                req_wdata = req_wdata + 1;
            end
            req_valid = 0;
            rsp_ready = 1;
            @(negedge clk);
            rsp_ready = 0;
            if (rsp_valid)
                $fatal(1, "Repeated response");
            checks = checks + 1;
        end
    endtask
    initial
    begin
        repeat (3) @(negedge clk)
            ;
        reset = 0;
        access(0, 32'h31434741, 0);
        access(12'h100, 32'h31565243, 0);
        access(8, 3, 0);
        access(12'h108, 7, 0);
        access(12'h200, 0, 1);
        access(12'hfff, 0, 1);
        req_be = 3;
        access(0, 0, 1);
        req_be = 15;
        access(1, 0, 1);
        @(negedge clk);
        req_valid = 1;
        req_offset = 0;
        @(negedge clk);
        req_valid = 0;
        reset = 1;
        @(negedge clk);
        reset = 0;
        if (rsp_valid)
            $fatal(1, "Reset retained response");
        access(12'h100, 32'h31565243, 0);
        $display("PASS_R32_SOC_CRYPTO_ROUTE checks=%0d reset/backpressure/unmapped", checks);
        $finish;
    end
    initial
    begin
        #100000;
        $fatal(1, "Timeout");
    end
endmodule
