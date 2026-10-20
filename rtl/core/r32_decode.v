// SPDX-License-Identifier: MIT
// Decode is independent of the Python encoder; reserved fields are enforced.
module r32_decode(input wire [31:0] word,output reg valid,
 output reg [4:0] ra,rb,rd,output reg use_a,use_b,write_rd,
 output reg load,store,serial,long_op,output wire [5:0] op);
 assign op=word[31:26];
 always @*begin
   ra=word[20:16];rb=word[15:11];rd=word[25:21];use_a=0;use_b=0;write_rd=0;
   load=0;store=0;serial=0;long_op=0;valid=1;
   case(op)
     0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,45,46,47,48,49,53:begin
       use_a=1;use_b=1;write_rd=1;valid=word[10:0]==0;long_op=op>=10&&op<=16;serial=op==45;store=op==45;
     end
     17,18,19,20,40:begin use_a=1;write_rd=1;end
     21,22,23,54:begin use_a=1;write_rd=1;valid=word[15:5]==0;end
     24:begin write_rd=1;valid=word[20:16]==0;end
     25,26,27,28,29:begin use_a=1;write_rd=1;load=1;end
     30,31,32:begin use_a=1;use_b=1;rb=rd;rd=0;store=1;end
     33,34,35,36,37,38:begin use_a=1;use_b=1;ra=word[25:21];rb=word[20:16];rd=0;end
     39:begin write_rd=1;end
     41:begin write_rd=1;serial=1;valid=word[20:16]==0&&word[15:0]<18;end
     42:begin use_a=1;write_rd=0;serial=1;valid=word[25:21]==0&&word[15:0]<18;end
     43:begin rd=0;serial=word[25:0]!=0;valid=word[25:0]<=7;end
     44:begin use_a=1;write_rd=1;load=1;serial=1;valid=word[15:0]==0;end
     50,51,52:begin use_a=1;write_rd=1;valid=word[15:0]==0;end
     55:begin use_a=1;write_rd=1;serial=1;valid=word[15:0]<18;end
     default:valid=0;
   endcase
 end
endmodule
