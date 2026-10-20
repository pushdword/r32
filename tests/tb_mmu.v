`timescale 1ns/1ps
module tb_mmu;
 reg clk=0;always #5 clk=~clk;reg reset=1,flush=0;
 reg qv=0,supervisor=1,paging=0;wire qr;reg [31:0] va=0,root=0;reg [1:0] access_kind=0;
 wire rv,fault,uncached;reg rr=0;wire [31:0] pa,fa;wire [3:0] cause;
 wire wv,wrv,wrr;wire [31:0] wa;reg [31:0] wd=0;reg we=0,response=0,pending=0;reg [31:0] held_addr;integer delay=0,cycles=0,walks=0,checks=0;reg permit=1;
 wire wr=permit&&!pending&&!response&&(cycles%4!=0);
 r32_mmu dut(clk,reset,flush,qv,qr,va,access_kind,supervisor,paging,root,rv,rr,pa,fault,cause,fa,uncached,wv,wr,wa,response,wrr,wd,we);
 reg [31:0] memory[0:65535];integer i;
 initial for(i=0;i<65536;i=i+1)memory[i]=0;
 reg stalled=0;reg [31:0] stalled_address;
 always @(posedge clk)begin
  cycles<=cycles+1;if(cycles>2000000)$fatal(1,"MMU timeout");
  if(!reset)begin
   if(stalled&&(!wv||wa!==stalled_address))$fatal(1,"Walker request changed walk_before acceptance");
   stalled<=wv&&!wr;stalled_address<=wa;
   if(wv&&wa[31:24]==8'hf0)$fatal(1,"Metadata read reached MMIO");
   if(wv&&wr)begin
    if(pending||response)$fatal(1,"Two walker reads outstanding");
    pending<=1;held_addr<=wa;delay<=6;walks<=walks+1;
   end
   if(pending)begin
    if(delay!=0)delay<=delay-1;
    else begin
     pending<=0;response<=1;
     we<=!((held_addr<32'h8000)||(held_addr>=32'h10000000&&held_addr<32'h14000000));
     wd<=held_addr>=32'h10000000&&held_addr<32'h10040000 ? memory[(held_addr-32'h10000000)>>2]:0;
    end
   end
   if(response&&wrr)response<=0;
  end
 end
 task fence;
 begin @(negedge clk);flush=1;@(negedge clk);flush=0;wait(qr);end
 endtask
 task request(input [31:0] address,input [1:0] kind,input sup,pg,input [31:0] ptbr);
 begin wait(qr);@(negedge clk);va=address;access_kind=kind;supervisor=sup;paging=pg;root=ptbr;qv=1;@(posedge clk);if(!qr)$fatal(1,"Request not accepted");@(negedge clk);qv=0;end
 endtask
 task translate(input [31:0] address,flags,ptbr,expected_pa,expected_fault,expected_walks);
 integer walk_before;reg [69:0] held;
 begin
  walk_before=walks;request(address,flags[1:0],flags[2],flags[3],ptbr);wait(rv);@(negedge clk);
  if(fault!==expected_fault[0]||(!fault&&pa!==expected_pa)||fa!==address||cause!==(flags[1:0]==0?4'd10:flags[1:0]==1?4'd11:4'd12)||(!fault&&uncached!==(expected_pa[31:24]==8'hf0))||walks-walk_before!==expected_walks)
   $fatal(1,"MMU mismatch check%0d VA=%x flags=%x pa=%x expected=%x fault=%b want=%b walks=%0d want=%0d",checks,address,flags,pa,expected_pa,fault,expected_fault[0],walks-walk_before,expected_walks);
  held={pa,fault,cause,fa,uncached};repeat(5)begin @(negedge clk);if(!rv||held!=={pa,fault,cause,fa,uncached})$fatal(1,"Response changed under backpressure");end
  rr=1;@(negedge clk);rr=0;checks=checks+1;
 end
 endtask
 task cancel(input integer stage);
 integer walk_before;
 begin
  fence();walk_before=walks;permit=stage!=1&&stage!=8;request(32'h00400123,1,1,1,32'h10000000);
  case(stage)
   1:wait(wv&&!wr);
   2:wait(pending);
   3:begin wait(pending);permit=0;wait(wv);end
   4:begin wait(walks==walk_before+2);wait(pending);end
   5:wait(rv);
   6:wait(response);
   7:begin wait(walks==walk_before+2);wait(response);end
   8:begin wait(wv);while(cycles%4==0)@(negedge clk);permit=1;end
  endcase
  @(negedge clk);flush=1;@(negedge clk);flush=0;permit=1;
  while(!qr)begin @(negedge clk);if(rv)$fatal(1,"Cancelled translation produced response");end
  if(pending||response)$fatal(1,"Cancelled metadata read was not drained");
  checks=checks+1;
 end
 endtask
 integer file,status,op;reg [31:0] a,b,c,d,e,f;reg [2047:0] path;
 initial begin
  if(!$value$plusargs("VECTORS=%s",path))$fatal(1,"Missing vectors");file=$fopen(path,"r");if(!file)$fatal(1,"No vector file");
  repeat(4)@(negedge clk);reset=0;
  forever begin
   status=$fscanf(file,"%h %h %h %h %h %h %h\n",op,a,b,c,d,e,f);
   if(status!=7)$fatal(1,"Malformed vector file");
   case(op)
    0:begin $display("PASS R32 MMU checks=%0d walker_reads=%0d cycles=%0d",checks,walks,cycles);$finish;end
    1:memory[(a-32'h10000000)>>2]=b;
    2:fence();
    3:translate(a,b,c,d,e,f);
    4:cancel(a);
    default:$fatal(1,"Invalid vector command");
   endcase
  end
 end
endmodule
