`timescale 1ns / 1ps
module tb_board_bus;
    reg clk = 0;
    always
        #5 clk = ~clk;
    reg reset = 1, iv = 0, rr = 0, dv = 0, dw = 0, dsr = 0;
    reg [31 : 0] ia = 0, da = 0, dd = 0;
    reg [3 : 0] db = 15;
    wire ir, rv, ie, dr, ds, de, tx;
    wire [31 : 0] id, rd;
    r32_bram_uart dut(clk,
                      reset,
                      1'b1,
                      tx,
                      iv,
                      ir,
                      ia,
                      rv,
                      rr,
                      id,
                      ie,
                      dv,
                      dr,
                      da,
                      dd,
                      db,
                      dw,
                      ds,
                      dsr,
                      rd,
                      de);
    integer checks = 0, ticks = 0;
    reg [31 : 0] old_instruction;
    always @(posedge clk)
    begin
        ticks <= ticks + 1;
        if (ticks > 1000)
            $fatal(1, "Bus watchdog");
    end
    task tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask
    task assert_ok
        (input condition);
        begin
            checks = checks + 1;
            if (condition !== 1)
                $fatal(1, "Bus check %0d failed", checks);
        end
    endtask
    task data_request
        (input [31 : 0] a,
         input [31 : 0] v,
         input [3 : 0] byte_enable,
         input writing);
        begin
            @(negedge clk);
            da = a;
            dd = v;
            db = byte_enable;
            dw = writing;
            dv = 1;
            #1;
            while (!dr)
            begin
                tick();
                @(negedge clk);
            end
            tick();
            @(negedge clk);
            dv = 0;
            while (!ds)
                tick();
            @(negedge clk);
        end
    endtask
    task instruction_request
        (input [31 : 0] a);
        begin
            @(negedge clk);
            ia = a;
            iv = 1;
            #1;
            while (!ir)
            begin
                tick();
                @(negedge clk);
            end
            tick();
            @(negedge clk);
            iv = 0;
            while (!rv)
                tick();
            @(negedge clk);
        end
    endtask
    task finish_data;
        begin
            dsr = 1;
            tick();
            @(negedge clk);
            dsr = 0;
        end
    endtask
    task finish_instruction;
        begin
            rr = 1;
            tick();
            @(negedge clk);
            rr = 0;
        end
    endtask
    initial
    begin
        repeat (3)
            tick();
        @(negedge clk);
        reset = 0;
        old_instruction = dut.memory[0];
        data_request(32'h1000, 32'h11223344, 15, 1);
        assert_ok(ds && !de);
        repeat (4)
        begin
            tick();
            assert_ok(dut.memory[1024] === 0);
        end
        instruction_request(32'h1000);
        assert_ok(rv && !ie && id === 0);
        finish_data();
        assert_ok(dut.memory[1024] === 32'h11223344);
        assert_ok(rv && id === 0);
        // Independent buffers let data drain even when the CPU stalls fetch output.
        data_request(32'h1000, 0, 15, 0);
        assert_ok(ds && rd === 32'h11223344);
        assert_ok(rv && id === 0);
        repeat (4)
        begin
            tick();
            assert_ok(id === 0 && rd === 32'h11223344);
        end
        finish_instruction();
        instruction_request(0);
        assert_ok(id === old_instruction);
        assert_ok(rd === 32'h11223344);
        finish_data();
        finish_instruction();
        data_request(32'h1000, 32'haabbccdd, 2, 1);
        finish_data();
        data_request(32'h1000, 0, 15, 0);
        assert_ok(rd === 32'h1122cc44);
        finish_data();
        data_request(32'h1001, 32'hffffffff, 15, 1);
        assert_ok(de);
        finish_data();
        assert_ok(dut.memory[1024] === 32'h1122cc44);
        data_request(32'h1000, 32'hffffffff, 15, 1);
        reset = 1;
        dsr = 1;
        tick();
        @(negedge clk);
        reset = 0;
        dsr = 0;
        assert_ok(dut.memory[1024] === 32'h1122cc44);
        data_request(32'h1000, 0, 15, 0);
        assert_ok(rd === 32'h1122cc44);
        finish_data();
        instruction_request(32'h3000);
        assert_ok(rv && ie);
        $display("PASS BOARD BUS checks=%0d", checks);
        $finish;
    end
endmodule
