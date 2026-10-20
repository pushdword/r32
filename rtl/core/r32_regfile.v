// SPDX-License-Identifier: MIT
// Two replicated synchronous 1R/1W banks; explicit collision forwarding.
// No reset loop touches RAM. A written mask gives deterministic reset reads.
module r32_regfile(
 input wire clk,reset,read_enable,input wire [4:0] ra,rb,
 output reg [31:0] qa,qb,
 input wire write_enable,input wire [4:0] wd,input wire [31:0] value
);
 (* ram_style="block",syn_ramstyle="block_ram" *) reg [31:0] bank_a[0:31];
 (* ram_style="block",syn_ramstyle="block_ram" *) reg [31:0] bank_b[0:31];
 reg [31:0] written; reg [4:0] held_a,held_b;
 always @(posedge clk)begin
   if(reset)begin written<=0;qa<=0;qb<=0;held_a<=0;held_b<=0;end
   else begin
     if(write_enable&&wd!=0)begin bank_a[wd]<=value;bank_b[wd]<=value;written[wd]<=1;end
     if(read_enable)begin
       held_a<=ra;held_b<=rb;
       qa<=ra==0?0:(write_enable&&wd==ra)?value:written[ra]?bank_a[ra]:0;
       qb<=rb==0?0:(write_enable&&wd==rb)?value:written[rb]?bank_b[rb]:0;
     end else if(write_enable&&wd!=0)begin
       if(held_a==wd)qa<=value;
       if(held_b==wd)qb<=value;
     end
   end
 end
endmodule
