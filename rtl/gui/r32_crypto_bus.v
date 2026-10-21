// SPDX-License-Identifier: MIT
// Hold the selected MMIO responder until the outstanding transaction completes.
module r32_crypto_bus
    (input wire clk, reset, req_valid,
     output wire req_ready,
     input wire [11 : 0] req_offset,
     input wire [31 : 0] req_wdata,
     input wire [3 : 0] req_be,
     input wire req_write,
     output wire rsp_valid,
     input wire rsp_ready,
     output wire [31 : 0] rsp_rdata,
     output wire rsp_error);
    reg [1 : 0] pending;
    wire aes = req_offset[11 : 8] == 0;
    wire curve = req_offset[11 : 8] == 1;
    wire ar, av, ae, cr, cv, ce;
    wire [31 : 0] ad, cd;
    assign req_ready = !reset && pending == 0 && (aes ? ar : curve ? cr : 1'b1);
    assign rsp_valid = !reset && (pending == 1 ? av : pending == 2 ? cv : pending == 3);
    assign rsp_rdata = pending == 1 ? ad : pending == 2 ? cd : 32'b0;
    assign rsp_error = pending == 1 ? ae : pending == 2 ? ce : pending == 3;
    x32_crypto_bus aes_gcm(clk,
                           reset,
                           req_valid && pending == 0 && aes && !reset,
                           ar,
                           req_offset[7 : 0],
                           req_wdata,
                           req_be,
                           req_write,
                           av,
                           rsp_ready && pending == 1 && !reset,
                           ad,
                           ae);
    x32_curve_bus curve25519(clk,
                             reset,
                             req_valid && pending == 0 && curve && !reset,
                             cr,
                             req_offset[7 : 0],
                             req_wdata,
                             req_be,
                             req_write,
                             cv,
                             rsp_ready && pending == 2 && !reset,
                             cd,
                             ce);
    always @(posedge clk)
    begin
        if (reset)
            pending <= 0;
        else if (req_valid && req_ready)
            pending <= aes ? 1 : curve ? 2 : 3;
        else if (rsp_valid && rsp_ready)
            pending <= 0;
    end
endmodule
