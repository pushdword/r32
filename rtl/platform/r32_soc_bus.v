// SPDX-License-Identifier: MIT
// Single physical target bus with independent CPU instruction/data response slots.
// A held fetch response must not block a data access needed to drain the pipeline.
module r32_soc_bus # (parameter INIT_FILE="firmware.hex",parameter CLKS_PER_BIT=260)(
 input wire clk,reset,uart_rx,output wire uart_tx,
 input wire iv,output wire ir,input wire [31:0] ia,output reg rv,input wire rr,output reg [31:0] id,output reg ie,
 input wire dv,output wire dr,input wire [31:0] da,dd,input wire [3:0] db,input wire dw,
 output reg ds,input wire dsr,output reg [31:0] rd,output reg de,
 output wire timer_irq,input wire timer_accept,output wire ipi_irq,input wire ipi_accept,output wire uart_irq,
 output wire sdram_init_done,output wire sdram_rank,output wire [12:0] sdram_address,output wire [1:0] sdram_bank,
 output wire sdram_ras_n,sdram_cas_n,sdram_we_n,output wire [1:0] sdram_dqm,
 output wire [15:0] sdram_dq_out,output wire sdram_dq_oe,input wire [15:0] sdram_dq_in,
 input wire pixel_clk,pixel_reset,video_locked,output wire [26:0] pixel,
 input wire [3:0] pmod_inputs,output wire [5:0] pmod_outputs,
 output wire video_mode1024,output wire sd_sck,sd_mosi,sd_cs_n,input wire sd_miso,sd_cd_n
);
 reg [1:0] state;reg owner;reg [31:0] address,data;reg [3:0] be;reg writing;
 wire choose_d=dv&&!ds;
 assign dr=!reset&&state==0&&choose_d;
 assign ir=!reset&&state==0&&!choose_d&&!rv;
 wire [2:0] target=address[31:26]==6'b000100 ? 1:address[31:12]==20'hf0001 ? 2:address[31:12]==20'hf0002 ? 3:address[31:15]==17'h1e002 ? 4:address[31:12]==20'hf0004 ? 5:address[31:12]==20'hf0006 ? 6:address[31:12]==20'hf0007 ? 7:0;
 wire [7:0] ready,valid,error;wire [31:0] values[0:7];wire [7:0] requests,consume;
 for(genvar n=0;n<8;n=n+1)begin:route
  assign requests[n]=state==1&&target==n&&!reset;
  assign consume[n]=state==2&&target==n&&!reset;
 end
 x32_bram_uart_fifo_bus #(.RAM_WORDS(8192),.INIT_FILE(INIT_FILE),.CLKS_PER_BIT(CLKS_PER_BIT)) boot_uart(clk,reset,uart_rx,uart_tx,
  requests[0],ready[0],address,data,be,writing,valid[0],consume[0],values[0],error[0],uart_irq);
 x32_sdram_controller #(.INIT_CYCLES(6000),.REFRESH_CYCLES(150),.OPEN_ROW(1)) dram(clk,reset,requests[1],ready[1],address,data,be,writing,valid[1],consume[1],values[1],error[1],sdram_init_done,
  sdram_rank,sdram_address,sdram_bank,sdram_ras_n,sdram_cas_n,sdram_we_n,sdram_dqm,sdram_dq_out,sdram_dq_oe,sdram_dq_in);
 x32_timer #(.CLOCK_HZ(30000000)) timer(clk,reset,requests[2],ready[2],address[4:0],data,be,writing,valid[2],consume[2],values[2],error[2],timer_irq,timer_accept);
 wire [31:0] hwdt_data;assign values[3]=address[11:2]==14 ? 32'd50000000 : hwdt_data;
 x32_hw_table #(.RAM_WORDS(8192),.CLOCK_HZ(30000000),.ENABLE_BOARD_IO(1),.ENABLE_VIDEO_MODES(1),.ENABLE_PMOD(1)) hwdt(clk,reset,requests[3],ready[3],address[11:0],data,be,writing,valid[3],consume[3],hwdt_data,error[3]);
 x32_text_video_ext video(clk,reset,requests[4],ready[4],address[14:0],data,be,writing,valid[4],consume[4],values[4],error[4],pixel_clk,pixel_reset,video_locked,pixel,video_mode1024);
 x32_spi #(.CLOCK_HZ(30000000)) spi(clk,reset,requests[5],ready[5],address[4:0],data,be,writing,valid[5],consume[5],values[5],error[5],sd_sck,sd_mosi,sd_cs_n,sd_miso,sd_cd_n);
 wire [1:0] ipi;assign ipi_irq=ipi[0];wire unused_run;wire [31:0] unused_pc,unused_sp;
 x32_smp_control #(.CORE_COUNT(1)) smp(clk,reset,requests[6],ready[6],1'b0,address[5:0],data,be,writing,
  valid[6],consume[6],values[6],error[6],unused_run,unused_pc,unused_sp,1'b1,1'b0,32'b0,ipi,{1'b0,ipi_accept});
 x32_pmod_devices #(.CLOCK_HZ(30000000)) pmod(clk,reset,requests[7],ready[7],address[5:0],data,be,writing,
  valid[7],consume[7],values[7],error[7],pmod_inputs,pmod_outputs);
 always @(posedge clk)begin
  if(reset)begin state<=0;owner<=0;address<=0;data<=0;be<=0;writing<=0;rv<=0;ds<=0;id<=0;rd<=0;ie<=0;de<=0;end
  else begin
   if(rr)rv<=0;if(dsr)ds<=0;
   case(state)
    0:if(dr||iv&&ir)begin state<=1;owner<=dr;address<=dr ? da:ia;data<=dr&&dw ? dd:0;be<=dr ? db:4'hf;writing<=dr&&dw;end
    1:if(ready[target])state<=2;
    2:if(valid[target])begin
     state<=0;
     if(owner)begin ds<=1;rd<=values[target];de<=error[target];end
     else begin rv<=1;id<=values[target];ie<=error[target];end
    end
    default:state<=0;
   endcase
  end
 end
endmodule
