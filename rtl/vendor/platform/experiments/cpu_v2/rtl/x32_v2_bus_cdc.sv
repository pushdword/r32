// V2 experiment only: single-outstanding held-payload CPU/SoC clock crossing.
// Common reset asserts asynchronously and releases synchronously in each domain.
// A reset aborts a pending response; an already accepted write is not rolled back.
module x32_v2_bus_cdc
    #(parameter EXTERNAL_RESETS = 0)
    (input wire cpu_clk, soc_clk, reset,
     input wire cpu_reset_in, soc_reset_in,
     output wire cpu_reset, soc_reset,
     input wire c_req_valid,
     output wire c_req_ready,
     input wire [31 : 0] c_req_address, c_req_wdata,
     input wire [3 : 0] c_req_be,
     input wire c_req_write,
     output wire c_rsp_valid,
     input wire c_rsp_ready,
     output wire [31 : 0] c_rsp_rdata,
     output wire c_rsp_error,
     output wire m_req_valid,
     input wire m_req_ready,
     output wire [31 : 0] m_req_address, m_req_wdata,
     output wire [3 : 0] m_req_be,
     output wire m_req_write,
     input wire m_rsp_valid,
     output wire m_rsp_ready,
     input wire [31 : 0] m_rsp_rdata,
     input wire m_rsp_error);
    // Constrain the first toggle synchronizer stages as asynchronous crossings;
    // held payloads need max-delay bounds (see ../fpu/CDC_CONTRACT.md).
    (* ASYNC_REG = "TRUE" *) reg [1 : 0] cpu_reset_sync, soc_reset_sync;
    generate
        if (EXTERNAL_RESETS)
        begin : external_resets
            // Caller guarantees common asynchronous assertion and independent,
            // locally synchronized release. Avoid duplicating reset clock nets.
            assign cpu_reset = cpu_reset_in;
            assign soc_reset = soc_reset_in;
        end
        else
        begin : internal_resets
            always @(posedge cpu_clk or posedge reset)
                if (reset)
                    cpu_reset_sync <= 2'b11;
                else
                    cpu_reset_sync <= {cpu_reset_sync[0], 1'b0};
            always @(posedge soc_clk or posedge reset)
                if (reset)
                    soc_reset_sync <= 2'b11;
                else
                    soc_reset_sync <= {soc_reset_sync[0], 1'b0};
            assign cpu_reset = cpu_reset_sync[1];
            assign soc_reset = soc_reset_sync[1];
        end
    endgenerate

    reg request_toggle, response_toggle;
    (* ASYNC_REG = "TRUE" *) reg request_meta, request_sync;
    (* ASYNC_REG = "TRUE" *) reg response_meta, response_sync;
    reg [68 : 0] request_hold, request_capture;
    reg [32 : 0] response_hold, response_capture;
    reg request_seen, response_seen;
    localparam C_IDLE = 0, C_WAIT = 1, C_CAPTURE = 2, C_RESPONSE = 3;
    localparam M_IDLE = 0, M_CAPTURE = 1, M_ISSUE = 2, M_WAIT = 3;
    reg [1 : 0] cpu_state, soc_state;

    assign c_req_ready = !cpu_reset && cpu_state == C_IDLE;
    assign c_rsp_valid = !cpu_reset && cpu_state == C_RESPONSE;
    assign {c_rsp_error, c_rsp_rdata} = response_capture;
    assign m_req_valid = !soc_reset && soc_state == M_ISSUE;
    assign {m_req_write, m_req_be, m_req_address, m_req_wdata} = request_capture;
    assign m_rsp_ready = !soc_reset && soc_state == M_WAIT;

    // Only the toggles pass through synchronizers. Each source payload remains
    // unchanged until the destination has captured it and completed the round trip.
    always @(posedge cpu_clk or posedge cpu_reset)
    begin
        if (cpu_reset)
        begin
            response_meta <= 0;
            response_sync <= 0;
            request_toggle <= 0;
            request_hold <= 0;
            response_seen <= 0;
            response_capture <= 0;
            cpu_state <= C_IDLE;
        end
        else
        begin
            response_meta <= response_toggle;
            response_sync <= response_meta;
            case (cpu_state)
                C_IDLE:
                    if (c_req_valid)
                    begin
                        request_hold <= {c_req_write, c_req_be, c_req_address, c_req_wdata};
                        request_toggle <= !request_toggle;
                        cpu_state <= C_WAIT;
                    end
                C_WAIT:
                    if (response_sync != response_seen)
                        cpu_state <= C_CAPTURE;
                C_CAPTURE: begin
                    response_capture <= response_hold;
                    response_seen <= response_sync;
                    cpu_state <= C_RESPONSE;
                end
                C_RESPONSE:
                    if (c_rsp_ready)
                        cpu_state <= C_IDLE;
                default:
                    cpu_state <= C_IDLE;
            endcase
        end
    end
    always @(posedge soc_clk or posedge soc_reset)
    begin
        if (soc_reset)
        begin
            request_meta <= 0;
            request_sync <= 0;
            request_seen <= 0;
            response_toggle <= 0;
            response_hold <= 0;
            request_capture <= 0;
            soc_state <= M_IDLE;
        end
        else
        begin
            request_meta <= request_toggle;
            request_sync <= request_meta;
            case (soc_state)
                M_IDLE:
                    if (request_sync != request_seen)
                        soc_state <= M_CAPTURE;
                M_CAPTURE: begin
                    request_capture <= request_hold;
                    request_seen <= request_sync;
                    soc_state <= M_ISSUE;
                end
                M_ISSUE:
                    if (m_req_ready)
                        soc_state <= M_WAIT;
                M_WAIT:
                    if (m_rsp_valid)
                    begin
                        response_hold <= {m_rsp_error, m_rsp_rdata};
                        response_toggle <= !response_toggle;
                        soc_state <= M_IDLE;
                    end
                default:
                    soc_state <= M_IDLE;
            endcase
        end
    end
endmodule
