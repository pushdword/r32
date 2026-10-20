// SPDX-License-Identifier: MIT
// Retain a response for every accepted CPU request across translation invalidation.
// An older request uses captured privilege/root; the CPU discards killed fetches.
module r32_vm_channel #(parameter INSTRUCTION=0)(
 input wire clk,reset,flush,reservation_clear,supervisor,paging,input wire [31:0] ptbr,
 input wire qv,output wire qr,input wire [31:0] qa,qd,input wire [3:0] qb,input wire qw,lr,sc,
 output wire rv,input wire rr,output reg [31:0] rd,output reg error,page_error,sc_failed,output wire [31:0] translated_address,
 output wire pv,input wire pr,output wire [31:0] pa,pd,output wire [3:0] pb,output wire pw,
 input wire sv,output wire sr,input wire [31:0] sd,input wire se,
 output wire wv,input wire wr,output wire [31:0] wa,input wire wsv,output wire wsr,input wire [31:0] wsd,input wire wse
);
 localparam IDLE=0,TRANSLATE=1,ISSUE=2,WAIT=3,RESPONSE=4;
 reg [2:0] state;reg [31:0] data,address;reg [3:0] be;reg writing,is_lr,is_sc;
 reg reserved;reg [31:0] reserved_word;
 wire mq,mr,mfault,mmio;wire [31:0] mpa,mva;wire [3:0] mcause;
 assign translated_address=address;
 assign qr=state==IDLE&&mq&&!reset;
 assign rv=state==RESPONSE&&!reset;
 assign pv=state==ISSUE&&!reset;assign pa={address[31:2],2'b0};assign pd=data;assign pb=be;assign pw=writing;
 assign sr=state==WAIT&&!reset;
 r32_mmu #(.FLUSH_CANCEL(0)) mmu(clk,reset,flush,qv&&state==IDLE,mq,qa,INSTRUCTION?2'd0:qw?2'd2:2'd1,supervisor,paging,ptbr,
  mr,state==TRANSLATE,mpa,mfault,mcause,mva,mmio,wv,wr,wa,wsv,wsr,wsd,wse);
 always @(posedge clk)begin
  if(reset)begin state<=IDLE;data<=0;address<=0;be<=0;writing<=0;is_lr<=0;is_sc<=0;rd<=0;error<=0;page_error<=0;sc_failed<=0;reserved<=0;reserved_word<=0;end
  else begin
   case(state)
    IDLE:if(qv&&qr)begin data<=qd;be<=qb;writing<=qw;is_lr<=lr;is_sc<=sc;state<=TRANSLATE;sc_failed<=0;if(qw&&!sc)reserved<=0;end
    TRANSLATE:if(mr)begin
     address<=mpa;error<=mfault;page_error<=mfault;rd<=0;
     if(is_sc)reserved<=0;
     if(mfault)state<=RESPONSE;
     else if(is_sc&&(!reserved||reserved_word!={mpa[31:2],2'b0}))begin sc_failed<=1;rd<=1;state<=RESPONSE;end
     else state<=ISSUE;
    end
    ISSUE:if(pr)state<=WAIT;
    WAIT:if(sv)begin rd<=sd;error<=se;page_error<=0;state<=RESPONSE;end
    RESPONSE:if(rr)begin
     if(is_lr&&!error)begin reserved<=1;reserved_word<={address[31:2],2'b0};end
     state<=IDLE;
    end
    default:state<=IDLE;
   endcase
   if(reservation_clear)reserved<=0;
  end
 end
endmodule

// The instruction channel has its own physical bus. Metadata reads and translated
// data requests share the data bus. The arbiter buffers its grant before exposing
// it, so a newly arriving higher priority request cannot change a stalled request.
module r32_translation_bus(
 input wire clk,reset,flush,reservation_clear,supervisor,paging,input wire [31:0] ptbr,
 input wire iv,output wire ir,input wire [31:0] ia,output wire rv,input wire rr,output wire [31:0] id,output wire ie,ipage,
 input wire dv,output wire dr,input wire [31:0] da,dd,input wire [3:0] db,input wire dw,lr,sc,
 output wire ds,input wire dsr,output wire [31:0] rd,output wire de,dpage,sc_failed,output wire [31:0] translated_data_address,
 output wire piv,input wire pir,output wire [31:0] pia,input wire prv,output wire prr,input wire [31:0] pid,input wire pie,
 output wire pdv,input wire pdr,output wire [31:0] pda,pdd,output wire [3:0] pdb,output wire pdw,
 input wire pds,output wire pdsr,input wire [31:0] prd,input wire pde
);
 wire iwv,iwr,iwsv,iwsr,dwv,dwr,dwsv,dwsr;wire [31:0] iwa,dwa;
 wire xv,xr,xw,xsv,xsr;wire [31:0] xa,xd;wire [3:0] xb;
 wire [31:0] unused_i_address;wire unused_i_sc;wire [31:0] unused_i_data;wire [3:0] unused_i_be;wire unused_i_write;
 r32_vm_channel #(.INSTRUCTION(1)) instruction_port(clk,reset,flush,reservation_clear,supervisor,paging,ptbr,
  iv,ir,ia,32'b0,4'hf,1'b0,1'b0,1'b0,rv,rr,id,ie,ipage,unused_i_sc,unused_i_address,
  piv,pir,pia,unused_i_data,unused_i_be,unused_i_write,prv,prr,pid,pie,
  iwv,iwr,iwa,iwsv,iwsr,prd,pde);
 r32_vm_channel data_port(clk,reset,flush,reservation_clear,supervisor,paging,ptbr,
  dv,dr,da,dd,db,dw,lr,sc,ds,dsr,rd,de,dpage,sc_failed,translated_data_address,
  xv,xr,xa,xd,xb,xw,xsv,xsr,prd,pde,dwv,dwr,dwa,dwsv,dwsr,prd,pde);
 reg [1:0] state,owner;reg [31:0] address,data;reg [3:0] be;reg writing;
 wire choose_x=xv,choose_d=!xv&&dwv,choose_i=!xv&&!dwv&&iwv;
 assign xr=state==0&&choose_x;assign dwr=state==0&&choose_d;assign iwr=state==0&&choose_i;
 assign pdv=state==1&&!reset;assign pda=address;assign pdd=data;assign pdb=be;assign pdw=writing;
 assign xsv=state==2&&owner==0&&pds;assign dwsv=state==2&&owner==1&&pds;assign iwsv=state==2&&owner==2&&pds;
 assign pdsr=state==2&&(owner==0?xsr:owner==1?dwsr:iwsr);
 always @(posedge clk)begin
  if(reset)begin state<=0;owner<=0;address<=0;data<=0;be<=0;writing<=0;end
  else case(state)
   0:if(xv||dwv||iwv)begin state<=1;owner<=choose_x?0:choose_d?1:2;address<=choose_x?xa:choose_d?dwa:iwa;data<=choose_x?xd:0;be<=choose_x?xb:4'hf;writing<=choose_x&&xw;end
   1:if(pdr)state<=2;
   2:if(pds&&pdsr)state<=0;
   default:state<=0;
  endcase
 end
endmodule
