// SPDX-License-Identifier: MIT
// One outstanding translation, separate 16-entry I/D TLBs and a read-only walker.
// A flush cancels the translation but drains every accepted metadata read.
module r32_mmu
    #(parameter FLUSH_CANCEL = 1)
    (input wire clk, reset, flush,
     input wire req_valid,
     output wire req_ready,
     input wire [31 : 0] req_address,
     input wire [1 : 0] req_access,
     input wire req_supervisor, req_paging,
     input wire [31 : 0] req_ptbr,
     output wire res_valid,
     input wire res_ready,
     output reg [31 : 0] res_address,
     output reg res_fault,
     output reg [3 : 0] res_cause,
     output reg [31 : 0] res_fault_address,
     output reg res_uncached,
     output wire walk_valid,
     input wire walk_ready,
     output reg [31 : 0] walk_address,
     input wire walk_res_valid,
     output wire walk_res_ready,
     input wire [31 : 0] walk_data,
     input wire walk_error);
    localparam IDLE = 0, LOOKUP = 1, ISSUE_PDE = 2, WAIT_PDE = 3, ISSUE_PTE = 4, WAIT_PTE = 5,
               RESPONSE = 6, CANCEL_ISSUE = 7, CANCEL_DRAIN = 8;
    reg [3 : 0] state;
    reg stale_fill;
    reg [31 : 0] va, root;
    reg [1 : 0] access_kind;
    reg supervisor, paging;
    reg [3 : 0] permissions;
    reg [31 : 0] valid;
    reg [19 : 0] vpn[0 : 31], frame[0 : 31];
    reg [3 : 0] perms[0 : 31];
    reg [3 : 0] next_i, next_d;
    reg hit;
    reg [19 : 0] hit_frame;
    reg [3 : 0] hit_permissions;
    integer k;
    reg [4 : 0] slot;
    wire instruction = access_kind == 0;
    // Metadata reads must never consume a UART/FIFO or another MMIO device.
    wire metadata_mmio = walk_address[31 : 24] == 8'hf0;
    assign req_ready = state == IDLE && !flush && !reset;
    assign res_valid = state == RESPONSE && !flush && !reset;
    assign walk_valid = (state == ISSUE_PDE || state == ISSUE_PTE || state == CANCEL_ISSUE) &&
                        !reset && !metadata_mmio;
    assign walk_res_ready =
               (state == WAIT_PDE || state == WAIT_PTE || state == CANCEL_DRAIN) && !reset;
    always @*
    begin
        hit = 0;
        hit_frame = 0;
        hit_permissions = 0;
        for (k = 0; k < 32; k = k + 1)
            if (valid[k] && (k < 16) == instruction && vpn[k] == va[31 : 12])
            begin
                hit = 1;
                hit_frame = frame[k];
                hit_permissions = perms[k];
            end
        slot = instruction ? {1'b0, next_i} : {1'b1, next_d};
    end
    task complete
        (input [31 : 0] pa,
         input [3 : 0] rights,
         input check_rights);
        reg mmio;
        reg denied;
        begin
            mmio = pa[31 : 24] == 8'hf0;
            denied = (check_rights && (!(access_kind == 0   ? rights[2]
                                         : access_kind == 1 ? rights[0]
                                                            : rights[1]) ||
                                       (!supervisor && !rights[3]))) ||
                     (mmio && (instruction || !supervisor));
            res_address <= pa;
            res_fault <= denied;
            res_uncached <= mmio;
            res_cause <= access_kind == 0 ? 10 : access_kind == 1 ? 11 : 12;
            res_fault_address <= va;
            state <= RESPONSE;
        end
    endtask
    task fault;
        begin
            res_address <= 0;
            res_fault <= 1;
            res_uncached <= 0;
            res_cause <= access_kind == 0 ? 10 : access_kind == 1 ? 11 : 12;
            res_fault_address <= va;
            state <= RESPONSE;
        end
    endtask
    always @(posedge clk)
    begin
        if (reset)
        begin
            stale_fill <= 0;
            state <= IDLE;
            valid <= 0;
            next_i <= 0;
            next_d <= 0;
            va <= 0;
            root <= 0;
            access_kind <= 0;
            supervisor <= 1;
            paging <= 0;
            permissions <= 0;
            walk_address <= 0;
            res_address <= 0;
            res_fault <= 0;
            res_cause <= 0;
            res_fault_address <= 0;
            res_uncached <= 0;
        end
        else if (flush && FLUSH_CANCEL)
        begin
            valid <= 0;
            next_i <= 0;
            next_d <= 0;
            case (state)
                ISSUE_PDE, ISSUE_PTE, CANCEL_ISSUE:
                    state <= metadata_mmio ? IDLE
                             : walk_ready  ? CANCEL_DRAIN
                                           : CANCEL_ISSUE;
                WAIT_PDE, WAIT_PTE, CANCEL_DRAIN:
                    state <= walk_res_valid ? IDLE : CANCEL_DRAIN;
                default:
                    state <= IDLE;
            endcase
        end
        else
        begin
            if (flush)
            begin
                valid <= 0;
                next_i <= 0;
                next_d <= 0;
                stale_fill <= 1;
            end
            case (state)
                IDLE:
                    if (req_valid && !flush)
                    begin
                        stale_fill <= 0;
                        va <= req_address;
                        root <= req_ptbr;
                        access_kind <= req_access;
                        supervisor <= req_supervisor;
                        paging <= req_paging;
                        state <= LOOKUP;
                    end
                LOOKUP: begin
                    if (!paging)
                        complete(va, 0, 0);
                    else if (root[11 : 0] != 0)
                        fault();
                    else if (hit)
                        complete({hit_frame, va[11 : 0]}, hit_permissions, 1);
                    else
                    begin
                        permissions <= 4'hf;
                        walk_address <= root + {20'b0, va[31 : 22], 2'b0};
                        state <= ISSUE_PDE;
                    end
                end
                ISSUE_PDE:
                    if (metadata_mmio)
                        fault();
                    else if (walk_ready)
                        state <= WAIT_PDE;
                ISSUE_PTE:
                    if (metadata_mmio)
                        fault();
                    else if (walk_ready)
                        state <= WAIT_PTE;
                WAIT_PDE:
                    if (walk_res_valid)
                    begin
                        if (walk_error || !walk_data[0] || walk_data[11 : 5] != 0)
                            fault();
                        else
                        begin
                            permissions <= walk_data[4 : 1];
                            walk_address <=
                                {walk_data[31 : 12], 12'b0} + {20'b0, va[21 : 12], 2'b0};
                            state <= ISSUE_PTE;
                        end
                    end
                WAIT_PTE:
                    if (walk_res_valid)
                    begin
                        if (walk_error || !walk_data[0] || walk_data[11 : 5] != 0)
                            fault();
                        else
                        begin
                            if (!stale_fill && !flush)
                            begin
                                valid[slot] <= 1;
                                vpn[slot] <= va[31 : 12];
                                frame[slot] <= walk_data[31 : 12];
                                perms[slot] <= permissions & walk_data[4 : 1];
                                if (instruction)
                                    next_i <= next_i + 1'b1;
                                else
                                    next_d <= next_d + 1'b1;
                            end
                            complete({walk_data[31 : 12], va[11 : 0]},
                                     permissions & walk_data[4 : 1], 1);
                        end
                    end
                RESPONSE:
                    if (res_ready)
                        state <= IDLE;
                CANCEL_ISSUE:
                    if (walk_ready)
                        state <= CANCEL_DRAIN;
                CANCEL_DRAIN:
                    if (walk_res_valid)
                        state <= IDLE;
                default:
                    state <= IDLE;
            endcase
        end
    end
endmodule
