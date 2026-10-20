module tb_core;
    parameter PROTECTED = 0;
    reg clk = 0;
    always
        #5 clk = ~clk;
    reg reset = 1;
    reg [31 : 0] irq = 0;
    wire iv, ir, rv, rr, ie, dv, dr, ds, dsr, de, dw;
    wire [31 : 0] ia, id, da, dd, rd;
    wire [3 : 0] db;
    wire ret, st, tr, halt;
    wire [31 : 0] pc, word, npc, value, sa, sd, tp, tc, ta;
    wire [4 : 0] dest;
    wire [3 : 0] sb;
    wire [63 : 0] cycles, instret;
    r32_core #(.ENABLE_FPU32(1),
               .ENABLE_MMU(PROTECTED))
        cpu(clk,
            reset,
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
            de,
            irq,
            ret,
            pc,
            word,
            npc,
            dest,
            value,
            st,
            sa,
            sd,
            sb,
            tr,
            tp,
            tc,
            ta,
            halt,
            cycles,
            instret);
    reg [7 : 0] rom[0 : 32767];
    reg [7 : 0] ram[0 : 65535];
    reg ibusy = 0, dbusy = 0;
    integer ilat = 0, dlat = 0;
    reg [31 : 0] idata = 0, ddata = 0, daddr = 0, dwrite_data = 0;
    reg ierr = 0, derr = 0, dwrite = 0;
    reg [3 : 0] dbe = 0;
    integer allow_traps = 0;
    integer random_stalls = 0, ticks = 0, idx, seed = 32, irq_cycle = 0;
    reg [31 : 0] rng = 32'h12345678;
    reg [1023 : 0] rom_path, ram_path;
    integer max_cycles = 1000000;
    assign ir = !reset && (!ibusy || (rv && rr)) && (!random_stalls || rng[0]);
    assign dr = !reset && !dbusy && (!random_stalls || rng[1]);
    assign rv = ibusy && ilat == 0;
    assign id = idata;
    assign ie = ierr;
    assign ds = dbusy && dlat == 0;
    assign rd = ddata;
    assign de = derr;
    function valid_ram
        (input [31 : 0] addr);
        begin
            valid_ram = (addr < 32768) || (addr >= 32'h10000000 && addr < 32'h10010000);
        end
    endfunction
    function [31 : 0] read_word
        (input [31 : 0] addr);
        integer q;
        reg [31 : 0] v;
        begin
            v = 0;
            for (q = 0; q < 4; q = q + 1)
            begin
                if (addr + q < 32768)
                    v = v | ({24'b0, rom[addr + q]} << (q * 8));
                else if (addr + q >= 32'h10000000 && addr + q < 32'h10010000)
                    v = v | ({24'b0, ram[addr + q - 32'h10000000]} << (q * 8));
            end
            if (addr == 32'hf0000004)
                v = 1;
            read_word = v;
        end
    endfunction
    initial
    begin
        for (idx = 0; idx < 32768; idx = idx + 1)
            rom[idx] = 0;
        for (idx = 0; idx < 65536; idx = idx + 1)
            ram[idx] = 0;
        if (!$value$plusargs("ROM=%s", rom_path))
            $fatal(1, "ROM required");
        if (!$value$plusargs("RAM=%s", ram_path))
            $fatal(1, "RAM required");
        if ($value$plusargs("STALLS=%d", random_stalls))
        begin
        end
        if ($value$plusargs("IRQ_CYCLE=%d", irq_cycle))
        begin
        end
        if ($value$plusargs("TRAP_CONTINUE=%d", allow_traps))
        begin
        end
        $readmemh(rom_path, rom);
        $readmemh(ram_path, ram);
        repeat (4) @(negedge clk)
            ;
        reset = 0;
    end
    always @(posedge clk)
    begin
        if (reset)
        begin
            ibusy <= 0;
            dbusy <= 0;
            ilat <= 0;
            dlat <= 0;
            ticks <= 0;
            irq <= 0;
        end
        else
        begin
            ticks <= ticks + 1;
            rng <= {rng[30 : 0], rng[31] ^ rng[21] ^ rng[1] ^ rng[0]};
            if (irq_cycle != 0 && ticks == irq_cycle)
                irq <= 1;
            if (tr && tc[31])
                irq <= 0;
            if (ibusy && ilat > 0)
                ilat <= ilat - 1;
            if (rv && rr)
                ibusy <= 0;
            if (iv && ir)
            begin
                ibusy <= 1;
                ilat <= random_stalls ? (rng[4 : 2] % 4) : 0;
                idata <= read_word(ia);
                ierr <= !valid_ram(ia);
            end
            if (dbusy && dlat > 0)
                dlat <= dlat - 1;
            if (ds && dsr)
            begin
                dbusy <= 0;
                if (dwrite && !derr)
                begin
                    for (idx = 0; idx < 4; idx = idx + 1)
                        if (dbe[idx])
                        begin
                            if (daddr + idx < 32768)
                                rom[daddr + idx] = dwrite_data >> (idx * 8);
                            else if (daddr + idx >= 32'h10000000 && daddr + idx < 32'h10010000)
                                ram[daddr + idx - 32'h10000000] = dwrite_data >> (idx * 8);
                        end
                    if (daddr == 32'hf0000000)
                        $display("UART %02x", dwrite_data[7 : 0]);
                end
            end
            if (dv && dr)
            begin
                dbusy <= 1;
                dlat <= random_stalls ? (rng[8 : 5] % 7) : 0;
                ddata <= read_word(da);
                daddr <= da;
                dwrite <= dw;
                dwrite_data <= dd;
                dbe <= db;
                derr <= !valid_ram(da) && da != 32'hf0000000 && da != 32'hf0000004;
            end
            if (ticks > max_cycles)
                $fatal(1, "Pipeline timeout");
        end
    end
    always @(negedge clk)
        if (!reset)
        begin
            if (ret)
                $display("RET %08x %08x %08x %02x %08x %01x %08x %08x %01x %0d", pc, word, npc,
                         dest, value, st, sa, sd, sb, cycles);
            if (tr)
            begin
                $display("TRAP %08x %08x %08x", tp, tc, ta);
                if (!tc[31] && !allow_traps)
                    $finish;
            end
            if (halt)
            begin
                $display("HALT %0d %0d", cycles, instret);
                $finish;
            end
        end
    reg [287 : 0] expected[0 : 65535];
    reg [1023 : 0] expected_path;
    integer expected_count = 0, expected_index = 0, expected_fault = 0;
    reg [31 : 0] expected_fault_pc = 0, expected_fault_cause = 0, expected_fault_address = 0;
    initial
    begin
        if ($value$plusargs("COUNT=%d", expected_count))
        begin
        end
        if ($value$plusargs("EXPECTED=%s", expected_path))
        begin
            if (expected_count < 1 || expected_count > 65536)
                $fatal(1, "Invalid expected trace length");
            $readmemh(expected_path, expected, 0, expected_count - 1);
        end
        if ($value$plusargs("FAULT=%d", expected_fault))
        begin
        end
        if ($value$plusargs("FAULT_PC=%h", expected_fault_pc))
        begin
        end
        if ($value$plusargs("FAULT_CAUSE=%h", expected_fault_cause))
        begin
        end
        if ($value$plusargs("FAULT_ADDRESS=%h", expected_fault_address))
        begin
        end
    end
    always @(posedge clk)
        if (!reset && expected_count)
        begin
            if (ret)
            begin
                if (expected_index >= expected_count ||
                    {pc,
                     word,
                     npc,
                     {27'b0, dest},
                     value,
                     {31'b0, st},
                     (st ? sa : 32'b0),
                     (st ? sd : 32'b0),
                     {28'b0, (st ? sb : 4'b0)}} !== expected[expected_index])
                    $fatal(1, "Architectural retirement %0d differs", expected_index);
                expected_index = expected_index + 1;
            end
            if (tr && !tc[31])
            begin
                if (!expected_fault || expected_index != expected_count ||
                    {tp, tc, ta} !==
                        {expected_fault_pc, expected_fault_cause, expected_fault_address})
                    $fatal(1, "Unexpected architectural trap");
            end
            if (halt && (expected_fault || expected_index != expected_count))
                $fatal(1, "Incomplete architectural trace");
        end
endmodule
