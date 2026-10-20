`timescale 1ps / 1ps
// Pure simulation: 30 MHz fabric, variable CPU clock and randomized stalls.
module tb_bus_cdc;
    parameter integer CPU_HALF_PS = 12500;
    parameter integer PHASE_PS = 1103;
    parameter EXTERNAL_RESETS = 0;
    reg cpu_clk = 0, soc_clk = 0, reset = 1;
    wire cpu_reset, soc_reset;
    reg [1 : 0] cpu_release = 2'b11;
    reg [2 : 0] soc_release = 3'b111;
    wire cpu_reset_in = cpu_release[1], soc_reset_in = soc_release[2];
    always @(posedge cpu_clk or posedge reset)
        if (reset)
            cpu_release <= 2'b11;
        else
            cpu_release <= {cpu_release[0], 1'b0};
    always @(posedge soc_clk or posedge reset)
        if (reset)
            soc_release <= 3'b111;
        else
            soc_release <= {soc_release[1 : 0], 1'b0};
    reg c_req_valid = 0, c_req_write = 0, c_rsp_ready = 0;
    reg [31 : 0] c_req_address = 0, c_req_wdata = 0;
    reg [3 : 0] c_req_be = 0;
    wire c_req_ready, c_rsp_valid, c_rsp_error;
    wire [31 : 0] c_rsp_rdata;
    wire m_req_valid, m_req_write, m_rsp_ready;
    wire [31 : 0] m_req_address, m_req_wdata;
    wire [3 : 0] m_req_be;
    reg m_req_ready = 0, m_rsp_valid = 0, m_rsp_error = 0;
    reg [31 : 0] m_rsp_rdata = 0;
    x32_v2_bus_cdc #(.EXTERNAL_RESETS(EXTERNAL_RESETS))
        dut(.*);
    always
        #16667 soc_clk = ~soc_clk;
    initial
    begin
        #PHASE_PS;
        forever
            #CPU_HALF_PS cpu_clk = ~cpu_clk;
    end

    reg [31 : 0] rng = 32'h8a314fa2;
    function automatic[31 : 0] next_rng
        (input [31 : 0] value);
        next_rng = {value[30 : 0], value[31] ^ value[21] ^ value[1] ^ value[0]};
    endfunction
    function automatic[31 : 0] merged
        (input [31 : 0] old_data, new_data,
         input [3 : 0] be);
        integer lane;
        begin
            merged = old_data;
            for (lane = 0; lane < 4; lane = lane + 1)
                if (be[lane])
                    merged[lane * 8 +: 8] = new_data[lane * 8 +: 8];
        end
    endfunction
    reg [31 : 0] memory[0 : 255];
    reg [68 : 0] expected_req;
    reg [32 : 0] expected_rsp;
    reg outstanding = 0, delivered = 0;
    integer cpu_accept = 0, soc_accept = 0, cpu_complete = 0, soc_complete = 0, aborted = 0;
    integer byte_writes = 0, reads = 0, errors = 0, epoch_cpu = 0, epoch_soc = 0, epoch_done = 0;
    integer pending_delay = 0, k, transactions = 0;
    reg model_pending = 0, force_soc_stall = 0, force_response_stall = 0;
    reg previous_cpu_stall = 0, previous_soc_stall = 0;
    reg [32 : 0] held_cpu_rsp;
    reg [68 : 0] held_soc_req;
    reg [31 : 0] driver_rng = 32'ha51fe340;

    // Independent observer checks every request/response crossing and order.
    always @(posedge reset)
    begin
        if (outstanding)
            aborted = aborted + 1;
        outstanding = 0;
        delivered = 0;
        epoch_cpu = 0;
        epoch_soc = 0;
        epoch_done = 0;
    end
    always @(posedge cpu_clk)
    begin
        if (cpu_reset)
            previous_cpu_stall = 0;
        else
        begin
            if (previous_cpu_stall && (!c_rsp_valid || {c_rsp_error, c_rsp_rdata} !== held_cpu_rsp))
                $fatal(1, "CPU response changed under backpressure");
            previous_cpu_stall = c_rsp_valid && !c_rsp_ready;
            held_cpu_rsp = {c_rsp_error, c_rsp_rdata};
            if (c_req_valid && c_req_ready)
            begin
                if (outstanding)
                    $fatal(1, "Second outstanding CPU request");
                expected_req = {c_req_write, c_req_be, c_req_address, c_req_wdata};
                outstanding = 1;
                delivered = 0;
                cpu_accept = cpu_accept + 1;
                epoch_cpu = epoch_cpu + 1;
            end
            if (c_rsp_valid)
            begin
                if (!outstanding || !delivered)
                    $fatal(1, "Stale/unmatched CPU response");
                if ({c_rsp_error, c_rsp_rdata} !== expected_rsp)
                    $fatal(1, "Response payload mismatch wanted%h got%h", expected_rsp,
                           {c_rsp_error, c_rsp_rdata});
                if (c_req_ready)
                    $fatal(1, "CPU ready while response outstanding");
                if (c_rsp_ready)
                begin
                    outstanding = 0;
                    delivered = 0;
                    cpu_complete = cpu_complete + 1;
                    epoch_done = epoch_done + 1;
                end
            end
        end
    end
    always @(posedge soc_clk or posedge soc_reset)
    begin
        if (soc_reset)
        begin
            m_req_ready <= 0;
            m_rsp_valid <= 0;
            m_rsp_rdata <= 0;
            m_rsp_error <= 0;
            model_pending <= 0;
            pending_delay <= 0;
            previous_soc_stall <= 0;
            for (k = 0; k < 256; k = k + 1)
                memory[k] <= 32'hc3a50000 + k;
        end
        else
        begin
            rng <= next_rng(rng);
            if (previous_soc_stall && (!m_req_valid || {m_req_write, m_req_be, m_req_address,
                                                        m_req_wdata} !== held_soc_req))
                $fatal(1, "SoC request changed under backpressure");
            previous_soc_stall <= m_req_valid && !m_req_ready;
            held_soc_req <= {m_req_write, m_req_be, m_req_address, m_req_wdata};
            m_req_ready <= !force_soc_stall && !model_pending && !m_rsp_valid && (rng[2 : 0] != 0);
            if (m_req_valid && m_req_ready)
            begin
                if (!outstanding || delivered || model_pending || m_rsp_valid)
                    $fatal(1, "Duplicate/unmatched SoC request");
                if ({m_req_write, m_req_be, m_req_address, m_req_wdata} !== expected_req)
                    $fatal(1, "Request payload changed across crossing");
                delivered = 1;
                soc_accept = soc_accept + 1;
                epoch_soc = epoch_soc + 1;
                m_req_ready <= 0;
                model_pending <= 1;
                pending_delay <= rng[7 : 3];
                // Error cases return data as well, so all 33 response bits matter.
                expected_rsp = {m_req_address[12],
                                m_req_write ? 32'h0 : memory[m_req_address[9 : 2]]};
                m_rsp_error <= m_req_address[12];
                m_rsp_rdata <= m_req_write ? 32'h0 : memory[m_req_address[9 : 2]];
                if (m_req_address[12])
                    errors = errors + 1;
                else if (m_req_write)
                begin
                    memory[m_req_address[9 : 2]] <=
                        merged(memory[m_req_address[9 : 2]], m_req_wdata, m_req_be);
                    byte_writes = byte_writes + 1;
                end
                else
                    reads = reads + 1;
            end
            if (model_pending && !force_response_stall)
            begin
                if (pending_delay > 0)
                    pending_delay <= pending_delay - 1;
                else
                begin
                    m_rsp_valid <= 1;
                    model_pending <= 0;
                end
            end
            if (m_rsp_valid && m_rsp_ready)
            begin
                m_rsp_valid <= 0;
                soc_complete = soc_complete + 1;
            end
        end
    end
    task automatic issue_request
        (input [31 : 0] addr, data,
         input [3 : 0] be,
         input wr);
        begin
            @(negedge cpu_clk);
            while (!c_req_ready) @(negedge cpu_clk)
                ;
            c_req_valid = 1;
            c_req_address = addr;
            c_req_wdata = data;
            c_req_be = be;
            c_req_write = wr;
            @(negedge cpu_clk);
            c_req_valid = 0;
            c_req_address = ~addr;
            c_req_wdata = ~data;
            c_req_be = ~be;
            c_req_write = ~wr;
        end
    endtask
    task automatic finish_response
        (input integer stalled_cycles);
        integer j;
        begin
            while (!c_rsp_valid) @(negedge cpu_clk)
                ;
            // A competing request must not be accepted while response is stalled.
            c_req_valid = 1;
            for (j = 0; j < stalled_cycles; j = j + 1)
            begin
                @(negedge cpu_clk);
                if (c_req_ready || !c_rsp_valid)
                    $fatal(1, "Blocked response/ready contract");
            end
            c_req_valid = 0;
            c_rsp_ready = 1;
            @(negedge cpu_clk);
            c_rsp_ready = 0;
            transactions = transactions + 1;
        end
    endtask
    task automatic common_reset;
        begin
            #3137;
            reset = 1;
            c_req_valid = 0;
            c_rsp_ready = 0;
            #17233;
            if (c_req_ready || c_rsp_valid || m_req_valid || m_rsp_ready)
                $fatal(1, "Traffic visible while reset asserted");
            reset = 0;
            while (cpu_reset || soc_reset) @(negedge cpu_clk)
                ;
            repeat (10)
            begin
                @(negedge cpu_clk);
                if (c_rsp_valid || m_req_valid)
                    $fatal(1, "Stale traffic after reset");
            end
        end
    endtask
    integer i, wait_count;
    initial
    begin
        #52127;
        reset = 0;
        while (cpu_reset || soc_reset) @(negedge cpu_clk)
            ;
        // Random data, byte enables, read/write/errors and destination stalls.
        for (i = 0; i < 800; i = i + 1)
        begin
            driver_rng = next_rng(driver_rng);
            issue_request({19'b0, driver_rng[3], 2'b0, driver_rng[11 : 4], 2'b0},
                          driver_rng ^ 32'hc1f705a4, driver_rng[19 : 16], driver_rng[0]);
            finish_response(driver_rng[25 : 21] % 17);
        end
        if (epoch_cpu != epoch_soc || epoch_cpu != epoch_done)
            $fatal(1, "Lost transaction");
        // Abort before downstream acceptance.
        force_soc_stall = 1;
        repeat (3) @(negedge soc_clk)
            ;
        issue_request(32'h44, 32'h12345678, 4'b0101, 1);
        repeat (11) @(negedge cpu_clk)
            ;
        common_reset();
        force_soc_stall = 0;
        // Abort after downstream acceptance, before its response.
        force_response_stall = 1;
        issue_request(32'h54, 32'h89abcdef, 4'b1010, 1);
        while (!delivered) @(negedge cpu_clk)
            ;
        common_reset();
        force_response_stall = 0;
        // Abort while CPU applies backpressure to an already received response.
        issue_request(32'h1054, 0, 4'b1111, 0);
        while (!c_rsp_valid) @(negedge cpu_clk)
            ;
        common_reset();
        // Sweep short asynchronous reset pulses through different crossing phases.
        for (i = 0; i < 24; i = i + 1)
        begin
            issue_request(i * 4, 32'ha5a55a5a + i, 4'b1111, i[0]);
            #((i * 11939) % 220003 + 1);
            common_reset();
            issue_request(i * 4, 32'h55aa0022 ^ i, i[3 : 0], i[0]);
            finish_response(i % 7);
        end
        for (i = 0; i < 200; i = i + 1)
        begin
            driver_rng = next_rng(driver_rng);
            issue_request({19'b0, driver_rng[3], 2'b0, driver_rng[11 : 4], 2'b0},
                          driver_rng ^ 32'hfedcba98, driver_rng[19 : 16], driver_rng[0]);
            finish_response(driver_rng[25 : 21] % 17);
        end
        repeat (10) @(negedge cpu_clk)
            ;
        if (outstanding || c_rsp_valid || m_req_valid || epoch_cpu != epoch_soc ||
            epoch_cpu != epoch_done)
            $fatal(1, "Final transaction totals inconsistent");
        if (aborted != 27 || reads < 100 || byte_writes < 100 || errors < 100)
            $fatal(1, "Insufficient coverage abort%0d/read%0d/write%0d/error%0d", aborted, reads,
                   byte_writes, errors);
        $display(
            "PASS CPU_HALF_PS=%0d PHASE_PS=%0d EXTERNAL_RESETS=%0d completed=%0d cpu_accept=%0d soc_accept=%0d soc_complete=%0d aborted=%0d reads=%0d byte_writes=%0d errors=%0d",
            CPU_HALF_PS, PHASE_PS, EXTERNAL_RESETS, transactions, cpu_accept, soc_accept,
            soc_complete, aborted, reads, byte_writes, errors);
        $finish;
    end
    initial
    begin
        #2000000000;
        $fatal(1, "Simulation timeout");
    end
endmodule
