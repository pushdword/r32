`timescale 1ns/1ps
module tb_soc;
 reg clk=0,sys=0,pixel_clk=0;always #10 clk=~clk;always #16.666667 sys=~sys;
 wire mode;always begin #((mode===1'b1)?7.692308:12.5)pixel_clk=~pixel_clk;end
 reg reset=1,system_reset=1,pixel_reset=1,rx=1;wire tx;
 wire initialized,rank,ras_n,cas_n,we_n,oe,halt,tr;wire [12:0] address;wire [1:0] bank,dqm;wire [15:0] dout;tri [15:0] dq;
 wire [26:0] pixel;wire sd_sck,sd_mosi,sd_cs_n;wire [5:0] pmod_outputs;wire [31:0] tpc,tcause,taddress;
 assign dq=oe?dout:16'hzzzz;
 r32_soc dut(clk,reset,sys,system_reset,rx,tx,initialized,rank,address,bank,ras_n,cas_n,we_n,dqm,dout,oe,dq,
  pixel_clk,pixel_reset,1'b1,pixel,4'hf,pmod_outputs,mode,sd_sck,sd_mosi,sd_cs_n,1'b1,1'b0,halt,tr,tpc,tcause,taddress);
 wire model_oe;wire [31:0] reads,writes,refs0,refs1;
 w9825g6kh_model ram(~sys,rank,address,bank,ras_n,cas_n,we_n,dqm,dq,oe,initialized,model_oe,reads,writes,refs0,refs1);
 integer cycles=0;reg [7:0] ch;reg [2047:0] linebuf=0;integer passes=0;
 always @(posedge clk)begin cycles<=cycles+1;if(cycles>10000000)$fatal(1,"SoC timeout pc=%x",dut.cpu.fetch_pc);if(tr)$fatal(1,"SoC trap pc=%x cause=%x address=%x",tpc,tcause,taddress);end
 initial begin repeat(8)@(negedge clk);reset=0;repeat(4)@(negedge sys);system_reset=0;repeat(8)@(negedge pixel_clk);pixel_reset=0;end
 initial forever begin
  @(negedge tx);repeat(390)@(posedge sys);
  for(integer i=0;i<8;i=i+1)begin ch[i]=tx;repeat(260)@(posedge sys);end
  if(tx!==1)$fatal(1,"UART stop");$write("%c",ch);$fflush();
  if(ch==10)begin
   if(linebuf=="R32 SOC READY ISA1 ABI1 BAUD115200")begin
    if(reads<64||writes<64||refs0<8||refs1<8||!mode)$fatal(1,"Missing SDRAM/HDMI activity");
    $display("PASS R32 SOC CPU50 SYS30 MMU SDRAM HDMI reads=%0d writes=%0d cycles=%0d",reads,writes,cycles);$finish;
   end
   linebuf=0;
  end else if(ch!=13)linebuf={linebuf[2039:0],ch};
 end
endmodule
