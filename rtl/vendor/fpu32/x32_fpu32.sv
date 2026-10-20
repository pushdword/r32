// Compact binary32: shared normalization/rounding, 24-bit DSP product and
// 25-bit restoring divider. Fixed nearest-even, gradual underflow, canonical
// quiet NaN, no FP register bank, dynamic rounding or floating exception state.
module x32_fpu32(
    input wire clk,rst,req_valid,output wire req_ready,
    input wire [1:0] req_op,input wire [31:0] req_a,req_b,
    output wire resp_valid,input wire resp_ready,output reg [31:0] resp_z
);
    localparam IDLE=0,SPECIAL=1,ADD_PREP=2,ALIGN=3,ADD_EXEC=4,
        NORMALIZE_A=5,NORMALIZE_B=6,MULTIPLY=7,MUL_SELECT=8,
        DIV_SEED=9,DIV_STEP=10,NORMALIZE=11,ROUND=12,PACK=13,RESPONSE=14;
    reg [3:0] state;
    reg [1:0] op;
    reg [31:0] a_bits,b_bits;
    reg a_s,b_s,z_s;
    reg signed [9:0] a_e,b_e,z_e;
    reg [23:0] a_m,b_m,mantissa;
    reg [26:0] a_extended,b_extended,result_extended;
    reg [47:0] product;
    reg [24:0] remainder;
    reg [25:0] quotient;
    reg [4:0] divide_count;
    wire a_inf=a_bits[30:23]==8'hff && a_bits[22:0]==0;
    wire b_inf=b_bits[30:23]==8'hff && b_bits[22:0]==0;
    wire a_nan=a_bits[30:23]==8'hff && |a_bits[22:0];
    wire b_nan=b_bits[30:23]==8'hff && |b_bits[22:0];
    wire a_zero=a_bits[30:0]==0,b_zero=b_bits[30:0]==0;
    wire [27:0] add_sum={1'b0,a_extended}+{1'b0,b_extended};
    wire a_larger=a_extended>=b_extended;
    wire [26:0] add_difference=a_larger?a_extended-b_extended:b_extended-a_extended;
    wire division_bit=remainder>={1'b0,b_m};
    wire [24:0] division_remainder=(division_bit?remainder-{1'b0,b_m}:remainder)<<1;
    wire [25:0] division_quotient={quotient[24:0],division_bit};
    wire [24:0] rounded={1'b0,result_extended[26:3]}+25'd1;
    wire [9:0] encoded_exponent=z_e+10'd127;
    assign req_ready=!rst && state==IDLE;
    assign resp_valid=!rst && state==RESPONSE;
    // Accumulate every discarded bit into sticky before a single final rounding.
    function automatic [26:0] shift_sticky(input [26:0] value);
        shift_sticky={1'b0,value[26:2],value[1]|value[0]};
    endfunction
    always @(posedge clk)begin
        if(rst)begin state<=IDLE;resp_z<=0;end
        else case(state)
            IDLE:if(req_valid)begin
                op<=req_op;a_bits<=req_a;b_bits<=req_b^{(req_op==1),31'b0};
                a_s<=req_a[31];b_s<=req_b[31]^(req_op==1);
                a_m<={req_a[30:23]!=0,req_a[22:0]};b_m<={req_b[30:23]!=0,req_b[22:0]};
                a_e<=req_a[30:23]==0?-10'sd126:$signed({2'b0,req_a[30:23]})-10'sd127;
                b_e<=req_b[30:23]==0?-10'sd126:$signed({2'b0,req_b[30:23]})-10'sd127;
                state<=SPECIAL;
            end
            SPECIAL:begin
                z_s<=a_s^b_s;
                if(a_nan||b_nan)begin resp_z<=32'h7fc00000;state<=RESPONSE;end
                else if(!op[1])begin
                    if(a_inf||b_inf)begin
                        resp_z<=a_inf&&b_inf&&a_s!=b_s?32'h7fc00000:a_inf?a_bits:b_bits;
                        state<=RESPONSE;
                    end else if(a_zero||b_zero)begin
                        resp_z<=a_zero&&b_zero?{a_s&b_s,31'b0}:a_zero?b_bits:a_bits;state<=RESPONSE;
                    end else state<=ADD_PREP;
                end else if(op==2)begin
                    if((a_inf&&b_zero)||(b_inf&&a_zero))begin resp_z<=32'h7fc00000;state<=RESPONSE;end
                    else if(a_inf||b_inf)begin resp_z<={a_s^b_s,8'hff,23'b0};state<=RESPONSE;end
                    else if(a_zero||b_zero)begin resp_z<={a_s^b_s,31'b0};state<=RESPONSE;end
                    else state<=NORMALIZE_A;
                end else begin
                    if((a_inf&&b_inf)||(a_zero&&b_zero))begin resp_z<=32'h7fc00000;state<=RESPONSE;end
                    else if(a_inf||b_zero)begin resp_z<={a_s^b_s,8'hff,23'b0};state<=RESPONSE;end
                    else if(b_inf||a_zero)begin resp_z<={a_s^b_s,31'b0};state<=RESPONSE;end
                    else state<=NORMALIZE_A;
                end
            end
            ADD_PREP:begin a_extended<={a_m,3'b0};b_extended<={b_m,3'b0};state<=ALIGN;end
            ALIGN:begin
                if(a_e<b_e)begin a_extended<=shift_sticky(a_extended);a_e<=a_e+1;end
                else if(b_e<a_e)begin b_extended<=shift_sticky(b_extended);b_e<=b_e+1;end
                else begin z_e<=a_e;state<=ADD_EXEC;end
            end
            ADD_EXEC:begin
                if(a_s==b_s)begin
                    z_s<=a_s;
                    if(add_sum[27])begin result_extended<={add_sum[27:2],add_sum[1]|add_sum[0]};z_e<=z_e+1;end
                    else result_extended<=add_sum[26:0];
                    state<=NORMALIZE;
                end else if(add_difference==0)begin resp_z<=0;state<=RESPONSE;end
                else begin result_extended<=add_difference;z_s<=a_larger?a_s:b_s;state<=NORMALIZE;end
            end
            NORMALIZE_A:if(a_m[23])state<=NORMALIZE_B;else begin a_m<=a_m<<1;a_e<=a_e-1;end
            NORMALIZE_B:if(b_m[23])state<=op==2?MULTIPLY:DIV_SEED;else begin b_m<=b_m<<1;b_e<=b_e-1;end
            MULTIPLY:begin product<=a_m*b_m;z_e<=a_e+b_e;state<=MUL_SELECT;end
            MUL_SELECT:begin
                if(product[47])begin result_extended<={product[47:24],product[23:22],|product[21:0]};z_e<=z_e+1;end
                else result_extended<={product[46:23],product[22:21],|product[20:0]};
                state<=NORMALIZE;
            end
            DIV_SEED:begin
                z_e<=a_e-b_e-(a_m<b_m?10'sd1:10'sd0);
                remainder<=a_m<b_m?{a_m,1'b0}:{1'b0,a_m};quotient<=0;divide_count<=26;state<=DIV_STEP;
            end
            DIV_STEP:begin
                remainder<=division_remainder;quotient<=division_quotient;divide_count<=divide_count-1'b1;
                if(divide_count==1)begin result_extended<={division_quotient,|division_remainder};state<=NORMALIZE;end
            end
            NORMALIZE:begin
                if(z_e>10'sd127)begin resp_z<={z_s,8'hff,23'b0};state<=RESPONSE;end
                else if(z_e< -10'sd126)begin result_extended<=shift_sticky(result_extended);z_e<=z_e+1;end
                else if(!result_extended[26]&&result_extended!=0&&z_e> -10'sd126)begin
                    result_extended<=result_extended<<1;z_e<=z_e-1;
                end else state<=ROUND;
            end
            ROUND:begin
                if(result_extended[2]&&(result_extended[1]||result_extended[0]||result_extended[3]))begin
                    if(rounded[24])begin mantissa<=rounded[24:1];z_e<=z_e+1;end
                    else mantissa<=rounded[23:0];
                end else mantissa<=result_extended[26:3];
                state<=PACK;
            end
            PACK:begin
                if(z_e>10'sd127)resp_z<={z_s,8'hff,23'b0};
                else if(mantissa==0)resp_z<={z_s,31'b0};
                else if(mantissa[23])resp_z<={z_s,encoded_exponent[7:0],mantissa[22:0]};
                else resp_z<={z_s,8'b0,mantissa[22:0]};
                state<=RESPONSE;
            end
            RESPONSE:if(resp_ready)state<=IDLE;
            default:state<=IDLE;
        endcase
    end
endmodule
