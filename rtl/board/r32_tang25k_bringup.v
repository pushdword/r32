// SPDX-License-Identifier: MIT
// One50MHz domain. No PLL, SDRAM, SD, NOR, USB or Ethernet signals are driven.
module r32_tang25k_bringup
    #(parameter INIT_FILE = "firmware.hex",
      parameter CLKS_PER_BIT = 434,
      parameter POWERUP_BITS = 16)
    (input wire clk, reset_button, uart_rx,
     output wire uart_tx);
    reg [POWERUP_BITS - 1 : 0] powerup = 0;
    (* syn_keep = 1, async_reg = "true" *) reg button_meta = 0, button_sync = 0;
    always @(posedge clk)
    begin
        if (!(&powerup))
            powerup <= powerup + 1'b1;
        button_meta <= reset_button;
        button_sync <= button_meta;
    end
    wire reset = !(&powerup) || button_sync;
    wire iv, ir, rv, rr, ie, dv, dr, ds, dsr, de, dw;
    wire [31 : 0] ia, id, da, dd, rd;
    wire [3 : 0] db;
    wire ret, store, tr, halt;
    wire [31 : 0] pc, word, npc, value, sa, sd, tp, tc, ta;
    wire [4 : 0] dest;
    wire [3 : 0] sb;
    wire [63 : 0] cycles, instret;
    r32_core #(.ENABLE_FPU32(0))
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
            32'b0,
            ret,
            pc,
            word,
            npc,
            dest,
            value,
            store,
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
    r32_bram_uart #(.INIT_FILE(INIT_FILE),
                    .CLKS_PER_BIT(CLKS_PER_BIT))
        bus(clk,
            reset,
            uart_rx,
            uart_tx,
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
endmodule
