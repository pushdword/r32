// SPDX-License-Identifier: MIT
// Same TXT2, PLLA/DCS/CLKDIV, TMDS and OSER10 configuration as X32.
module r32_tang25k_soc_top #(parameter INIT_FILE="firmware.hex")(
 input wire clk,reset_button,uart_rx,output wire uart_tx,
 output wire sdram_clk,sdram_rank,output wire [12:0] sdram_address,output wire [1:0] sdram_bank,
 output wire sdram_ras_n,sdram_cas_n,sdram_we_n,output wire [1:0] sdram_dqm,inout wire [15:0] sdram_dq,
 output wire sd_sck,sd_mosi,sd_cs_n,input wire sd_miso,sd_cd_n,
 output wire eth_sck,eth_mosi,eth_cs_n,eth_reset_n,input wire eth_miso,eth_int_n,inout wire rtc_scl,rtc_sda,
 output wire tmds_clk_p,tmds_clk_n,output wire [2:0] tmds_data_p,tmds_data_n
);
 reg [15:0] power_on;reg button_meta,button_sync;
 initial begin power_on=16'hffff;button_meta=0;button_sync=0;end
 always @(posedge clk)begin if(power_on!=0)power_on<=power_on-1'b1;button_meta<=reset_button;button_sync<=button_meta;end
 wire board_reset=power_on!=0||button_sync;
 wire system_clk,system_locked;wire common_reset=board_reset||!system_locked;
 x32_tang25k_system_clock system_clock(clk,power_on!=0,system_locked,system_clk);
 reg [2:0] cpu_release=3'b111,system_release=3'b111;
 always @(posedge clk or posedge common_reset)begin if(common_reset)cpu_release<=3'b111;else cpu_release<={cpu_release[1:0],1'b0};end
 always @(posedge system_clk or posedge common_reset)begin if(common_reset)system_release<=3'b111;else system_release<={system_release[1:0],1'b0};end
 wire reset=cpu_release[2],system_reset=system_release[2];
 wire locked,serializer_clk,pixel_clk,video_mode1024;wire [26:0] pixel;
 x32_tang25k_video_modes clocks(clk,board_reset,video_mode1024,locked,serializer_clk,pixel_clk);
 wire pixel_reset_async=board_reset||!locked;reg [2:0] pixel_reset_pipe=3'b111;
 always @(posedge pixel_clk or posedge pixel_reset_async)begin
  if(pixel_reset_async)pixel_reset_pipe<=3'b111;else pixel_reset_pipe<={pixel_reset_pipe[1:0],1'b0};
 end
 wire pixel_reset=pixel_reset_pipe[2];
 wire [15:0] dq_out;wire dq_oe;assign sdram_dq=dq_oe?dq_out:16'hzzzz;assign sdram_clk=~system_clk;
 wire [5:0] pmod_outputs;assign {eth_reset_n,eth_cs_n,eth_mosi,eth_sck}=pmod_outputs[3:0];
 assign rtc_scl=pmod_outputs[4]?1'b0:1'bz;assign rtc_sda=pmod_outputs[5]?1'b0:1'bz;
 wire initialized,halted,trap;wire [31:0] tpc,tcause,taddress;
 r32_soc #(.INIT_FILE(INIT_FILE)) soc(clk,reset,system_clk,system_reset,uart_rx,uart_tx,
  initialized,sdram_rank,sdram_address,sdram_bank,sdram_ras_n,sdram_cas_n,sdram_we_n,sdram_dqm,dq_out,dq_oe,sdram_dq,
  pixel_clk,pixel_reset,locked,pixel,{eth_int_n,rtc_sda,rtc_scl,eth_miso},pmod_outputs,video_mode1024,sd_sck,sd_mosi,sd_cs_n,sd_miso,sd_cd_n,halted,trap,tpc,tcause,taddress);
 wire [9:0] symbols[0:2];wire [2:0] serial;
 x32_tmds blue(pixel_clk,pixel_reset,pixel[26],pixel[7:0],pixel[25:24],symbols[0]);
 x32_tmds green(pixel_clk,pixel_reset,pixel[26],pixel[15:8],2'b0,symbols[1]);
 x32_tmds red(pixel_clk,pixel_reset,pixel[26],pixel[23:16],2'b0,symbols[2]);
 for(genvar lane=0;lane<3;lane=lane+1)begin:lanes
  OSER10 serializer(.D0(symbols[lane][0]),.D1(symbols[lane][1]),.D2(symbols[lane][2]),.D3(symbols[lane][3]),.D4(symbols[lane][4]),
   .D5(symbols[lane][5]),.D6(symbols[lane][6]),.D7(symbols[lane][7]),.D8(symbols[lane][8]),.D9(symbols[lane][9]),
   .FCLK(serializer_clk),.PCLK(pixel_clk),.RESET(1'b0),.Q(serial[lane]));
  ELVDS_OBUF buffer(.I(serial[lane]),.O(tmds_data_p[lane]),.OB(tmds_data_n[lane]));
 end
 ELVDS_OBUF clock_buffer(.I(pixel_clk),.O(tmds_clk_p),.OB(tmds_clk_n));
endmodule
