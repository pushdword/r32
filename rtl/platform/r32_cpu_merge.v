// SPDX-License-Identifier: MIT
// One physical master with separate I/D reply buffers. CPU side of the clock bridge.
module r32_cpu_merge(
 input wire clk,reset,
 input wire iv,output wire ir,input wire [31:0] ia,output reg rv,input wire rr,output reg [31:0] id,output reg ie,
 input wire dv,output wire dr,input wire [31:0] da,dd,input wire [3:0] db,input wire dw,
 output reg ds,input wire dsr,output reg [31:0] rd,output reg de,
 output wire qv,input wire qr,output reg [31:0] qa,qd,output reg [3:0] qb,output reg qw,
 input wire sv,output wire sr,input wire [31:0] sd,input wire se
);
 reg [1:0] state;reg owner;
 wire choose_d=dv&&!ds;
 assign dr=!reset&&state==0&&choose_d;assign ir=!reset&&state==0&&!choose_d&&!rv;
 assign qv=state==1&&!reset;assign sr=state==2&&!reset;
 always @(posedge clk)begin
  if(reset)begin state<=0;owner<=0;rv<=0;id<=0;ie<=0;ds<=0;rd<=0;de<=0;qa<=0;qd<=0;qb<=0;qw<=0;end
  else begin
   if(rr)rv<=0;if(dsr)ds<=0;
   case(state)
    0:if(dr||iv&&ir)begin state<=1;owner<=dr;qa<=dr?da:ia;qd<=dr&&dw?dd:0;qb<=dr?db:4'hf;qw<=dr&&dw;end
    1:if(qr)state<=2;
    2:if(sv)begin state<=0;if(owner)begin ds<=1;rd<=sd;de<=se;end else begin rv<=1;id<=sd;ie<=se;end end
    default:state<=0;
   endcase
  end
 end
endmodule

// Level notifications cross into the CPU; each taken interrupt returns a toggle.
// Acknowledgement cannot be lost when the receiving clock is slower.
module r32_irq_cdc(input wire cpu_clk,soc_clk,cpu_reset,soc_reset,
 input wire [2:0] pending,input wire [2:0] accepted,output wire [2:0] cpu_pending,output wire [2:0] soc_accepted);
 (* ASYNC_REG="TRUE" *) reg [2:0] irq_meta,irq_sync,ack_meta,ack_sync;
 reg [2:0] ack_toggle,ack_seen;
 assign cpu_pending=irq_sync;assign soc_accepted=ack_sync^ack_seen;
 always @(posedge cpu_clk)begin
  if(cpu_reset)begin irq_meta<=0;irq_sync<=0;ack_toggle<=0;end
  else begin irq_meta<=pending;irq_sync<=irq_meta;ack_toggle<=ack_toggle^accepted;end
 end
 always @(posedge soc_clk)begin
  if(soc_reset)begin ack_meta<=0;ack_sync<=0;ack_seen<=0;end
  else begin ack_meta<=ack_toggle;ack_sync<=ack_meta;ack_seen<=ack_sync;end
 end
endmodule
