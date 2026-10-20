// Platform SMP v1: per-request hardware core ID, secondary launch and sticky
// IPI33. CORE_COUNT=1 retains discovery and CPU0 self-IPI without a CPU1.
// No OS scheduling policy lives here. Secondary is parked after reset.
module x32_smp_control
    #(parameter integer CORE_COUNT = 2)
    (input wire clk, reset, req_valid,
     output wire req_ready,
     input wire req_core,
     input wire [5 : 0] offset,
     input wire [31 : 0] wdata,
     input wire [3 : 0] be,
     input wire write,
     output reg rsp_valid,
     input wire rsp_ready,
     output reg [31 : 0] rdata,
     output reg error,
     output reg secondary_run,
     output reg [31 : 0] secondary_pc, secondary_sp,
     input wire secondary_halted, secondary_fault,
     input wire [31 : 0] secondary_current_pc,
     output reg [1 : 0] ipi_pending,
     input wire [1 : 0] ipi_accept);
    assign req_ready = !reset && !rsp_valid;
    wire access = req_valid && req_ready;
    wire shape_ok = offset[1 : 0] == 0 && be == 4'hf && (!write ? wdata == 0 : 1'b1);
    wire writable = offset == 16 || offset == 20 || offset == 24 || offset == 28;
    wire single_bad = CORE_COUNT == 1 && (req_core || (write && offset != 28) ||
                                          (write && offset == 28 && (wdata & 32'hfffffffe) != 0));
    wire bad = single_bad || !shape_ok || (write && !writable) ||
               (write && offset != 28 && req_core) ||
               (write && offset == 24 && (wdata != 1 && wdata != 2)) ||
               (write && offset == 24 && wdata == 1 &&
                (secondary_run || secondary_pc[1 : 0] != 0 || secondary_sp[1 : 0] != 0)) ||
               (write && (offset == 16 || offset == 20) && secondary_run) ||
               (write && offset == 28 && (wdata & 32'hfffffffc) != 0);
    always @(posedge clk)
    begin
        if (reset)
        begin
            rsp_valid <= 0;
            rdata <= 0;
            error <= 0;
            secondary_run <= 0;
            secondary_pc <= 0;
            secondary_sp <= 0;
            ipi_pending <= 0;
        end
        else
        begin
            // A simultaneous SEND wins consumption, preserving a new IPI.
            ipi_pending <= ipi_pending & ~ipi_accept;
            if (rsp_valid && rsp_ready)
                rsp_valid <= 0;
            if (access)
            begin
                rsp_valid <= 1;
                error <= bad;
                rdata <= 0;
                if (!bad)
                begin
                    case (offset)
                        0:
                            if (write)
                                error <= 1;
                            else
                                rdata <= 32'h31504d53;
                        4:
                            if (write)
                                error <= 1;
                            else
                                rdata <= {31'b0, req_core};
                        8:
                            if (write)
                                error <= 1;
                            else
                                rdata <= CORE_COUNT;
                        12:
                            if (write)
                                error <= 1;
                            else
                                rdata <= CORE_COUNT == 1 ? 0
                                                         : {29'b0, secondary_fault,
                                                            secondary_halted, secondary_run};
                        16:
                            if (write)
                                secondary_pc <= wdata;
                            else
                                rdata <= secondary_pc;
                        20:
                            if (write)
                                secondary_sp <= wdata;
                            else
                                rdata <= secondary_sp;
                        24:
                            if (write)
                            begin
                                secondary_run <= wdata == 1;
                                if (wdata == 2)
                                    ipi_pending[1] <= 0;
                            end
                            else
                                rdata <= {31'b0, secondary_run};
                        28:
                            if (write)
                                ipi_pending <= (ipi_pending & ~ipi_accept) | wdata[1 : 0];
                        32:
                            if (write)
                                error <= 1;
                            else
                                rdata <= {30'b0, ipi_pending};
                        36:
                            if (write)
                                error <= 1;
                            else
                                rdata <= CORE_COUNT == 1 ? 0 : secondary_current_pc;
                        default:
                            error <= 1;
                    endcase
                end
            end
        end
    end
endmodule
