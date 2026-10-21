// Fixed instruction ROM for the Curve25519 engine.
module x32_curve_program
    (input wire clk,
     input wire [8 : 0] address,
     output reg [31 : 0] instruction);
    (* syn_romstyle = "block_rom" *) reg [31 : 0] words[0 : 511];
    integer i;
    initial
    begin
        for (i = 0; i < 512; i = i + 1)
            words[i] = 32'hf0000001;
        words[0] = 32'h90000003;
        words[1] = 32'h90000026;
        words[2] = 32'h9000002e;
        // x25519
        words[3] = 32'he01e0000;
        words[4] = 32'h179e0000;
        words[5] = 32'h12010000;
        words[6] = 32'h12400000;
        words[7] = 32'h129e0000;
        words[8] = 32'h12c10000;
        words[9] = 32'h700000fe;
        // montgomery
        words[10] = 32'h601c0000;
        words[11] = 32'h40082800;
        words[12] = 32'h40092c00;
        words[13] = 32'h14082400;
        words[14] = 32'h24482400;
        words[15] = 32'h148a2c00;
        words[16] = 32'h24ca2c00;
        words[17] = 32'h35104000;
        words[18] = 32'h35514400;
        words[19] = 32'h25945400;
        words[20] = 32'h35d34000;
        words[21] = 32'h36124400;
        words[22] = 32'h14176000;
        words[23] = 32'h32904000;
        words[24] = 32'h24576000;
        words[25] = 32'h34514400;
        words[26] = 32'h32de4400;
        words[27] = 32'h32145400;
        words[28] = 32'h34025800;
        words[29] = 32'h14144000;
        words[30] = 32'h32564000;
        words[31] = 32'h40082800;
        words[32] = 32'h40092c00;
        words[33] = 32'h8000000a;
        words[34] = 32'h16490000;
        words[35] = 32'ha00000ba;
        words[36] = 32'h37c86800;
        words[37] = 32'hf0000000;
        // edbase
        words[38] = 32'h13060000;
        words[39] = 32'h13470000;
        words[40] = 32'h13810000;
        words[41] = 32'h33c61c00;
        words[42] = 32'he01c0002;
        words[43] = 32'ha0000068;
        words[44] = 32'ha00000b3;
        words[45] = 32'hf0000000;
        // edverify
        words[46] = 32'hd01e0001;
        words[47] = 32'he01e0000;
        words[48] = 32'h70000000;
        words[49] = 32'hc0000001;
        words[50] = 32'h401e9000;
        words[51] = 32'h17a40000;
        words[52] = 32'h501e9000;
        words[53] = 32'h908000ca;
        words[54] = 32'h135e0000;
        words[55] = 32'h13810000;
        words[56] = 32'h340d3400;
        words[57] = 32'h34500c00;
        words[58] = 32'h24100400;
        words[59] = 32'h14510400;
        words[60] = 32'h34914400;
        words[61] = 32'h34d24800;
        words[62] = 32'h35134800;
        words[63] = 32'h35544000;
        words[64] = 32'h35554400;
        words[65] = 32'h16550000;
        words[66] = 32'ha00000c2;
        words[67] = 32'h355a4000;
        words[68] = 32'h35554400;
        words[69] = 32'h35554400;
        words[70] = 32'h33154400;
        words[71] = 32'h358c3000;
        words[72] = 32'h35964400;
        words[73] = 32'h50164000;
        words[74] = 32'h9040004c;
        words[75] = 32'h330c1400;
        // root_ready
        words[76] = 32'h358c3000;
        words[77] = 32'h35964400;
        words[78] = 32'h50164000;
        words[79] = 32'h908000ca;
        words[80] = 32'hd00c0000;
        words[81] = 32'h90c00053;
        words[82] = 32'h90000054;
        // negate
        words[83] = 32'h23003000;
        // decoded
        words[84] = 32'h33cc3400;
        words[85] = 32'he01c0002;
        words[86] = 32'ha0000068;
        words[87] = 32'h18080000;
        words[88] = 32'h18490000;
        words[89] = 32'h188a0000;
        words[90] = 32'h18cb0000;
        words[91] = 32'h13060000;
        words[92] = 32'h13470000;
        words[93] = 32'h13810000;
        words[94] = 32'h33c61c00;
        words[95] = 32'he01d0002;
        words[96] = 32'ha0000068;
        words[97] = 32'h13200000;
        words[98] = 32'h13610000;
        words[99] = 32'h13a20000;
        words[100] = 32'h13e30000;
        words[101] = 32'ha00000a0;
        words[102] = 32'ha00000b3;
        words[103] = 32'hf0000000;
        // edscalar
        words[104] = 32'h12000000;
        words[105] = 32'h12410000;
        words[106] = 32'h12810000;
        words[107] = 32'h12c00000;
        words[108] = 32'h700000ff;
        // ed_loop
        words[109] = 32'h60000000;
        words[110] = 32'h40083000;
        words[111] = 32'h40093400;
        words[112] = 32'h400a3800;
        words[113] = 32'h400b3c00;
        words[114] = 32'ha000007a;
        words[115] = 32'ha000008d;
        words[116] = 32'h40083000;
        words[117] = 32'h40093400;
        words[118] = 32'h400a3800;
        words[119] = 32'h400b3c00;
        words[120] = 32'h8000006d;
        words[121] = 32'hb0000000;
        // add_qp
        words[122] = 32'h240d3000;
        words[123] = 32'h25092000;
        words[124] = 32'h34105000;
        words[125] = 32'h144c3400;
        words[126] = 32'h15082400;
        words[127] = 32'h34515000;
        words[128] = 32'h348f2c00;
        words[129] = 32'h34921000;
        words[130] = 32'h34ce2800;
        words[131] = 32'h14d34c00;
        words[132] = 32'h25514000;
        words[133] = 32'h25934800;
        words[134] = 32'h15d34800;
        words[135] = 32'h16114000;
        words[136] = 32'h33155800;
        words[137] = 32'h33585c00;
        words[138] = 32'h33975800;
        words[139] = 32'h33d56000;
        words[140] = 32'hb0000000;
        // double_p
        words[141] = 32'h24092000;
        words[142] = 32'h25092000;
        words[143] = 32'h34105000;
        words[144] = 32'h14482400;
        words[145] = 32'h15082400;
        words[146] = 32'h34515000;
        words[147] = 32'h348b2c00;
        words[148] = 32'h34921000;
        words[149] = 32'h34ca2800;
        words[150] = 32'h14d34c00;
        words[151] = 32'h25514000;
        words[152] = 32'h25934800;
        words[153] = 32'h15d34800;
        words[154] = 32'h16114000;
        words[155] = 32'h32155800;
        words[156] = 32'h32585c00;
        words[157] = 32'h32975800;
        words[158] = 32'h32d56000;
        words[159] = 32'hb0000000;
        // add_pq
        words[160] = 32'h24092000;
        words[161] = 32'h250d3000;
        words[162] = 32'h34105000;
        words[163] = 32'h14482400;
        words[164] = 32'h150c3400;
        words[165] = 32'h34515000;
        words[166] = 32'h348b3c00;
        words[167] = 32'h34921000;
        words[168] = 32'h34ca3800;
        words[169] = 32'h14d34c00;
        words[170] = 32'h25514000;
        words[171] = 32'h25934800;
        words[172] = 32'h15d34800;
        words[173] = 32'h16114000;
        words[174] = 32'h32155800;
        words[175] = 32'h32585c00;
        words[176] = 32'h32975800;
        words[177] = 32'h32d56000;
        words[178] = 32'hb0000000;
        // pack
        words[179] = 32'h164a0000;
        words[180] = 32'ha00000ba;
        words[181] = 32'h34086800;
        words[182] = 32'h37c96800;
        words[183] = 32'hd0100000;
        words[184] = 32'he01f0001;
        words[185] = 32'hb0000000;
        // inverse
        words[186] = 32'h16810000;
        words[187] = 32'h700000fe;
        // inverse_loop
        words[188] = 32'h369a6800;
        words[189] = 32'hc0000000;
        words[190] = 32'h910000c0;
        words[191] = 32'h369a6400;
        // inverse_skip
        words[192] = 32'h800000bc;
        words[193] = 32'hb0000000;
        // pow2523
        words[194] = 32'h16810000;
        words[195] = 32'h700000fb;
        // pow_loop
        words[196] = 32'h369a6800;
        words[197] = 32'hc0000001;
        words[198] = 32'h910000c8;
        words[199] = 32'h369a6400;
        // pow_skip
        words[200] = 32'h800000c4;
        words[201] = 32'hb0000000;
        // invalid
        words[202] = 32'hf0000001;
    end
    always @(posedge clk)
        instruction <= words[address];
endmodule
