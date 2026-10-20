// X32 single-outstanding target for two 32 MiB x16 SDR SDRAM ranks.
// Mapping agrees with the Sipeed-referenced f6f62778 controller:
// byte offset [25]=rank, [24:12]=row, [11:10]=bank, [9:1]=column.
// Commands/data change on CPU posedge; the PHY supplies the opposite-edge
// SDRAM clock. DQ input is sampled on CPU posedge after CAS+tAC has elapsed.
// The compatible profile closes every row. OPEN_ROW keeps one row active,
// precharging it before a different row, refresh, or an idle warm reset.
module x32_sdram_controller #(
    parameter [31:0] BASE_ADDRESS=32'h10000000,
    parameter integer INIT_CYCLES=10000, // 200 us at 50 MHz, not shortened in hardware
    parameter integer REFRESH_CYCLES=250, // 5 us + bounded in-flight transaction
    parameter integer CAS_LATENCY=3,
    parameter OPEN_ROW=0,
    parameter integer T_RCD=2,T_RP=2,T_RFC=4,T_MRD=2,T_WR=2,T_RAS=3
)(
    input wire clk,reset,
    input wire req_valid,output wire req_ready,
    input wire [31:0] req_address,req_wdata,input wire [3:0] req_be,input wire req_write,
    output reg rsp_valid,input wire rsp_ready,output reg [31:0] rsp_rdata,output reg rsp_error,
    output reg init_done,
    output reg sdram_rank,output reg [12:0] sdram_address,output reg [1:0] sdram_bank,
    output reg sdram_ras_n,sdram_cas_n,sdram_we_n,output reg [1:0] sdram_dqm,
    output reg [15:0] sdram_dq_out,output reg sdram_dq_oe,input wire [15:0] sdram_dq_in
);
    localparam integer CW=$clog2(INIT_CYCLES+T_RFC+CAS_LATENCY+2);
    localparam integer RW=$clog2(REFRESH_CYCLES+1);
    localparam integer GW=$clog2((T_RAS>T_WR?T_RAS:T_WR)+1);
    localparam [4:0] POWER_WAIT=0,INIT_PRE=1,INIT_REF=2,INIT_MRS=3,INIT_NEXT=4,
        WAIT_TIME=5,IDLE=6,ACTIVATE=7,FIRST=8,READ_FIRST=9,SECOND=10,READ_SECOND=11,
        PRECHARGE=12,RESPOND=13,REFRESH=14,REFRESH_NEXT=15,REFRESH_END=16,
        CLOSE_ROW=17;
    reg [4:0] state,next_state;
    reg [CW-1:0] wait_count;reg [GW-1:0] row_guard,write_guard;
    reg [RW-1:0] refresh_count;
    reg init_rank,refresh_rank,discard_response;reg [3:0] init_refreshes;
    reg [25:2] address;reg [31:0] write_data;reg [3:0] byte_enable;reg write_request;
    reg row_open,open_rank;reg [1:0] open_bank;reg [12:0] open_row;
    reg [4:0] after_close;
    wire same_row=row_open&&open_rank==req_address[25]&&
        open_bank==req_address[11:10]&&open_row==req_address[24:12];
    wire refresh_due=refresh_count>=RW'(REFRESH_CYCLES-1);
    wire invalid=req_address[1:0]!=0||req_be==0||(!req_write&&req_wdata!=0)||
        req_address[31:26]!=BASE_ADDRESS[31:26];
    assign req_ready=!reset&&init_done&&state==IDLE&&!rsp_valid&&!refresh_due;
    // FPGA configuration supplies the power-up state. A CPU reset is a warm
    // interface reset: DRAM has no reset pin, and stopping refresh while an
    // active row is open would violate retention/tRAS(max). Accepted physical
    // operations therefore drain to PRE; their stale responses are discarded.
    initial begin
        state=POWER_WAIT;next_state=IDLE;wait_count=CW'(INIT_CYCLES-1);
        row_guard=0;write_guard=0;refresh_count=0;
        init_rank=0;refresh_rank=0;init_refreshes=0;init_done=0;discard_response=1;
        address=0;write_data=0;byte_enable=0;write_request=0;
        row_open=0;open_rank=0;open_bank=0;open_row=0;after_close=IDLE;
        rsp_valid=0;rsp_rdata=0;rsp_error=0;
        sdram_rank=0;sdram_address=0;sdram_bank=0;
        sdram_ras_n=1;sdram_cas_n=1;sdram_we_n=1;
        sdram_dqm=3;sdram_dq_out=0;sdram_dq_oe=0;
        if(BASE_ADDRESS[25:0]!=0||INIT_CYCLES<1||REFRESH_CYCLES<32||
           CAS_LATENCY!=3||T_RCD<1||T_RP<1||T_RFC<1||T_MRD<2||T_WR<2||T_RAS<1)
            $fatal(1,"Unsupported SDRAM configuration");
    end
    // A generic wait always emits NOP. The extra state transition is
    // deliberately conservative; no command is issued at a minimum's edge.
    task wait_for(input integer cycles,input reg [4:0] following);
        begin wait_count<=CW'(cycles-1);next_state<=following;state<=WAIT_TIME;end
    endtask
    task column_command(input reg high_half);
        begin
            sdram_rank<=address[25];sdram_bank<=address[11:10];
            sdram_address<={4'b0,address[9:2],high_half}; // A10=0: explicit PRE
            sdram_ras_n<=1;sdram_cas_n<=0;sdram_we_n<=!write_request;
            if(write_request)begin
                sdram_dq_oe<=1;
                sdram_dq_out<=high_half?write_data[31:16]:write_data[15:0];
                sdram_dqm<=~(high_half?byte_enable[3:2]:byte_enable[1:0]);
                write_guard<=GW'(T_WR);
            end else sdram_dqm<=0; // Read masking is applied to the response.
        end
    endtask
    always @(posedge clk)begin
        begin
            // Only READ/WRITE/ACT/PRE/REF/MRS states override this NOP.
            sdram_ras_n<=1;sdram_cas_n<=1;sdram_we_n<=1;sdram_dq_oe<=0;
            sdram_dqm<=init_done?2'b00:2'b11;
            if(row_guard!=0)row_guard<=row_guard-1;
            if(write_guard!=0)write_guard<=write_guard-1;
            if(init_done&&!refresh_due)refresh_count<=refresh_count+1;
            if(reset)begin rsp_valid<=0;discard_response<=1;end
            else if(rsp_valid&&rsp_ready)rsp_valid<=0;
            case(state)
                POWER_WAIT:if(wait_count!=0)wait_count<=wait_count-1;else state<=INIT_PRE;
                INIT_PRE:begin
                    sdram_rank<=init_rank;sdram_address<=13'h400;sdram_ras_n<=0;sdram_we_n<=0;
                    init_refreshes<=0;wait_for(T_RP,INIT_REF);
                end
                INIT_REF:begin
                    sdram_rank<=init_rank;sdram_ras_n<=0;sdram_cas_n<=0;
                    init_refreshes<=init_refreshes+1;
                    wait_for(T_RFC,init_refreshes==7?INIT_MRS:INIT_REF);
                end
                INIT_MRS:begin
                    sdram_rank<=init_rank;sdram_bank<=0;sdram_address<=13'h230;
                    // BL1, sequential, CAS3, single-location writes; reserved bits zero.
                    sdram_ras_n<=0;sdram_cas_n<=0;sdram_we_n<=0;wait_for(T_MRD,INIT_NEXT);
                end
                INIT_NEXT:if(!init_rank)begin init_rank<=1;state<=INIT_PRE;end
                          else begin init_done<=1;refresh_count<=0;state<=IDLE;end
                WAIT_TIME:if(wait_count!=0)wait_count<=wait_count-1;else state<=next_state;
                IDLE:begin
                    // Refresh does not wait for rsp_ready: a CPU can hold a reply
                    // indefinitely, but that must never stop DRAM maintenance.
                    if(refresh_due)begin
                        refresh_rank<=0;
                        if(OPEN_ROW&&row_open)begin after_close<=REFRESH;state<=CLOSE_ROW;end
                        else state<=REFRESH;
                    end
                    else if(OPEN_ROW&&reset&&row_open)begin after_close<=IDLE;state<=CLOSE_ROW;end
                    else if(req_valid&&req_ready)begin
                        if(invalid)begin rsp_error<=1;rsp_rdata<=0;rsp_valid<=1;end
                        else begin
                            address<=req_address[25:2];write_data<=req_wdata;
                            byte_enable<=req_be;write_request<=req_write;rsp_rdata<=0;discard_response<=0;
                            if(OPEN_ROW&&same_row)state<=FIRST;
                            else if(OPEN_ROW&&row_open)begin after_close<=ACTIVATE;state<=CLOSE_ROW;end
                            else state<=ACTIVATE;
                        end
                    end
                end
                ACTIVATE:begin
                    sdram_rank<=address[25];sdram_bank<=address[11:10];sdram_address<=address[24:12];
                    row_open<=1;open_rank<=address[25];open_bank<=address[11:10];open_row<=address[24:12];
                    sdram_ras_n<=0;row_guard<=GW'(T_RAS);wait_for(T_RCD,FIRST);
                end
                FIRST:if(byte_enable[1:0]==0)state<=SECOND;
                      else begin
                          column_command(0);
                          if(write_request)state<=SECOND;
                          else begin wait_count<=CW'(CAS_LATENCY);state<=READ_FIRST;end
                      end
                READ_FIRST:if(wait_count!=0)wait_count<=wait_count-1;
                           else begin
                               rsp_rdata[15:0]<={byte_enable[1]?sdram_dq_in[15:8]:8'b0,
                                                  byte_enable[0]?sdram_dq_in[7:0]:8'b0};state<=SECOND;
                           end
                SECOND:if(byte_enable[3:2]==0)state<=OPEN_ROW?RESPOND:PRECHARGE;
                       else begin
                           column_command(1);
                           if(write_request)state<=OPEN_ROW?RESPOND:PRECHARGE;
                           else begin wait_count<=CW'(CAS_LATENCY);state<=READ_SECOND;end
                       end
                READ_SECOND:if(wait_count!=0)wait_count<=wait_count-1;
                            else begin
                                rsp_rdata[31:16]<={byte_enable[3]?sdram_dq_in[15:8]:8'b0,
                                                    byte_enable[2]?sdram_dq_in[7:0]:8'b0};state<=OPEN_ROW?RESPOND:PRECHARGE;
                            end
                PRECHARGE:if(row_guard==0&&write_guard==0)begin
                    sdram_rank<=address[25];sdram_bank<=address[11:10];sdram_address<=0;
                    row_open<=0;
                    sdram_ras_n<=0;sdram_we_n<=0;wait_for(T_RP,RESPOND);
                end
                CLOSE_ROW:if(row_guard==0&&write_guard==0)begin
                    sdram_rank<=open_rank;sdram_bank<=open_bank;sdram_address<=0;
                    row_open<=0;sdram_ras_n<=0;sdram_we_n<=0;wait_for(T_RP,after_close);
                end
                RESPOND:if(!OPEN_ROW||write_guard==0)begin
                    rsp_error<=0;rsp_valid<=!reset&&!discard_response;state<=IDLE;
                end
                REFRESH:begin
                    sdram_rank<=refresh_rank;sdram_ras_n<=0;sdram_cas_n<=0;wait_for(T_RFC,REFRESH_NEXT);
                end
                REFRESH_NEXT:if(!refresh_rank)begin refresh_rank<=1;state<=REFRESH;end
                             else state<=REFRESH_END;
                REFRESH_END:begin refresh_count<=0;state<=IDLE;end
                default:state<=POWER_WAIT;
            endcase
        end
    end
endmodule
