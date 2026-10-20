// Opt-in TXT2 controller. Reset mode is the existing800x600/100x37 layout.
// CONTROL bit0 enable, bit1 mode1024. TEXT_GEOMETRY/PIXEL_GEOMETRY are current.
// Window32KiB:6144 cells at+0x100;4096-byte writable Latin1 font at+0x7000.
// MODE is held by the CPU clock domain; board clock manager blanks on switch.
module x32_text_video_ext(
    input wire clk,reset,req_valid,output wire req_ready,input wire [14:0] req_offset,
    input wire [31:0] req_wdata,input wire [3:0] req_be,input wire req_write,
    output reg rsp_valid,input wire rsp_ready,output reg [31:0] rsp_rdata,output reg rsp_error,
    input wire pixel_clk,pixel_reset,pll_locked,output wire [26:0] pixel,output reg mode1024
);
    (* ram_style="block" *) reg [15:0] cells[0:6143];
    (* ram_style="block" *) reg [31:0] font[0:1023];
    initial begin
        for(integer i=0;i<6144;i=i+1)cells[i]=16'h0f20;
        $readmemh("rtl/vendor/platform/rtl/SoC/Video/font_latin1.hex",font);
    end
    reg enabled,lock_meta,lock_sync,frame_meta,frame_sync,frame_previous;
    reg read_pending,held_font;reg [12:0] held_index;reg [15:0] cpu_cell;reg [31:0] cpu_font;
    reg [31:0] frames;reg frame_toggle;
    wire text_access=req_offset>=256&&req_offset<24832;
    wire font_access=req_offset>=15'h7000;
    wire known=text_access||font_access||req_offset==0||req_offset==4||req_offset==8||req_offset==12||req_offset==16||req_offset==20||req_offset==24;
    wire invalid=!known||req_offset[1:0]!=0||req_be!=4'hf||(!req_write&&req_wdata!=0)||
        (req_write&&((!text_access&&!font_access&&req_offset!=16)||(text_access&&|req_wdata[31:16])||
         (req_offset==16&&req_wdata>3)));
    wire [12:0] cpu_index=req_offset[14:2]-13'd64;
    wire [12:0] ram_index=read_pending?held_index:cpu_index;
    wire [9:0] font_index=read_pending?held_index[9:0]:req_offset[11:2];
    always @(posedge clk)begin
        if(req_valid&&req_ready&&!invalid&&text_access&&req_write)begin cells[ram_index]<=req_wdata[15:0];cpu_cell<=req_wdata[15:0];end
        else cpu_cell<=cells[ram_index];
        if(req_valid&&req_ready&&!invalid&&font_access&&req_write)begin font[font_index]<=req_wdata;cpu_font<=req_wdata;end
        else cpu_font<=font[font_index];
    end
    assign req_ready=!reset&&!rsp_valid&&!read_pending;
    always @(posedge clk)begin
        if(reset)begin enabled<=1;mode1024<=0;lock_meta<=0;lock_sync<=0;frame_meta<=0;frame_sync<=0;frame_previous<=0;frames<=0;
            rsp_valid<=0;rsp_rdata<=0;rsp_error<=0;read_pending<=0;held_index<=0;held_font<=0;
        end else begin
            lock_meta<=pll_locked;lock_sync<=lock_meta;frame_meta<=frame_toggle;frame_sync<=frame_meta;frame_previous<=frame_sync;
            if(frame_previous!=frame_sync)frames<=frames+1'b1;
            if(rsp_valid&&rsp_ready)rsp_valid<=0;
            if(read_pending)begin rsp_valid<=1;rsp_rdata<=held_font?cpu_font:{16'b0,cpu_cell};rsp_error<=0;read_pending<=0;end
            if(req_valid&&req_ready)begin
                rsp_valid<=1;rsp_error<=invalid;rsp_rdata<=0;
                if(!invalid)begin
                    if(text_access||font_access)begin
                        if(!req_write)begin read_pending<=1;held_index<=font_access?{3'b0,req_offset[11:2]}:cpu_index;held_font<=font_access;rsp_valid<=0;end
                    end else if(req_write)begin enabled<=req_wdata[0];mode1024<=req_wdata[1];end
                    else case(req_offset)
                        0:rsp_rdata<=32'h31545854; // Preserve BIOS/U-Boot TXT1 identity.
                        4:rsp_rdata<={30'b0,enabled,lock_sync};
                        8:rsp_rdata<=mode1024?32'h00300080:32'h00250064;
                        12:rsp_rdata<=mode1024?32'h03000400:32'h02580320;
                        16:rsp_rdata<={30'b0,mode1024,enabled};
                        20:rsp_rdata<=frames;
                        24:rsp_rdata<=32'h32545854; // TXT2 extension marker, only in HWDT32KiB profile.
                        default:begin end
                    endcase
                end
            end
        end
    end
    reg [10:0] x;reg [9:0] y;reg enable_meta,enable_sync,mode_meta,mode_sync;
    wire active=mode_sync?(x<1024&&y<768):(x<800&&y<600);
    wire visible_text=active&&(mode_sync||y<592);
    wire [12:0] text_index=mode_sync?{y[9:4],x[9:3]}:13'(y[9:4])*13'd100+13'(x[9:3]);
    reg [15:0] character_word;reg [31:0] font_word;reg [2:0] x1,x2;reg [3:0] y1;reg [1:0] font_row;
    reg [7:0] attribute2;reg hs1,vs1,de1,text1,hs2,vs2,de2,text2;
    always @(posedge pixel_clk)begin
        character_word<=cells[visible_text?text_index:13'd0];
        font_word<=font[{character_word[7:0],y1[3:2]}];
    end
    always @(posedge pixel_clk)begin
        if(pixel_reset)begin x<=0;y<=0;frame_toggle<=0;enable_meta<=0;enable_sync<=0;mode_meta<=0;mode_sync<=0;
            x1<=0;x2<=0;y1<=0;font_row<=0;attribute2<=8'h0f;hs1<=0;vs1<=0;de1<=0;text1<=0;hs2<=0;vs2<=0;de2<=0;text2<=0;
        end else begin
            enable_meta<=enabled;enable_sync<=enable_meta;mode_meta<=mode1024;mode_sync<=mode_meta;
            if(x==(mode_sync?1343:1055))begin x<=0;if(y==(mode_sync?805:627))begin y<=0;frame_toggle<=!frame_toggle;end else y<=y+1'b1;end
            else x<=x+1'b1;
            x1<=x[2:0];y1<=y[3:0];hs1<=mode_sync?(x>=1048&&x<1184):(x>=840&&x<968);
            // DMT1024x768 uses negative H/V sync;800x600 uses positive sync.
            vs1<=mode_sync?!(y>=771&&y<777):(y>=601&&y<605);
            if(mode_sync)hs1<=!(x>=1048&&x<1184);
            de1<=active;text1<=visible_text&&enable_sync;
            attribute2<=character_word[15:8];x2<=x1;font_row<=y1[1:0];hs2<=hs1;vs2<=vs1;de2<=de1;text2<=text1;
        end
    end
    wire [7:0] glyph=font_word>>{font_row,3'b000};
    wire lit=text2&&glyph[7-x2];wire [3:0] color=text2?(lit?attribute2[3:0]:attribute2[7:4]):4'b0;
    wire [7:0] red={8{color[2]}}&(color[3]?8'hff:8'haa),green={8{color[1]}}&(color[3]?8'hff:8'haa),blue={8{color[0]}}&(color[3]?8'hff:8'haa);
    assign pixel={de2,vs2,hs2,red,green,blue};
endmodule
