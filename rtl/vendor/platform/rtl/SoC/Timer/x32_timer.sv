// MMIO countdown timer, clocked by the SoC clock. No CPU ISA extension.
// CTRL: enable/periodic/irq-enable. All accesses are aligned full words.
// STATUS.pending records expiry; irq_valid is a separate one-entry notification
// queue, held until irq_ready. ACK/masking cannot withdraw a queued notification.
module x32_timer
    #(parameter [31 : 0] CLOCK_HZ = 32'd50000000)
    (input wire clk, reset,
     input wire req_valid,
     output wire req_ready,
     input wire [4 : 0] req_offset,
     input wire [31 : 0] req_wdata,
     input wire [3 : 0] req_be,
     input wire req_write,
     output reg rsp_valid,
     input wire rsp_ready,
     output reg [31 : 0] rsp_rdata,
     output reg rsp_error,
     output wire irq_valid,
     input wire irq_ready);
    reg [2 : 0] control;
    reg [31 : 0] period, remaining, ticks;
    reg pending, notification;
    wire known = req_offset == 0 || req_offset == 4 || req_offset == 8 || req_offset == 12 ||
                 req_offset == 16 || req_offset == 20 || req_offset == 24;
    wire invalid = !known || req_be != 4'hf || (!req_write && req_wdata != 0) ||
                   (req_write && req_offset != 0 && req_offset != 4 && req_offset != 20) ||
                   (req_write && req_offset == 0 &&
                    ((|req_wdata[31 : 3]) || (req_wdata[0] && period == 0))) ||
                   (req_write && req_offset == 4 && req_wdata == 0 && control[0]) ||
                   (req_write && req_offset == 20 && (|req_wdata[31 : 1]));
    wire accept = req_valid && req_ready;
    wire ctrl_write = accept && !invalid && req_write && req_offset == 0;
    wire period_write = accept && !invalid && req_write && req_offset == 4;
    wire acknowledge = accept && !invalid && req_write && req_offset == 20 && req_wdata[0];
    // Reprogramming takes priority over counting; a newly loaded interval begins
    // after this edge. An ACK does not suppress an expiry on the same edge.
    wire expire = control[0] && remaining == 1 && !ctrl_write && !period_write;
    assign req_ready = !reset && !rsp_valid;
    assign irq_valid = !reset && notification;
    always @(posedge clk)
    begin
        if (reset)
        begin
            control <= 0;
            period <= 0;
            remaining <= 0;
            ticks <= 0;
            pending <= 0;
            notification <= 0;
            rsp_valid <= 0;
            rsp_rdata <= 0;
            rsp_error <= 0;
        end
        else
        begin
            if (rsp_valid && rsp_ready)
                rsp_valid <= 0;
            if (accept)
            begin
                rsp_valid <= 1;
                rsp_error <= invalid;
                rsp_rdata <= 0;
                if (!invalid && !req_write)
                    case (req_offset)
                        0:
                            rsp_rdata <= {29'b0, control};
                        4:
                            rsp_rdata <= period;
                        8:
                            rsp_rdata <= remaining;
                        12:
                            rsp_rdata <= {30'b0, notification, pending};
                        16:
                            rsp_rdata <= ticks;
                        24:
                            rsp_rdata <= CLOCK_HZ;
                        default:
                            rsp_rdata <= 0;
                    endcase
            end
            if (notification && irq_ready)
                notification <= 0;
            if (acknowledge)
                pending <= 0;
            if (ctrl_write)
            begin
                control <= req_wdata[2 : 0];
                remaining <= req_wdata[0] ? period : 0;
                if (req_wdata[2] && pending)
                    notification <= 1;
            end
            else if (period_write)
            begin
                period <= req_wdata;
                if (control[0])
                    remaining <= req_wdata;
            end
            else if (control[0])
            begin
                if (expire)
                begin
                    ticks <= ticks + 1'b1;
                    pending <= 1;
                    if (control[2])
                        notification <= 1;
                    if (control[1])
                        remaining <= period;
                    else
                    begin
                        remaining <= 0;
                        control[0] <= 0;
                    end
                end
                else
                    remaining <= remaining - 1'b1;
            end
        end
    end
endmodule
