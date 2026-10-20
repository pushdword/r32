// Mode0 SPI: legacy DIV0/CS4/DATA8/STATUS12/CLOCK16/ABORT20 preserved.
// RXBLOCK24 reads SBF1, START=bit31|length1..512. FIFO_POP28 returns LE DWORD.
// STATUS: CAP31, FIFOwords15:8, CRC_OK4/DONE3 sticky until START/ABORT/reset,
// card1, busy0. The engine receives payload+2CRC bytes; firmware owns CS.
// Opt-in TX extension in this private implementation: STATUS.bit30; DWORD
// writes28 preload the same512B RAM, START24=bit30|length emits data+HWCRC16.
// RAW_BLOCK opts into SBR1: exactly length payload bytes, with no CRC clocks.
// STATUS.bit29 identifies raw mode; CRC_OK remains clear in that mode.
module x32_spi #(parameter [31:0] CLOCK_HZ=50000000, parameter ENABLE_RX_BLOCK=1,parameter ENABLE_TX_BLOCK=1,parameter RAW_BLOCK=0)(
    input wire clk,reset,req_valid,output wire req_ready,
    input wire [4:0] req_offset,input wire [31:0] req_wdata,
    input wire [3:0] req_be,input wire req_write,
    output reg rsp_valid,input wire rsp_ready,output reg [31:0] rsp_rdata,
    output reg rsp_error,output reg sck,mosi,cs_n,input wire miso,card_detect_n
);
    reg [7:0] divider,count,rx,last_rx;reg [6:0] tx;
    reg [2:0] bit_index;
    reg busy,cd_meta,cd_sync;
    reg block_active,block_done,block_crc_ok;
    localparam TX_ENABLED=ENABLE_RX_BLOCK&&ENABLE_TX_BLOCK;
    localparam TX_LOAD_BITS=RAW_BLOCK?3:2;
    reg block_tx;reg [TX_LOAD_BITS-1:0] tx_load;
    reg [1:0] block_phase,pack_index;
    reg [9:0] payload_left;
    // rx_* naming also keeps every direct MISO sample in the existing IO bound.
    reg [15:0] rx_block_crc;
    reg [7:0] wire_crc_hi;
    // Unreset bytes are used only after a prior byte in this same word.
    // START/ABORT/reset restore index0; partial words zero unused lanes.
    reg [7:0] pack0,pack1,pack2;
    reg [6:0] fifo_wr,fifo_rd;
    reg [7:0] fifo_count;
    reg fifo_read_pending;
    reg [31:0] fifo_read_data;
    // RAW-only halfword adapter. Legacy memory/control remains unchanged.
    reg write_pending,write_bus;
    reg [15:0] write_high,read_low,fifo_half;
    reg [1:0] read_phase;
    reg raw_finish_pending;
    wire abort_now,fifo_put,fifo_get;
    wire put_complete=RAW_BLOCK?(write_pending&&!abort_now):fifo_put;
    wire get_complete=RAW_BLOCK?(read_phase==2&&!abort_now):fifo_get;
    wire abort_request=req_write&&req_offset==20&&req_wdata==1&&req_be==15;
    wire internal_memory_busy=write_pending||read_phase!=0;
    wire memory_abort_ok=abort_request&&!write_bus&&!fifo_read_pending;
    wire known=req_offset==0||req_offset==4||req_offset==8||req_offset==12||
        req_offset==16||req_offset==20||(ENABLE_RX_BLOCK&&(req_offset==24||req_offset==28));
    wire tx_start=TX_ENABLED&&req_wdata[30]&&!req_wdata[31];
    wire invalid_start=(!req_wdata[31]&&!tx_start)||(req_wdata[31]&&req_wdata[30])||req_wdata[29:10]!=0||req_wdata[9:0]==0||
        req_wdata[9:0]>512||busy||cs_n||(tx_start?(!block_tx||fifo_count!=((req_wdata[9:0]+10'd3)>>2)):fifo_count!=0);
    wire invalid=req_offset[1:0]!=0||!known||req_be!=4'hf||(!req_write&&req_wdata!=0)||
        (!req_write&&req_offset==28&&(fifo_count==0||block_tx))||
        (req_write&&((busy&&req_offset!=20)||req_offset==12||req_offset==16||
         (req_offset==28&&(!TX_ENABLED||cs_n||fifo_count==128||(!block_tx&&fifo_count!=0)))||
         (req_offset==0&&(req_wdata==0||req_wdata>255))||
         (req_offset==4&&req_wdata>1)||(req_offset==8&&req_wdata>255)||(req_offset==20&&req_wdata!=1)||
         (req_offset==24&&invalid_start)));
    assign req_ready=!reset&&!rsp_valid&&!fifo_read_pending&&
                     (!RAW_BLOCK||!internal_memory_busy||memory_abort_ok);
    wire accepted=req_valid&&req_ready;
    assign abort_now=accepted&&req_write&&req_offset==20&&!invalid;
    wire block_byte_end=ENABLE_RX_BLOCK&&busy&&block_active&&count==0&&sck&&bit_index==0&&!abort_now;
    wire fifo_push=block_byte_end&&!block_tx&&block_phase==0&&(pack_index==3||payload_left==1);
    wire fifo_pop=ENABLE_RX_BLOCK&&accepted&&!req_write&&req_offset==28&&!invalid;
    wire tx_fifo_push=TX_ENABLED&&accepted&&req_write&&req_offset==28&&!invalid;
    wire tx_fifo_pop=TX_ENABLED&&block_active&&block_tx&&tx_load==1&&!abort_now;
    assign fifo_put=fifo_push||tx_fifo_push;
    assign fifo_get=fifo_pop||tx_fifo_pop;
    reg [31:0] fifo_push_word;
    wire [31:0] incoming_word=tx_fifo_push?req_wdata:fifo_push_word;
    always_comb begin
        case(pack_index)
            0:fifo_push_word={24'b0,rx};
            1:fifo_push_word={16'b0,rx,pack0};
            2:fifo_push_word={8'b0,rx,pack1,pack0};
            3:fifo_push_word={rx,pack2,pack1,pack0};
        endcase
    end
    generate if(ENABLE_RX_BLOCK)begin: rx_block_storage
    if(RAW_BLOCK)begin: halfwords
        reg [15:0] fifo_mem16 [0:255];
        // One syntactic read/write port lets Gowin infer one 16-bit BSRAM.
        // New low halves keep priority over the pending high halves.
        wire mem_write=fifo_put||write_pending;
        wire [7:0] mem_waddr={fifo_wr,!fifo_put};
        wire [15:0] mem_wdata=fifo_put?incoming_word[15:0]:write_high;
        wire mem_read=fifo_get||read_phase==1;
        wire [7:0] mem_raddr={fifo_rd,!fifo_get};
        always @(posedge clk)begin
            if(!reset&&!abort_now)begin
                if(mem_write)fifo_mem16[mem_waddr]<=mem_wdata;
                if(mem_read)fifo_half<=fifo_mem16[mem_raddr];
            end
        end
    end else begin: words
        reg [31:0] fifo_mem [0:127];
    always @(posedge clk)begin
        if(fifo_put&&!reset)fifo_mem[fifo_wr]<=tx_fifo_push?req_wdata:fifo_push_word;
        if(fifo_get)fifo_read_data<=fifo_mem[fifo_rd];
    end
    end
    end endgenerate
    always @(posedge clk)begin
        if(reset)begin
            divider<=125;count<=0;tx<=0;rx<=0;last_rx<=8'hff;bit_index<=7;
            busy<=0;sck<=0;mosi<=1;cs_n<=1;cd_meta<=1;cd_sync<=1;
            block_active<=0;block_done<=0;block_crc_ok<=0;block_phase<=0;
            block_tx<=0;tx_load<=0;
            payload_left<=0;rx_block_crc<=0;wire_crc_hi<=0;pack_index<=0;
            fifo_wr<=0;fifo_rd<=0;fifo_count<=0;fifo_read_pending<=0;
            write_pending<=0;write_bus<=0;read_phase<=0;raw_finish_pending<=0;
            rsp_valid<=0;rsp_rdata<=0;rsp_error<=0;
        end else begin
            cd_meta<=card_detect_n;cd_sync<=cd_meta;
            if(rsp_valid&&rsp_ready)rsp_valid<=0;
            if(RAW_BLOCK)begin
                if(fifo_put)begin
                    write_pending<=1;write_high<=incoming_word[31:16];write_bus<=tx_fifo_push;
                end
                if(put_complete)begin
                    write_pending<=0;write_bus<=0;
                    if(write_bus)begin rsp_valid<=1;rsp_error<=0;rsp_rdata<=0;end
                    if(raw_finish_pending)begin raw_finish_pending<=0;busy<=0;block_done<=1;end
                end
                if(fifo_get)read_phase<=1;
                else if(read_phase==1)begin read_low<=fifo_half;read_phase<=2;end
                else if(read_phase==2)begin
                    read_phase<=0;fifo_read_data<={fifo_half,read_low};
                    if(fifo_read_pending)begin
                        rsp_rdata<={fifo_half,read_low};rsp_valid<=1;fifo_read_pending<=0;
                    end
                end
            end else begin
            if(fifo_read_pending)begin
                rsp_rdata<=fifo_read_data;rsp_valid<=1;fifo_read_pending<=0;
            end
            end
            if(put_complete)fifo_wr<=fifo_wr+1'b1;
            if(get_complete)fifo_rd<=fifo_rd+1'b1;
            case({put_complete,get_complete})
                2'b10:fifo_count<=fifo_count+1'b1;
                2'b01:fifo_count<=fifo_count-1'b1;
                default:begin end
            endcase
            if(req_valid&&req_ready)begin
                rsp_valid<=1;rsp_error<=invalid;rsp_rdata<=0;
                if(!invalid)begin
                    if(req_write)case(req_offset)
                        0:divider<=req_wdata[7:0];
                        4:cs_n<=req_wdata[0];
                        8:begin tx<=req_wdata[6:0];rx<=0;bit_index<=7;
                            mosi<=req_wdata[7];busy<=1;count<=divider-1'b1;sck<=0;end
                        20:begin busy<=0;sck<=0;mosi<=1;cs_n<=1;count<=0;last_rx<=8'hff;
                            block_active<=0;block_done<=0;block_crc_ok<=0;block_phase<=0;
                            block_tx<=0;tx_load<=0;
                            payload_left<=0;rx_block_crc<=0;pack_index<=0;
                            fifo_wr<=0;fifo_rd<=0;fifo_count<=0;
                            write_pending<=0;write_bus<=0;read_phase<=0;raw_finish_pending<=0;end
                        24:if(ENABLE_RX_BLOCK)begin block_active<=1;block_done<=0;block_crc_ok<=0;block_phase<=0;
                            block_tx<=tx_start;tx_load<=tx_start?1:0;
                            payload_left<=req_wdata[9:0];rx_block_crc<=0;wire_crc_hi<=0;pack_index<=0;
                            tx<=7'h7f;rx<=0;bit_index<=7;mosi<=1;busy<=1;count<=divider-1'b1;sck<=0;end
                        28:if(TX_ENABLED)begin block_tx<=1;block_done<=0;block_crc_ok<=0;
                            if(RAW_BLOCK)rsp_valid<=0;end
                        default:begin end
                    endcase
                    else case(req_offset)
                        0:rsp_rdata<={24'b0,divider};
                        4:rsp_rdata<={31'b0,cs_n};
                        8:rsp_rdata<={24'b0,last_rx};
                        12:rsp_rdata<=ENABLE_RX_BLOCK?{1'b1,1'(TX_ENABLED),1'(RAW_BLOCK),13'b0,fifo_count,3'b0,block_crc_ok,block_done,1'b0,!cd_sync,busy}:{30'b0,!cd_sync,busy};
                        16:rsp_rdata<=CLOCK_HZ;
                        24:rsp_rdata<=RAW_BLOCK?32'h31524253:32'h31464253;
                        28:begin rsp_valid<=0;fifo_read_pending<=1;end
                        default:begin end
                    endcase
                end
            end
            if(busy&&!abort_now&&block_tx&&tx_load!=0)begin
                if(tx_load==1)tx_load<=2;
                else if(RAW_BLOCK&&tx_load==2)tx_load<=3;
                else if(RAW_BLOCK&&tx_load==3)tx_load<=4;
                else begin
                    tx_load<=0;tx<=fifo_read_data[6:0];mosi<=fifo_read_data[7];
                    pack0<=fifo_read_data[15:8];pack1<=fifo_read_data[23:16];pack2<=fifo_read_data[31:24];
                    bit_index<=7;pack_index<=0;count<=divider-1'b1;
                end
            end else if(busy&&!abort_now&&(!RAW_BLOCK||!raw_finish_pending))begin
                if(count!=0)count<=count-1'b1;
                else begin
                    count<=divider-1'b1;sck<=!sck;
                    if(!sck)begin
                        rx<={rx[6:0],miso}; // Mode0 rising-edge sample.
                        if(ENABLE_RX_BLOCK&&!RAW_BLOCK&&block_active&&block_phase==0)
                            rx_block_crc<={rx_block_crc[14:0],1'b0}^((rx_block_crc[15]^(block_tx?mosi:miso))?16'h1021:16'h0000);
                    end else if(bit_index==0)begin
                        last_rx<=rx;
                        if(!block_active)begin busy<=0;mosi<=1;end
                        else if(RAW_BLOCK)begin
                            // RAW_BLOCK has no CRC phases. START/reset/ABORT set
                            // phase0, and payload bytes never transition it.
                            if(payload_left==1)begin
                                block_active<=0;block_crc_ok<=0;
                                payload_left<=0;pack_index<=0;mosi<=1;
                                if(block_tx)begin busy<=0;block_done<=1;block_tx<=0;end
                                else begin raw_finish_pending<=1;block_done<=0;end
                            end else begin
                                bit_index<=7;rx<=0;payload_left<=payload_left-1'b1;
                                if(block_tx)begin
                                    if(pack_index==3)begin tx_load<=1;mosi<=1;end
                                    else begin
                                        pack_index<=pack_index+1'b1;mosi<=pack0[7];tx<=pack0[6:0];pack0<=pack1;pack1<=pack2;
                                    end
                                end else begin
                                    tx<=7'h7f;mosi<=1;
                                    case(pack_index)
                                        0:pack0<=rx;
                                        1:pack1<=rx;
                                        2:pack2<=rx;
                                        default:begin end
                                    endcase
                                    if(fifo_push)pack_index<=0;
                                    else pack_index<=pack_index+1'b1;
                                end
                            end
                        end else if(block_phase==2)begin
                            busy<=0;block_active<=0;block_done<=1;
                            block_crc_ok<=!block_tx&&({wire_crc_hi,rx}==rx_block_crc);mosi<=1;block_tx<=0;
                        end else if(block_tx)begin
                            bit_index<=7;rx<=0;
                            if(block_phase==0)begin
                                payload_left<=payload_left-1'b1;
                                if(payload_left==1)begin
                                    block_phase<=1;mosi<=rx_block_crc[15];tx<=rx_block_crc[14:8];
                                end else if(pack_index==3)begin tx_load<=1;mosi<=1;end
                                else begin
                                    pack_index<=pack_index+1'b1;mosi<=pack0[7];tx<=pack0[6:0];pack0<=pack1;pack1<=pack2;
                                end
                            end else begin block_phase<=2;mosi<=rx_block_crc[7];tx<=rx_block_crc[6:0];end
                        end else begin
                            bit_index<=7;rx<=0;tx<=7'h7f;mosi<=1;
                            if(block_phase==0)begin
                                payload_left<=payload_left-1'b1;
                                case(pack_index)
                                    0:pack0<=rx;
                                    1:pack1<=rx;
                                    2:pack2<=rx;
                                    default:begin end
                                endcase
                                if(fifo_push)pack_index<=0;
                                else pack_index<=pack_index+1'b1;
                                if(payload_left==1)block_phase<=1;
                            end else begin wire_crc_hi<=rx;block_phase<=2;end
                        end
                    end
                    else begin bit_index<=bit_index-1'b1;tx<={tx[5:0],1'b1};mosi<=tx[6];end
                end
            end
        end
    end
endmodule
