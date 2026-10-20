// Provisional bring-up map: 4 KiB BRAM at 0, UART at F0000000.
// DATA +0: lane0 TX write/RX read; STATUS +4: TXready/RXvalid/overrun/framing.
// CONTROL +8: lane0 bits0/1 W1C overrun/framing. No IRQ in this first BSP.
module x32_bram_uart_bus
    #(parameter integer RAM_WORDS = 1024,
      parameter INIT_FILE = "firmware.hex",
      parameter integer CLKS_PER_BIT = 434)
    (input wire clk, reset, uart_rx,
     output wire uart_tx,
     input wire req_valid,
     output wire req_ready,
     input wire [31 : 0] req_address, req_wdata,
     input wire [3 : 0] req_be,
     input wire req_write,
     output reg rsp_valid,
     input wire rsp_ready,
     output wire [31 : 0] rsp_rdata,
     output reg rsp_error);
    localparam integer AW = $clog2(RAM_WORDS);
    (* ram_style = "block" *) reg [31 : 0] memory[0 : RAM_WORDS - 1];
    initial
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, memory);
    wire in_ram = req_address < 32'(RAM_WORDS * 4);
    wire uart_data = req_address == 32'hf0000000;
    wire uart_status = req_address == 32'hf0000004;
    wire uart_control = req_address == 32'hf0000008;
    wire malformed = req_address[1 : 0] != 0 || req_be == 0 || (!req_write && req_wdata != 0);
    wire invalid =
             malformed || !(in_ram || uart_data || uart_status || uart_control) ||
             (req_write && uart_status) ||
             (req_write && uart_control && ((req_be != 1) || (req_wdata & 32'hfffffffc) != 0)) ||
             (uart_data && req_write && (req_be != 1));
    wire tx_ready, rx_valid, rx_overrun, rx_framing;
    wire [7 : 0] rx_data;
    reg sticky_overrun, sticky_framing;
    wire accept = req_valid && req_ready;
    wire tx_valid = accept && !invalid && uart_data && req_write;
    wire rx_ready = accept && !invalid && uart_data && !req_write && req_be[0];
    assign req_ready = !reset && !rsp_valid &&
                       (!req_valid || invalid || !uart_data || !req_write || tx_ready);
    x32_uart #(.CLKS_PER_BIT(CLKS_PER_BIT))
        uart(clk,
             reset,
             uart_rx,
             tx_valid,
             req_wdata[7 : 0],
             tx_ready,
             uart_tx,
             rx_valid,
             rx_data,
             rx_ready,
             rx_overrun,
             rx_framing);
    reg [31 : 0] ram_read, io_read;
    reg response_ram, response_write;
    assign rsp_rdata = rsp_error || response_write ? 0 : response_ram ? ram_read : io_read;
    integer lane;
    always @(posedge clk)
    begin
        if (accept && !invalid && in_ram)
        begin
            if (req_write)
                for (lane = 0; lane < 4; lane = lane + 1)
                    if (req_be[lane])
                        memory[req_address[AW + 1 : 2]][lane * 8 +: 8] <= req_wdata[lane * 8 +: 8];
            ram_read <= memory[req_address[AW + 1 : 2]];
        end
        if (reset)
        begin
            rsp_valid <= 0;
            rsp_error <= 0;
            sticky_overrun <= 0;
            sticky_framing <= 0;
            response_ram <= 0;
            response_write <= 0;
            io_read <= 0;
        end
        else
        begin
            if (rx_overrun)
                sticky_overrun <= 1;
            if (rx_framing)
                sticky_framing <= 1;
            if (rsp_valid && rsp_ready)
                rsp_valid <= 0;
            else if (accept)
            begin
                rsp_valid <= 1;
                rsp_error <= invalid;
                response_ram <= in_ram;
                response_write <= req_write;
                io_read <= 0;
                if (!invalid)
                begin
                    if (uart_data && !req_write && req_be[0])
                        io_read <= {24'b0, rx_valid ? rx_data : 8'b0};
                    else if (uart_status && req_be[0])
                        io_read <= {28'b0, sticky_framing, sticky_overrun, rx_valid, tx_ready};
                    if (uart_control && req_write)
                    begin
                        if (req_wdata[0])
                            sticky_overrun <= rx_overrun;
                        if (req_wdata[1])
                            sticky_framing <= rx_framing;
                    end
                end
            end
        end
    end
endmodule

// Bounded synchronous FIFO with a one-cycle prefetched head. Head is the
// synchronous RAM output register. A consumer observes VALID on the following
// edge, after the matching initialized head has become visible. RAM is unreset.
module x32_uart_fifo
    #(parameter integer DEPTH = 256)
    (input wire clk, reset,
     input wire put,
     input wire [7 : 0] data,
     output wire space,
     output wire valid,
     output reg [7 : 0] head,
     input wire take,
     output reg [$clog2(DEPTH) : 0] count);
    localparam AW = $clog2(DEPTH);
    reg [AW - 1 : 0] wr, rd;
    reg head_valid;
    (* ram_style = "block" *) reg [7 : 0] memory[0 : DEPTH - 1];
    wire push = put && space, pop = take && valid;
    wire fetch = count != 0 && !head_valid;
    assign space = count < DEPTH;
    assign valid = head_valid;
    always @(posedge clk)
    begin
        if (push && !reset)
            memory[wr] <= data;
        if (fetch && !reset)
            head <= memory[rd];
        if (reset)
        begin
            wr <= 0;
            rd <= 0;
            count <= 0;
            head_valid <= 0;
        end
        else
        begin
            if (push)
                wr <= wr + 1'b1;
            if (pop)
            begin
                rd <= rd + 1'b1;
                head_valid <= 0;
            end
            case ({push, pop})
                2'b10:
                    count <= count + 1'b1;
                2'b01:
                    count <= count - 1'b1;
                default: begin
                end
            endcase
            if (fetch)
                head_valid <= 1;
        end
    end
endmodule

// Private FIFO/IRQ UART extension. Legacy DATA/STATUS/CONTROL preserved.
// STATUS31=cap,4=physically drained. ID12=UAF1, COUNTS16={RXcount,TXcount},
// IRQ20 bit0 TX<=64 / bit1 RX available or sticky errors. ERRORS24={frame16,overrun16}.
// Reset STATUS retains the legacy known-bit mask, including strict ROM POST.
// Read CONTROL+8: UAF1 discovery (legacy bus safely returns zero). Only after
// that discovery, BYTE write CONTROL bit2 opts into STATUS31/4 and IRQs.
module x32_bram_uart_fifo_bus
    #(parameter integer RAM_WORDS = 1024,
      parameter INIT_FILE = "firmware.hex",
      parameter integer CLKS_PER_BIT = 434)
    (input wire clk, reset, uart_rx,
     output wire uart_tx,
     input wire req_valid,
     output wire req_ready,
     input wire [31 : 0] req_address, req_wdata,
     input wire [3 : 0] req_be,
     input wire req_write,
     output reg rsp_valid,
     input wire rsp_ready,
     output wire [31 : 0] rsp_rdata,
     output reg rsp_error,
     output wire irq);
    localparam integer AW = $clog2(RAM_WORDS);
    (* ram_style = "block" *) reg [31 : 0] memory[0 : RAM_WORDS - 1];
    initial
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, memory);
    wire in_ram = req_address < 32'(RAM_WORDS * 4);
    wire uart_data = req_address == 32'hf0000000, uart_status = req_address == 32'hf0000004;
    wire uart_control = req_address == 32'hf0000008, uart_id = req_address == 32'hf000000c;
    wire uart_counts = req_address == 32'hf0000010, uart_irqctl = req_address == 32'hf0000014;
    wire uart_errors = req_address == 32'hf0000018;
    wire malformed = req_address[1 : 0] != 0 || req_be == 0 || (!req_write && req_wdata != 0);
    wire invalid =
             malformed ||
             !(in_ram || uart_data || uart_status || uart_control || uart_id || uart_counts ||
               uart_irqctl || uart_errors) ||
             (req_write && (uart_status || uart_id || uart_counts || uart_errors)) ||
             (req_write && uart_control && (req_be != 1 || (req_wdata & 32'hfffffff8) != 0)) ||
             (req_write && uart_data && req_be != 1) ||
             (uart_irqctl && (req_be != 15 || (req_write && req_wdata > 3)));
    wire raw_tx_ready, raw_rx_valid, raw_overrun, raw_framing;
    wire [7 : 0] raw_rx_data, tx_head, rx_head;
    wire tx_space, tx_valid, rx_space, rx_valid;
    wire [8 : 0] tx_count, rx_count;
    reg sticky_overrun, sticky_framing;
    reg [1 : 0] irq_control;
    reg features_enabled;
    reg [15 : 0] overrun_count, framing_count;
    wire accept = req_valid && req_ready;
    wire tx_push = accept && !invalid && uart_data && req_write;
    wire rx_take = accept && !invalid && uart_data && !req_write && req_be[0];
    assign req_ready = !reset && !rsp_valid &&
                       (!req_valid || invalid || !uart_data || !req_write || tx_space);
    assign irq = features_enabled &&
                 ((irq_control[0] && tx_count <= 64) ||
                  (irq_control[1] && (rx_count != 0 || sticky_overrun || sticky_framing)));
    x32_uart_fifo tx_queue(clk,
                           reset,
                           tx_push,
                           req_wdata[7 : 0],
                           tx_space,
                           tx_valid,
                           tx_head,
                           raw_tx_ready,
                           tx_count);
    x32_uart_fifo rx_queue(clk,
                           reset,
                           raw_rx_valid,
                           raw_rx_data,
                           rx_space,
                           rx_valid,
                           rx_head,
                           rx_take,
                           rx_count);
    x32_uart #(.CLKS_PER_BIT(CLKS_PER_BIT))
        uart(clk,
             reset,
             uart_rx,
             tx_valid,
             tx_head,
             raw_tx_ready,
             uart_tx,
             raw_rx_valid,
             raw_rx_data,
             rx_space,
             raw_overrun,
             raw_framing);
    reg [31 : 0] ram_read, io_read;
    reg response_ram, response_write;
    assign rsp_rdata = rsp_error || response_write ? 0 : response_ram ? ram_read : io_read;
    integer lane;
    always @(posedge clk)
    begin
        if (accept && !invalid && in_ram)
        begin
            if (req_write)
                for (lane = 0; lane < 4; lane = lane + 1)
                    if (req_be[lane])
                        memory[req_address[AW + 1 : 2]][lane * 8 +: 8] <= req_wdata[lane * 8 +: 8];
            ram_read <= memory[req_address[AW + 1 : 2]];
        end
        if (reset)
        begin
            rsp_valid <= 0;
            rsp_error <= 0;
            sticky_overrun <= 0;
            sticky_framing <= 0;
            response_ram <= 0;
            response_write <= 0;
            io_read <= 0;
            irq_control <= 0;
            overrun_count <= 0;
            framing_count <= 0;
            features_enabled <= 0;
        end
        else
        begin
            if (raw_overrun)
            begin
                sticky_overrun <= 1;
                if (overrun_count != 16'hffff)
                    overrun_count <= overrun_count + 1'b1;
            end
            if (raw_framing)
            begin
                sticky_framing <= 1;
                if (framing_count != 16'hffff)
                    framing_count <= framing_count + 1'b1;
            end
            if (rsp_valid && rsp_ready)
                rsp_valid <= 0;
            else if (accept)
            begin
                rsp_valid <= 1;
                rsp_error <= invalid;
                response_ram <= in_ram;
                response_write <= req_write;
                io_read <= 0;
                if (!invalid)
                begin
                    if (uart_data && !req_write && req_be[0])
                        io_read <= {24'b0, rx_valid ? rx_head : 8'b0};
                    else if (uart_status && req_be[0])
                        io_read <= {features_enabled ? 27'h4000000 : 27'b0,
                                    features_enabled && raw_tx_ready && tx_count == 0,
                                    sticky_framing,
                                    sticky_overrun,
                                    rx_valid,
                                    tx_space};
                    else if (uart_control && !req_write && req_be[0])
                        io_read <= 32'h31464155;
                    else if (uart_id)
                        io_read <= 32'h31464155;
                    else if (uart_counts)
                        io_read <= {7'b0, rx_count, 7'b0, tx_count};
                    else if (uart_irqctl)
                        io_read <= {30'b0, irq_control};
                    else if (uart_errors)
                        io_read <= {framing_count, overrun_count};
                    if (uart_control && req_write)
                    begin
                        if (req_wdata[0])
                            sticky_overrun <= raw_overrun;
                        if (req_wdata[1])
                            sticky_framing <= raw_framing;
                        if (req_wdata[2])
                            features_enabled <= 1;
                    end
                    if (uart_irqctl && req_write)
                        irq_control <= req_wdata[1 : 0];
                end
            end
        end
    end
endmodule
