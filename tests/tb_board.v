`timescale 1ns/1ps
module tb_board;
 parameter DIV=8;
 reg clk=0;always #10 clk=~clk;
 reg button=0,rx=1;wire tx;
 r32_tang25k_bringup #(.INIT_FILE("firmware.hex"),.CLKS_PER_BIT(DIV),.POWERUP_BITS(4)) dut(clk,button,rx,tx);
 integer chars=0,ready_count=0,pass_count=0,id_count=0,done_count=0;reg [7:0] byte_in;reg [1023:0] linebuf=0;integer cycles=0;
 always @(posedge clk)begin cycles<=cycles+1;if(cycles>3000000)$fatal(1,"Board timeout");if(dut.tr)$fatal(1,"CPU trap cause=%x pc=%x",dut.tc,dut.tp);end
 initial forever begin
  @(negedge tx);repeat(DIV+DIV/2)@(posedge clk);
  for(integer i=0;i<8;i=i+1)begin byte_in[i]=tx;repeat(DIV)@(posedge clk);end
  if(tx!==1)$fatal(1,"UART stop bit");
  $write("%c",byte_in);chars=chars+1;
  if(byte_in==10)begin
   if(linebuf=="R32 SELFTEST PASS ALU MUL DIV CALL ATOMICS RAM2048 BYTEENABLE")pass_count=pass_count+1;
   if(linebuf=="R32 READY ISA1 ABI1 LE32 CLOCK50M BAUD115200")ready_count=ready_count+1;
   if(linebuf=="R32 ID 52333201 ISA1 ABI1")id_count=id_count+1;
   if(linebuf=="ZR32 DONE")done_count=done_count+1;
   linebuf=0;
  end else if(byte_in!=13)linebuf={linebuf[1015:0],byte_in};
 end
 task send(input [7:0] v);
  begin
   @(negedge clk);rx=0;repeat(DIV)@(negedge clk);
   for(integer i=0;i<8;i=i+1)begin rx=v[i];repeat(DIV)@(negedge clk);end
   rx=1;repeat(DIV*2)@(negedge clk);
  end
 endtask
 initial begin
  wait(ready_count==1);send("?");wait(id_count==1);send("s");wait(pass_count==2);send("Z");repeat(DIV*12)@(negedge clk);send("x");wait(done_count==1);wait(dut.halt);
  if(dut.bus.sticky_framing||dut.bus.sticky_overrun)$fatal(1,"UART receive error");
  button=1;repeat(8)@(negedge clk);button=0;wait(ready_count==2);
  $display("PASS R32 BOARD UART RX TX RESET MEMORY ATOMICS chars=%0d cycles=%0d",chars,cycles);$finish;
 end
endmodule
