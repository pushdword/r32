// SPDX-License-Identifier: MIT
// R32 six-stage elastic development pipeline: Fetch, Decode, Read, Execute,
// Memory, Writeback. Independent instruction/data ready-valid channels.
// Optional MMU connects private I/D TLBs and physical-address atomics.
// The bare profile retains its original ports and timing; caches are pending.
// Instruction/data responses must follow an accepted request (not combinational).
module r32_core
    #(parameter [31 : 0] RESET_PC = 0,
      parameter ENABLE_FPU32 = 0,
      parameter ENABLE_MMU = 0,
      parameter CPU_HZ = 50000000,
      parameter SYSTEM_HZ = 30000000)
    (input wire clk, reset,
     output wire i_req_valid,
     input wire i_req_ready,
     output wire [31 : 0] i_req_address,
     input wire i_rsp_valid,
     output wire i_rsp_ready,
     input wire [31 : 0] i_rsp_data,
     input wire i_rsp_error,
     output wire d_req_valid,
     input wire d_req_ready,
     output wire [31 : 0] d_req_address, d_req_data,
     output wire [3 : 0] d_req_be,
     output wire d_req_write,
     input wire d_rsp_valid,
     output wire d_rsp_ready,
     input wire [31 : 0] d_rsp_data,
     input wire d_rsp_error,
     input wire [31 : 0] irq_pending,
     output reg retire_valid,
     output reg [31 : 0] retire_pc, retire_word, retire_next_pc,
     output reg [4 : 0] retire_rd,
     output reg [31 : 0] retire_value,
     output reg retire_store,
     output reg [31 : 0] retire_store_address, retire_store_data,
     output reg [3 : 0] retire_store_be,
     output reg trap_valid,
     output reg [31 : 0] trap_pc, trap_cause, trap_address,
     output reg halted,
     output reg [63 : 0] cycles, instructions);
    wire vi_req_valid, vi_req_ready, vi_rsp_valid, vi_rsp_ready, vi_rsp_error, vd_req_valid,
         vd_req_ready, vd_req_write, vd_rsp_valid, vd_rsp_ready, vd_rsp_error;
    wire [31 : 0] vi_req_address, vi_rsp_data, vd_req_address, vd_req_data, vd_rsp_data;
    wire [3 : 0] vd_req_be;
    wire vi_page_error, vd_page_error, vm_sc_failed;
    wire [31 : 0] vm_physical_address;
    wire translation_flush, reservation_clear;
    reg pending, pending_killed;
    reg [31 : 0] pending_pc, fetch_pc, architectural_pc;
    reg f_valid, d_valid, r_valid, e_valid, m_valid, w_valid;
    reg [31 : 0] f_pc, f_word, d_pc, d_word, r_pc, r_word, e_pc, e_word, m_pc, m_word, w_pc, w_word;
    reg f_error, d_error, r_error, e_error, m_error, w_error;
    reg [31 : 0] f_cause, d_cause, r_cause, e_cause, m_cause, w_cause;
    reg [31 : 0] f_bad, d_bad, r_bad, e_bad, m_bad, w_bad;
    wire dec_valid, dec_use_a, dec_use_b, dec_write, dec_load, dec_store, dec_serial, dec_long;
    wire [4 : 0] dec_ra, dec_rb, dec_rd;
    wire [5 : 0] dec_op;
    r32_decode decoder(d_word,
                       dec_valid,
                       dec_ra,
                       dec_rb,
                       dec_rd,
                       dec_use_a,
                       dec_use_b,
                       dec_write,
                       dec_load,
                       dec_store,
                       dec_serial,
                       dec_long,
                       dec_op);
    reg [4 : 0] r_ra, r_rb, r_rd, e_rd, m_rd, w_rd;
    reg r_use_a, r_use_b, r_write, r_load, r_store, r_serial, r_long;
    reg e_write, e_load, e_store, e_serial, e_long, m_write, m_load, m_store, m_serial, w_write,
        w_serial, w_store;
    // DSP packing must not absorb execute operands or alter their enables.
    (* syn_preserve = 1 *) reg [31 : 0] e_a, e_b;
    reg [31 : 0] m_value, m_address, m_data, m_next, w_value, w_address, w_data, w_next;
    reg [31 : 0] m_csr_value, w_csr_value;
    reg [3 : 0] m_be, w_be;
    reg m_sent, m_sc_failed;
    reg [31 : 0] csr[0 : 17];
    reg supervisor, reserved_valid;
    reg [31 : 0] reserved_address;
    wire [31 : 0] rf_a, rf_b;
    wire w_good = w_valid && !w_error;
    wire rf_write = w_good && w_write && w_rd != 0;
    wire f_advance, d_advance, r_advance, e_advance, m_advance;
    r32_regfile regfile(clk,
                        reset,
                        d_advance,
                        dec_ra,
                        dec_rb,
                        rf_a,
                        rf_b,
                        rf_write,
                        w_rd,
                        w_value);
    wire [5 : 0] e_op = e_word[31 : 26], m_op = m_word[31 : 26], w_op = w_word[31 : 26];
    wire [31 : 0] e_imm = {{16{e_word[15]}}, e_word[15 : 0]};
    wire [31 : 0] e_unsigned = {16'b0, e_word[15 : 0]};
    reg [31 : 0] alu_value, alu_next, alu_address, alu_cause, alu_bad;
    reg alu_error, branch_taken;
    reg [3 : 0] alu_be;
    integer n;
    reg e_started, e_long_ready;
    reg [31 : 0] e_long_value;
    wire mul_busy, mul_done;
    wire [31 : 0] mul_result;
    wire full_flush, front_flush;
    r32_muldiv muldiv(clk,
                      reset || full_flush,
                      e_valid && e_long && !e_started,
                      e_op,
                      e_a,
                      e_b,
                      mul_busy,
                      mul_done,
                      mul_result);
    wire e_fp = ENABLE_FPU32 && e_op >= 46 && e_op <= 49;
    wire fp_ready, fp_valid;
    wire [31 : 0] fp_value;
    generate
        if (ENABLE_FPU32)
        begin : fpu
            x32_fpu32 unit(clk,
                           reset || full_flush,
                           e_valid && e_fp && !e_started,
                           fp_ready,
                           e_op[1 : 0] - 2'd2,
                           e_a,
                           e_b,
                           fp_valid,
                           1'b1,
                           fp_value);
        end
        else
        begin : no_fpu
            assign fp_ready = 0;
            assign fp_valid = 0;
            assign fp_value = 0;
        end
    endgenerate
    wire e_complete = (!e_long && !e_fp) || e_long_ready || (e_fp ? fp_valid : mul_done);
    wire e_value_ready = !e_load && e_complete;
    wire [31 : 0] e_value = (e_long || e_fp) ? (e_long_ready ? e_long_value
                                                : e_fp       ? fp_value
                                                             : mul_result)
                                             : alu_value;
    wire [31 : 0] m_shifted = vd_rsp_data >> {m_address[1 : 0], 3'b0};
    reg [31 : 0] memory_value;
    wire sc_fail = m_op == 45 && (ENABLE_MMU ? vm_sc_failed : m_sc_failed);
    wire m_transaction = (m_load || m_store) && !m_error && (!sc_fail || ENABLE_MMU);
    wire m_done = !m_transaction || (m_sent && vd_rsp_valid);
    wire m_bus_error = m_transaction && m_sent && vd_rsp_valid && vd_rsp_error;
    wire w_system = w_valid && w_op == 43;
    wire w_redirect = w_valid && (w_error || w_op == 42 || w_op == 55 ||
                                  (w_system && (w_word[25 : 0] == 2 || w_word[25 : 0] == 3 ||
                                                w_word[25 : 0] == 5 || w_word[25 : 0] == 6)));
    wire irq_drain = csr[0][0] && |(csr[7] & irq_pending);
    wire irq_take = irq_drain && !e_valid && !m_valid && !w_redirect;
    wire [31 : 0] interrupt_epc = w_good ? w_next : architectural_pc;
    reg [31 : 0] irq_number;
    integer k;
    always @*
    begin
        irq_number = 0;
        for (k = 31; k >= 0; k = k - 1)
            if (csr[7][k] && irq_pending[k])
                irq_number = k;
    end
    assign translation_flush =
               w_good &&
               (((w_op == 42 || w_op == 55) && (w_word[15 : 0] == 0 || w_word[15 : 0] == 5)) ||
                (w_system && w_word[25 : 0] == 6));
    assign reservation_clear =
               (w_good && (w_op == 42 || w_op == 55 || (w_system && w_word[25 : 0] == 6))) ||
               irq_take || (w_valid && w_error) || (w_good && w_system && w_word[25 : 0] == 2);
    generate
        if (ENABLE_MMU)
        begin : virtual_memory
            r32_translation_bus translation(clk,
                                            reset,
                                            translation_flush,
                                            reservation_clear,
                                            supervisor,
                                            csr[0][3],
                                            csr[5],
                                            vi_req_valid,
                                            vi_req_ready,
                                            vi_req_address,
                                            vi_rsp_valid,
                                            vi_rsp_ready,
                                            vi_rsp_data,
                                            vi_rsp_error,
                                            vi_page_error,
                                            vd_req_valid,
                                            vd_req_ready,
                                            m_address,
                                            vd_req_data,
                                            vd_req_be,
                                            vd_req_write,
                                            m_op == 44,
                                            m_op == 45,
                                            vd_rsp_valid,
                                            vd_rsp_ready,
                                            vd_rsp_data,
                                            vd_rsp_error,
                                            vd_page_error,
                                            vm_sc_failed,
                                            vm_physical_address,
                                            i_req_valid,
                                            i_req_ready,
                                            i_req_address,
                                            i_rsp_valid,
                                            i_rsp_ready,
                                            i_rsp_data,
                                            i_rsp_error,
                                            d_req_valid,
                                            d_req_ready,
                                            d_req_address,
                                            d_req_data,
                                            d_req_be,
                                            d_req_write,
                                            d_rsp_valid,
                                            d_rsp_ready,
                                            d_rsp_data,
                                            d_rsp_error);
        end
        else
        begin : physical_memory
            assign i_req_valid = vi_req_valid;
            assign vi_req_ready = i_req_ready;
            assign i_req_address = vi_req_address;
            assign vi_rsp_valid = i_rsp_valid;
            assign i_rsp_ready = vi_rsp_ready;
            assign vi_rsp_data = i_rsp_data;
            assign vi_rsp_error = i_rsp_error;
            assign d_req_valid = vd_req_valid;
            assign vd_req_ready = d_req_ready;
            assign d_req_address = vd_req_address;
            assign d_req_data = vd_req_data;
            assign d_req_be = vd_req_be;
            assign d_req_write = vd_req_write;
            assign vd_rsp_valid = d_rsp_valid;
            assign d_rsp_ready = vd_rsp_ready;
            assign vd_rsp_data = d_rsp_data;
            assign vd_rsp_error = d_rsp_error;
            assign vi_page_error = 0;
            assign vd_page_error = 0;
            assign vm_sc_failed = 0;
            assign vm_physical_address = 0;
        end
    endgenerate
    wire branch_redirect = e_advance && !alu_error && branch_taken;
    assign full_flush = w_redirect || irq_take;
    assign front_flush = full_flush || branch_redirect;
    assign m_advance = m_valid && m_done && !full_flush;
    assign e_advance = e_valid && (!m_valid || m_advance) && e_complete && !full_flush;
    reg [31 : 0] forward_a, forward_b;
    reg hazard;
    wire r_serial_wait = (r_serial && (e_valid || m_valid || w_valid)) || (e_valid && e_serial) ||
                         (m_valid && m_serial) || (w_valid && w_serial);
    always @*
    begin
        forward_a = rf_a;
        forward_b = rf_b;
        hazard = 0;
        if (r_ra == 0)
            forward_a = 0;
        else if (r_use_a)
        begin
            if (e_valid && e_write && e_rd == r_ra)
            begin
                if (e_value_ready && !alu_error)
                    forward_a = e_value;
                else
                    hazard = 1;
            end
            else if (m_valid && m_write && m_rd == r_ra)
            begin
                if (m_done && !m_error && !m_bus_error)
                    forward_a = memory_value;
                else
                    hazard = 1;
            end
            else if (rf_write && w_rd == r_ra)
                forward_a = w_value;
        end
        if (r_rb == 0)
            forward_b = 0;
        else if (r_use_b)
        begin
            if (e_valid && e_write && e_rd == r_rb)
            begin
                if (e_value_ready && !alu_error)
                    forward_b = e_value;
                else
                    hazard = 1;
            end
            else if (m_valid && m_write && m_rd == r_rb)
            begin
                if (m_done && !m_error && !m_bus_error)
                    forward_b = memory_value;
                else
                    hazard = 1;
            end
            else if (rf_write && w_rd == r_rb)
                forward_b = w_value;
        end
    end
    assign r_advance = r_valid && (!e_valid || e_advance) && !hazard && !r_serial_wait &&
                       !irq_drain && !full_flush;
    assign d_advance = d_valid && (!r_valid || r_advance) && !front_flush;
    assign f_advance = f_valid && (!d_valid || d_advance) && !front_flush;
    wire f_free = !f_valid || f_advance;
    assign vi_rsp_ready = pending && (f_free || pending_killed || front_flush);
    wire response = vi_rsp_valid && vi_rsp_ready;
    assign vi_req_valid = !reset && !halted && !front_flush && !pending_killed &&
                          (!pending || response) && f_free && !irq_drain;
    assign vi_req_address = fetch_pc;
    wire request = vi_req_valid && vi_req_ready;
    assign vd_req_valid = m_valid && m_transaction && !m_sent && !full_flush;
    assign vd_req_write = m_store;
    assign vd_req_address = {m_address[31 : 2], 2'b0};
    assign vd_req_data = m_data;
    assign vd_req_be = m_be;
    assign vd_rsp_ready = m_valid && m_sent && !full_flush;
    always @*
    begin
        memory_value = m_value;
        if (m_op == 45)
            memory_value = sc_fail ? 1 : 0;
        else if (m_load)
            case (m_op)
                25:
                    memory_value = {{24{m_shifted[7]}}, m_shifted[7 : 0]};
                26:
                    memory_value = {24'b0, m_shifted[7 : 0]};
                27:
                    memory_value = {{16{m_shifted[15]}}, m_shifted[15 : 0]};
                28:
                    memory_value = {16'b0, m_shifted[15 : 0]};
                default:
                    memory_value = vd_rsp_data;
            endcase
    end
    always @*
    begin
        alu_value = 0;
        alu_next = e_pc + 4;
        alu_address = e_a + e_imm;
        alu_error = e_error;
        alu_cause = e_cause;
        alu_bad = e_bad;
        branch_taken = 0;
        alu_be = 4'hf;
        case (e_op)
            0:
                alu_value = e_a + e_b;
            1:
                alu_value = e_a - e_b;
            2:
                alu_value = e_a & e_b;
            3:
                alu_value = e_a | e_b;
            4:
                alu_value = e_a ^ e_b;
            5:
                alu_value = e_a << e_b[4 : 0];
            6:
                alu_value = e_a >> e_b[4 : 0];
            7:
                alu_value = $signed(e_a) >>> e_b[4 : 0];
            8:
                alu_value = {31'b0, $signed(e_a) < $signed(e_b)};
            9:
                alu_value = {31'b0, e_a < e_b};
            10, 11, 12, 13, 14, 15, 16:
                alu_value = 0;
            17:
                alu_value = e_a + e_imm;
            18:
                alu_value = e_a & e_unsigned;
            19:
                alu_value = e_a | e_unsigned;
            20:
                alu_value = e_a ^ e_unsigned;
            21:
                alu_value = e_a << e_word[4 : 0];
            22:
                alu_value = e_a >> e_word[4 : 0];
            23:
                alu_value = $signed(e_a) >>> e_word[4 : 0];
            24:
                alu_value = {e_word[15 : 0], 16'b0};
            25, 26, 30:
                alu_be = 4'b0001 << alu_address[1 : 0];
            27, 28, 31:
                alu_be = 4'b0011 << alu_address[1 : 0];
            29, 32:
                alu_be = 4'hf;
            33:
                branch_taken = e_a == e_b;
            34:
                branch_taken = e_a != e_b;
            35:
                branch_taken = $signed(e_a) < $signed(e_b);
            36:
                branch_taken = $signed(e_a) >= $signed(e_b);
            37:
                branch_taken = e_a < e_b;
            38:
                branch_taken = e_a >= e_b;
            39: begin
                alu_value = e_pc + 4;
                alu_next = e_pc + 4 + {{9{e_word[20]}}, e_word[20 : 0], 2'b0};
                branch_taken = 1;
            end
            40: begin
                alu_value = e_pc + 4;
                alu_next = e_a + e_imm;
                branch_taken = 1;
            end
            41: begin
                if (e_word[15 : 0] < 18)
                    alu_value = csr[e_word[15 : 0]];
                case (e_word[15 : 0])
                    8:
                        alu_value = irq_pending;
                    10:
                        alu_value = cycles[31 : 0];
                    11:
                        alu_value = cycles[63 : 32];
                    12:
                        alu_value = instructions[31 : 0];
                    13:
                        alu_value = instructions[63 : 32];
                endcase
            end
            42:
                alu_value = e_a;
            55:
                if (e_word[15 : 0] < 18)
                    alu_value = csr[e_word[15 : 0]];
            43: begin
                if (e_word[25 : 0] == 1)
                begin
                    alu_error = 1;
                    alu_cause = supervisor ? 8 : 7;
                    alu_bad = 0;
                end
                if (e_word[25 : 0] == 7)
                begin
                    alu_error = 1;
                    alu_cause = 9;
                    alu_bad = e_pc;
                end
            end
            44, 45: begin
                alu_address = e_a;
                alu_be = 4'hf;
            end
            46, 47, 48, 49:
                if (!ENABLE_FPU32)
                begin
                    alu_error = 1;
                    alu_cause = 0;
                    alu_bad = e_pc;
                end
            50: begin
                alu_value = 32;
                for (n = 0; n < 32; n = n + 1)
                    if (e_a[n])
                        alu_value = 31 - n;
            end
            51: begin
                alu_value = 32;
                for (n = 31; n >= 0; n = n - 1)
                    if (e_a[n])
                        alu_value = n;
            end
            52: begin
                alu_value = 0;
                for (n = 0; n < 32; n = n + 1)
                    alu_value = alu_value + {31'b0, e_a[n]};
            end
            53:
                alu_value =
                    e_b[4 : 0] == 0 ? e_a : (e_a >> e_b[4 : 0]) | (e_a << (32 - e_b[4 : 0]));
            54:
                alu_value = e_word[4 : 0] == 0
                                ? e_a
                                : (e_a >> e_word[4 : 0]) | (e_a << (32 - e_word[4 : 0]));
            default: begin
                alu_error = 1;
                alu_cause = 0;
                alu_bad = e_pc;
            end
        endcase
        if (e_op >= 33 && e_op <= 38 && branch_taken)
            alu_next = e_pc + 4 + {{14{e_word[15]}}, e_word[15 : 0], 2'b0};
        if (!e_error)
        begin
            if ((e_load || e_store) &&
                (((e_op == 27 || e_op == 28 || e_op == 31) && alu_address[0]) ||
                 ((e_op == 29 || e_op == 32 || e_op == 44 || e_op == 45) && |alu_address[1 : 0])))
            begin
                alu_error = 1;
                alu_cause = e_store ? 5 : 3;
                alu_bad = alu_address;
            end
            else if (branch_taken && |alu_next[1 : 0])
            begin
                alu_error = 1;
                alu_cause = 1;
                alu_bad = alu_next;
            end
            else if ((e_load || e_store) && !ENABLE_MMU && !supervisor &&
                     alu_address[31 : 24] == 8'hf0)
            begin
                alu_error = 1;
                alu_cause = e_store ? 12 : 11;
                alu_bad = alu_address;
            end
            else if ((e_op == 41 && !supervisor && e_word[15 : 0] < 9) ||
                     ((e_op == 42 || e_op == 55) &&
                      (!supervisor || e_word[15 : 0] >= 8 ||
                       (e_word[15 : 0] == 5 && |e_a[11 : 0]) ||
                       ((e_word[15 : 0] == 1 || e_word[15 : 0] == 2) && |e_a[1 : 0]) ||
                       (e_word[15 : 0] == 0 && e_a[3] && !ENABLE_MMU))) ||
                     (e_op == 43 && !supervisor &&
                      (e_word[25 : 0] == 2 || e_word[25 : 0] == 3 || e_word[25 : 0] == 6)))
            begin
                alu_error = 1;
                alu_cause = 0;
                alu_bad = e_pc;
            end
        end
    end
    integer j;
    always @(posedge clk)
    begin
        if (reset)
        begin
            pending <= 0;
            pending_killed <= 0;
            pending_pc <= RESET_PC;
            fetch_pc <= RESET_PC;
            architectural_pc <= RESET_PC;
            f_valid <= 0;
            d_valid <= 0;
            r_valid <= 0;
            e_valid <= 0;
            m_valid <= 0;
            w_valid <= 0;
            f_pc <= 0;
            f_word <= 0;
            d_pc <= 0;
            d_word <= 0;
            r_pc <= 0;
            r_word <= 0;
            e_pc <= 0;
            e_word <= 0;
            m_pc <= 0;
            m_word <= 0;
            w_pc <= 0;
            w_word <= 0;
            f_error <= 0;
            d_error <= 0;
            r_error <= 0;
            e_error <= 0;
            m_error <= 0;
            w_error <= 0;
            f_cause <= 0;
            d_cause <= 0;
            r_cause <= 0;
            e_cause <= 0;
            m_cause <= 0;
            w_cause <= 0;
            f_bad <= 0;
            d_bad <= 0;
            r_bad <= 0;
            e_bad <= 0;
            m_bad <= 0;
            w_bad <= 0;
            r_ra <= 0;
            r_rb <= 0;
            r_rd <= 0;
            e_rd <= 0;
            m_rd <= 0;
            w_rd <= 0;
            r_use_a <= 0;
            r_use_b <= 0;
            r_write <= 0;
            r_load <= 0;
            r_store <= 0;
            r_serial <= 0;
            r_long <= 0;
            e_write <= 0;
            e_load <= 0;
            e_store <= 0;
            e_serial <= 0;
            e_long <= 0;
            m_write <= 0;
            m_load <= 0;
            m_store <= 0;
            m_serial <= 0;
            w_write <= 0;
            w_serial <= 0;
            w_store <= 0;
            e_a <= 0;
            e_b <= 0;
            m_value <= 0;
            m_address <= 0;
            m_data <= 0;
            m_next <= 0;
            w_value <= 0;
            w_address <= 0;
            w_data <= 0;
            w_next <= 0;
            m_csr_value <= 0;
            w_csr_value <= 0;
            m_be <= 0;
            w_be <= 0;
            m_sent <= 0;
            m_sc_failed <= 0;
            e_started <= 0;
            e_long_ready <= 0;
            e_long_value <= 0;
            supervisor <= 1;
            reserved_valid <= 0;
            reserved_address <= 0;
            cycles <= 0;
            instructions <= 0;
            halted <= 0;
            retire_valid <= 0;
            trap_valid <= 0;
            retire_pc <= 0;
            retire_word <= 0;
            retire_next_pc <= 0;
            retire_rd <= 0;
            retire_value <= 0;
            retire_store <= 0;
            retire_store_address <= 0;
            retire_store_data <= 0;
            retire_store_be <= 0;
            trap_pc <= 0;
            trap_cause <= 0;
            trap_address <= 0;
            for (j = 0; j < 18; j = j + 1)
                csr[j] <= 0;
            csr[9] <= ENABLE_FPU32 ? 32'h10001 : 1;
            csr[14] <= CPU_HZ;
            csr[15] <= SYSTEM_HZ;
            csr[17] <= 1;
        end
        else
        begin
            cycles <= cycles + 1'b1;
            retire_valid <= 0;
            retire_store <= 0;
            trap_valid <= 0;
            if (w_good)
            begin
                instructions <= instructions + 1'b1;
                architectural_pc <= w_next;
                retire_valid <= 1;
                retire_pc <= w_pc;
                retire_word <= w_word;
                retire_next_pc <= w_next;
                retire_rd <= w_write ? w_rd : 0;
                retire_value <= w_write && w_rd != 0 ? w_value : 0;
                retire_store <= w_store;
                retire_store_address <= w_address;
                retire_store_data <= w_data;
                retire_store_be <= w_be;
                if (w_op == 44)
                begin
                    reserved_valid <= 1;
                    reserved_address <= w_address;
                end
                if (w_op == 42 || w_op == 55)
                begin
                    csr[w_word[15 : 0]] <=
                        w_word[15 : 0] == 0 ? {28'b0, w_csr_value[3 : 0]} : w_csr_value;
                    reserved_valid <= 0;
                end
                if (w_system && w_word[25 : 0] == 6)
                    reserved_valid <= 0;
            end
            if (e_valid && !e_started && (e_long || (e_fp && fp_ready)))
                e_started <= 1;
            if (mul_done || fp_valid)
            begin
                e_long_ready <= 1;
                e_long_value <= fp_valid ? fp_value : mul_result;
            end
            w_valid <= m_advance;
            if (m_advance)
            begin
                w_csr_value <= m_csr_value;
                w_pc <= m_pc;
                w_word <= m_word;
                w_value <= memory_value;
                w_rd <= m_rd;
                w_write <= m_write;
                w_error <= m_error || m_bus_error;
                w_cause <= m_bus_error ? (vd_page_error ? (m_store ? 12 : 11) : (m_store ? 6 : 4))
                                       : m_cause;
                w_bad <= m_bus_error ? m_address : m_bad;
                w_next <= m_next;
                w_serial <= m_serial;
                w_store <= m_store && !sc_fail && !m_error && !m_bus_error;
                w_address <= ENABLE_MMU ? vm_physical_address : m_address;
                w_data <= m_data;
                w_be <= m_be;
            end
            if (m_advance)
            begin
                m_valid <= 0;
                m_sent <= 0;
            end
            if (e_advance)
            begin
                m_csr_value <= e_a;
                m_valid <= 1;
                m_sent <= 0;
                m_sc_failed <= e_op == 45 && (!reserved_valid || reserved_address != alu_address);
                m_pc <= e_pc;
                m_word <= e_word;
                m_value <= e_value;
                m_rd <= e_rd;
                m_write <= e_write;
                m_load <= e_load;
                m_store <= e_store;
                m_serial <= e_serial;
                m_error <= alu_error;
                m_cause <= alu_cause;
                m_bad <= alu_bad;
                m_next <= alu_next;
                m_address <= alu_address;
                m_data <= e_b << {alu_address[1 : 0], 3'b0};
                m_be <= alu_be;
            end
            if (vd_req_valid && vd_req_ready)
            begin
                m_sent <= 1;
                if (m_store)
                    reserved_valid <= 0;
            end
            if (e_advance)
            begin
                e_valid <= 0;
                e_started <= 0;
                e_long_ready <= 0;
            end
            if (r_advance)
            begin
                e_valid <= 1;
                e_started <= 0;
                e_long_ready <= 0;
                e_pc <= r_pc;
                e_word <= r_word;
                e_rd <= r_rd;
                e_write <= r_write;
                e_a <= forward_a;
                e_b <= forward_b;
                e_load <= r_load;
                e_store <= r_store;
                e_serial <= r_serial;
                e_long <= r_long;
                e_error <= r_error;
                e_cause <= r_cause;
                e_bad <= r_bad;
            end
            if (r_advance)
                r_valid <= 0;
            if (d_advance)
            begin
                r_valid <= 1;
                r_pc <= d_pc;
                r_word <= d_word;
                r_ra <= dec_ra;
                r_rb <= dec_rb;
                r_rd <= dec_rd;
                r_use_a <= dec_use_a;
                r_use_b <= dec_use_b;
                r_write <= dec_write;
                r_load <= dec_load;
                r_store <= dec_store;
                r_serial <= dec_serial;
                r_long <= dec_long;
                r_error <= d_error || !dec_valid;
                r_cause <= d_error ? d_cause : 0;
                r_bad <= d_error ? d_bad : d_pc;
            end
            if (d_advance)
                d_valid <= 0;
            if (f_advance)
            begin
                d_valid <= 1;
                d_pc <= f_pc;
                d_word <= f_word;
                d_error <= f_error;
                d_cause <= f_cause;
                d_bad <= f_bad;
            end
            if (f_advance)
                f_valid <= 0;
            if (response)
            begin
                pending <= 0;
                pending_killed <= 0;
                if (!pending_killed && !front_flush)
                begin
                    f_valid <= 1;
                    f_pc <= pending_pc;
                    f_word <= vi_rsp_data;
                    f_error <= vi_rsp_error || (|pending_pc[1 : 0]);
                    f_cause <= |pending_pc[1 : 0] ? 1 : vi_page_error ? 10 : 2;
                    f_bad <= pending_pc;
                end
            end
            if (request)
            begin
                pending <= 1;
                pending_killed <= 0;
                pending_pc <= fetch_pc;
                fetch_pc <= fetch_pc + 4;
            end
            if (front_flush)
            begin
                f_valid <= 0;
                d_valid <= 0;
                r_valid <= 0;
                e_valid <= 0;
                e_started <= 0;
                e_long_ready <= 0;
                if (pending && !response)
                    pending_killed <= 1;
                if (branch_redirect)
                    fetch_pc <= alu_next;
                if (w_redirect)
                begin
                    fetch_pc <= w_error                             ? csr[1]
                                : (w_system && w_word[25 : 0] == 2) ? csr[2]
                                                                    : w_next;
                    if (w_system && w_word[25 : 0] == 2)
                    begin
                        supervisor <= csr[0][2];
                        csr[0] <= {28'b0, csr[0][3], 1'b0, 1'b1, csr[0][1]};
                        reserved_valid <= 0;
                        architectural_pc <= csr[2];
                        retire_next_pc <= csr[2];
                    end
                    if (w_system && w_word[25 : 0] == 3 && !w_error)
                        halted <= 1;
                end
            end
            if (full_flush)
            begin
                m_valid <= 0;
                m_sent <= 0;
                w_valid <= 0;
            end
            if ((w_valid && w_error) || irq_take)
            begin
                trap_valid <= 1;
                trap_pc <= irq_take ? interrupt_epc : w_pc;
                trap_cause <= irq_take ? (32'h80000000 | irq_number) : w_cause;
                trap_address <= irq_take ? 0 : w_bad;
                csr[2] <= irq_take ? interrupt_epc : w_pc;
                csr[3] <= irq_take ? (32'h80000000 | irq_number) : w_cause;
                csr[4] <= irq_take ? 0 : w_bad;
                csr[0] <= {28'b0, csr[0][3], supervisor, csr[0][0], 1'b0};
                supervisor <= 1;
                fetch_pc <= csr[1];
                architectural_pc <= csr[1];
                halted <= 0;
                reserved_valid <= 0;
            end
        end
    end
endmodule
