// SPDX-License-Identifier: MIT

`timescale 1ns / 1ps
module tb;
    reg clk = 0, reset = 1, req_valid = 0, req_write = 0, rsp_ready = 0;
    reg [7 : 0] req_offset = 0;
    reg [31 : 0] req_wdata = 0;
    reg [3 : 0] req_be = 15;
    wire req_ready, rsp_valid, rsp_error;
    wire [31 : 0] rsp_rdata;
    x32_curve_bus dut(.*);
    always
        #5 clk = ~clk;
    integer checks = 0, j, count;
    reg [31 : 0] value;
    reg [255 : 0] got;
    task access
        (input wr,
         input [7 : 0] off,
         input [31 : 0] data,
         input [3 : 0] be,
         input error,
         output [31 : 0] result);
        integer n;
        reg [31 : 0] held;
        reg e;
        begin
            @(negedge clk);
            req_valid = 1;
            req_write = wr;
            req_offset = off;
            req_wdata = data;
            req_be = be;
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
            n = 0;
            while (!rsp_valid)
            begin
                @(negedge clk);
                n = n + 1;
                if (n > 50)
                    $fatal(1, "Response timeout");
            end
            held = rsp_rdata;
            e = rsp_error;
            repeat (3)
            begin
                @(negedge clk);
                if (!rsp_valid || rsp_rdata !== held || rsp_error !== e)
                    $fatal(1, "Held response changed");
            end
            if (e !== error)
                $fatal(1, "Error mismatch wr%0d offset%0d expected%0d got%0d", wr, off, error, e);
            if (error && held !== 0)
                $fatal(1, "Error exposed data");
            result = held;
            checks = checks + 1;
            rsp_ready = 1;
            @(negedge clk);
            rsp_ready = 0;
        end
    endtask
    task wr
        (input [7 : 0] off,
         input [31 : 0] data);
        reg [31 : 0] ignored;
        begin
            access(1, off, data, 15, 0, ignored);
        end
    endtask
    task load
        (input [7 : 0] off,
         input [255 : 0] data);
        begin
            for (j = 0; j < 8; j = j + 1)
                wr(off + j * 4, data[j * 32 +: 32]);
        end
    endtask
    task wipe;
        begin
            wr(16, 4);
            count = 0;
            access(0, 12, 0, 15, 0, value);
            while (value[0])
            begin
                repeat (100) @(negedge clk)
                    ;
                access(0, 12, 0, 15, 0, value);
                count = count + 1;
                if (count > 20)
                    $fatal(1, "Wipe timeout");
            end
            if (value !== 0)
                $fatal(1, "Wipe status nonzero");
            for (j = 128; j < 1024; j = j + 1)
                if (dut.core.field.fields[j] !== 0)
                    $fatal(1, "Secret survived wipe");
        end
    endtask
    initial
    begin
        repeat (3) @(negedge clk)
            ;
        reset = 0;
        repeat (1100) @(negedge clk)
            ;
        access(0, 0, 0, 15, 0, value);
        if (value !== 32'h31565243)
            $fatal(1, "ID");
        access(0, 8, 0, 15, 0, value);
        if (value !== 7)
            $fatal(1, "Capabilities");
        access(0, 160, 0, 15, 1, value);
        access(0, 64, 0, 15, 1, value);
        access(1, 16, 1, 15, 1, value);
        access(1, 16, 0, 15, 1, value);
        access(1, 64, 0, 3, 1, value);
        access(1, 65, 0, 15, 1, value);
        load(64, 256'hc49a44ba44226a50185afcc10a4c1462dd5e46824b15163b9d7c52f06be346a5);
        access(1, 16, 1, 15, 1, value);
        load(128, 256'h4c1cabd0a603a9103b35b326ec2466727c5fb124a4c19435db3030586768dbe6);
        wr(16, 1);
        access(1, 64, 0, 15, 1, value);
        access(1, 16, 1, 15, 1, value);
        access(0, 160, 0, 15, 1, value);
        count = 0;
        access(0, 12, 0, 15, 0, value);
        while (value[0])
        begin
            repeat (100000) @(negedge clk)
                ;
            access(0, 12, 0, 15, 0, value);
            count = count + 1;
            if (count > 100)
                $fatal(1, "Operation timeout");
        end
        if (value !== 6)
            $fatal(1, "Operation failed status%0d", value);
        got = 0;
        for (j = 0; j < 8; j = j + 1)
        begin
            access(0, 160 + j * 4, 0, 15, 0, value);
            got[j * 32 +: 32] = value;
        end
        if (got !== 256'h5285a2775507b454f7711c4903cfec324f088df24dea948e90c6e99d3755dac3)
            $fatal(1, "MMIO output byte order got%064h", got);
        access(0, 24, 0, 15, 0, value);
        if (value !== 6605389)
            $fatal(1, "Cycle counter");
        wipe();
        load(64, ~256'b0);
        load(128, 256'd9);
        wr(16, 1);
        repeat (1000) @(negedge clk)
            ;
        wipe();
        access(0, 160, 0, 15, 1, value);
        load(64, ~256'b0);
        load(128, 256'd9);
        wr(16, 1);
        repeat (1000) @(negedge clk)
            ;
        reset = 1;
        @(negedge clk);
        reset = 0;
        repeat (1100) @(negedge clk)
            ;
        access(0, 12, 0, 15, 0, value);
        if (value !== 0)
            $fatal(1, "Reset status");
        $display("PASS_CURVE_BUS checks=%0d", checks);
        $finish;
    end
    initial
    begin
        #200000000;
        $fatal(1, "Global timeout");
    end
endmodule
