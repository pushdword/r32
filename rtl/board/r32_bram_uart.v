// SPDX-License-Identifier: MIT
// Single synchronous BRAM port. Independent response registers avoid a blocked
// instruction response preventing a data load from draining the CPU pipeline.
module r32_bram_uart
    #(parameter INIT_FILE = "firmware.hex",
      parameter CLKS_PER_BIT = 434,
      parameter MEMORY_BITS = 13)
    (input wire clk, reset, uart_rx,
     output wire uart_tx,
     input wire iv,
     output wire ir,
     input wire [31 : 0] ia,
     output reg rv,
     input wire rr,
     output reg [31 : 0] id,
     output reg ie,
     input wire dv,
     output wire dr,
     input wire [31 : 0] da, dd,
     input wire [3 : 0] db,
     input wire dw,
     output reg ds,
     input wire dsr,
     output reg [31 : 0] rd,
     output reg de);
    (* ram_style = "block", syn_ramstyle = "block_ram" *)
        reg [31 : 0] memory[0 : (1 << (MEMORY_BITS - 2)) - 1];
    reg [31 : 0] address, write_data, ram_data;
    reg [3 : 0] be;
    reg writing, read_pending, read_data_port, fetch_error;
    wire tx_ready, rx_valid, rx_ready;
    wire [7 : 0] rx_data;
    wire overrun, framing;
    reg sticky_overrun, sticky_framing;
    wire commit = !reset && ds && dsr && !de;
    wire memory_write = commit && writing && address < (1 << MEMORY_BITS);
    wire data_read_ram = dv && !dw && da < (1 << MEMORY_BITS) && da[1 : 0] == 0;
    assign dr = !reset && !ds && !(read_pending && read_data_port) &&
                !(dv && dw && da == 32'hf0000000 && !tx_ready);
    wire data_read = dv && dr && data_read_ram;
    assign ir = !reset && (!rv || rr) && !(read_pending && !read_data_port) && !memory_write &&
                !data_read;
    wire instruction_read = iv && ir;
    wire [MEMORY_BITS - 3 : 0] memory_address = memory_write ? address[MEMORY_BITS - 1 : 2]
                                                : data_read  ? da[MEMORY_BITS - 1 : 2]
                                                             : ia[MEMORY_BITS - 1 : 2];
    // A single indexed read/write expression infers supported SP normal mode.
    always @(posedge clk)
    begin
        if (memory_write)
        begin
            if (be[0])
                memory[memory_address][7 : 0] <= write_data[7 : 0];
            if (be[1])
                memory[memory_address][15 : 8] <= write_data[15 : 8];
            if (be[2])
                memory[memory_address][23 : 16] <= write_data[23 : 16];
            if (be[3])
                memory[memory_address][31 : 24] <= write_data[31 : 24];
        end
        else if (data_read || instruction_read)
            ram_data <= memory[memory_address];
    end
    wire send = commit && writing && address == 32'hf0000000 && be[0];
    assign rx_ready = commit && !writing && address == 32'hf0000000;
    x32_uart #(.CLKS_PER_BIT(CLKS_PER_BIT))
        uart(clk,
             reset,
             uart_rx,
             send,
             write_data[7 : 0],
             tx_ready,
             uart_tx,
             rx_valid,
             rx_data,
             rx_ready,
             overrun,
             framing);
    initial
        $readmemh(INIT_FILE, memory);
    always @(posedge clk)
    begin
        if (reset)
        begin
            rv <= 0;
            ds <= 0;
            id <= 0;
            ie <= 0;
            rd <= 0;
            de <= 0;
            address <= 0;
            write_data <= 0;
            be <= 0;
            writing <= 0;
            read_pending <= 0;
            read_data_port <= 0;
            fetch_error <= 0;
            sticky_overrun <= 0;
            sticky_framing <= 0;
        end
        else
        begin
            read_pending <= data_read || instruction_read;
            if (data_read || instruction_read)
                read_data_port <= data_read;
            if (rr)
                rv <= 0;
            if (dsr)
                ds <= 0;
            if (read_pending)
            begin
                if (read_data_port)
                begin
                    ds <= 1;
                    rd <= ram_data;
                end
                else
                begin
                    rv <= 1;
                    id <= ram_data;
                    ie <= fetch_error;
                end
            end
            if (instruction_read)
                fetch_error <= ia >= (1 << MEMORY_BITS) || ia[1 : 0] != 0;
            if (dv && dr)
            begin
                if (!data_read)
                    ds <= 1;
                address <= da;
                write_data <= dd;
                be <= db;
                writing <= dw;
                de <= !(da < (1 << MEMORY_BITS) || da == 32'hf0000000 || da == 32'hf0000004 ||
                        da == 32'hf0000008 || da == 32'hf000000c) ||
                      da[1 : 0] != 0;
                if (da == 32'hf0000000)
                    rd <= {24'b0, rx_data};
                else if (da == 32'hf0000004)
                    rd <= {28'b0, sticky_framing, sticky_overrun, rx_valid, tx_ready};
                else if (!data_read)
                    rd <= 0;
            end
            if (commit && writing && address == 32'hf000000c)
            begin
                sticky_overrun <= 0;
                sticky_framing <= 0;
            end
            if (commit && writing && address == 32'hf0000008)
            begin
                if (write_data[0])
                    sticky_overrun <= 0;
                if (write_data[1])
                    sticky_framing <= 0;
            end
            if (overrun)
                sticky_overrun <= 1;
            if (framing)
                sticky_framing <= 1;
        end
    end
endmodule
