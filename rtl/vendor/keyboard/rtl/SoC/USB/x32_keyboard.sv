// Firmware keyboard v1: eight press events, usage+modifiers; no auto-repeat.
// Boot report slots are compared as a set. Held keys do not reopen the menu.
// Overflow is sticky and explicit; full/invalid reports cannot overwrite unread events.
module x32_keyboard(
    input wire clk,reset,input wire req_valid,output wire req_ready,
    input wire [4:0] req_offset,input wire [31:0] req_wdata,input wire [3:0] req_be,input wire req_write,
    output reg rsp_valid,input wire rsp_ready,output reg [31:0] rsp_rdata,output reg rsp_error,
    input wire clock_ready,keyboard_present,protocol_error,report_valid,input wire [63:0] report_data
);
    reg [31:0] queue[0:7];reg [2:0] head,tail;reg [3:0] count;
    reg overflow;reg [31:0] reports;reg [63:0] current,previous;
    reg scanning;reg [2:0] slot;reg last_present;
    wire accept=req_valid&&req_ready;
    wire known=req_offset==0||req_offset==4||req_offset==8||req_offset==12||
               req_offset==16||req_offset==20||req_offset==24||req_offset==28;
    wire invalid=!known||req_offset[1:0]!=0||req_be!=4'hf||(!req_write&&req_wdata!=0)||
                 (req_write&&(req_offset!=12||(|req_wdata[31:2])));
    wire pop=accept&&!invalid&&!req_write&&req_offset==8&&count!=0;
    wire flush=accept&&!invalid&&req_write&&req_offset==12&&req_wdata[0];
    wire clear_error=accept&&!invalid&&req_write&&req_offset==12&&req_wdata[1];
    reg [7:0] usage;reg already,duplicate,rollover;
    always_comb begin
        usage=current[16+slot*8+:8];already=0;duplicate=0;rollover=0;
        for(integer i=0;i<6;i=i+1)begin
            if(previous[16+i*8+:8]==usage)already=1;
            if(i<slot&&current[16+i*8+:8]==usage)duplicate=1;
            if(current[16+i*8+:8]>=1&&current[16+i*8+:8]<=3)rollover=1;
        end
    end
    wire press=scanning&&keyboard_present&&!report_valid&&usage>3&&!already&&!duplicate&&!rollover;
    wire push=press&&(count<8||pop)&&!flush;
    assign req_ready=!reset&&!rsp_valid;
    always @(posedge clk)begin
        if(reset)begin
            head<=0;tail<=0;count<=0;overflow<=0;reports<=0;current<=0;previous<=0;
            scanning<=0;slot<=0;last_present<=0;rsp_valid<=0;rsp_rdata<=0;rsp_error<=0;
        end else begin
            last_present<=keyboard_present;
            if(last_present&&!keyboard_present)begin previous<=0;scanning<=0;end
            if(rsp_valid&&rsp_ready)rsp_valid<=0;
            if(accept)begin
                rsp_valid<=1;rsp_error<=invalid;rsp_rdata<=0;
                if(!invalid&&!req_write)case(req_offset)
                    0:rsp_rdata<=32'h3144424b; // KBD1
                    4:rsp_rdata<={27'b0,protocol_error,overflow,(count!=0),keyboard_present,clock_ready};
                    8:rsp_rdata<=count!=0?queue[head]:0;
                    16:rsp_rdata<=reports;
                    20:rsp_rdata<=current[31:0];24:rsp_rdata<=current[63:32];
                    28:rsp_rdata<=12000000;
                    default:rsp_rdata<=0;
                endcase
            end
            if(report_valid&&keyboard_present)begin
                reports<=reports+1;
                if(scanning)overflow<=1;
                else begin current<=report_data;scanning<=1;slot<=0;end
            end else if(scanning)begin
                if(slot==5)begin scanning<=0;if(!rollover)previous<=current;end
                else slot<=slot+1;
            end
            if(clear_error)overflow<=0;
            if(press&&!push&&!flush)overflow<=1;
            if(flush)begin head<=0;tail<=0;count<=0;overflow<=0;end
            else begin
                if(pop)head<=head+1;
                if(push)begin queue[tail]<={16'b0,current[7:0],usage};tail<=tail+1;end
                case({push,pop})2'b10:count<=count+1;2'b01:count<=count-1;default:count<=count;endcase
            end
        end
    end
endmodule
