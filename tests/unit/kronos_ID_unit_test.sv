// Copyright (c) 2020 Sonal Pinto
// SPDX-License-Identifier: Apache-2.0


`include "vunit_defines.svh"

module tb_kronos_ID_ut;

import kronos_types::*;
import rv32_assembler::*;

logic clk;
logic rstz;
pipeIFID_t fetch;
logic pipe_in_vld;
logic pipe_in_rdy;
pipeIDEX_t decode;
logic pipe_out_vld;
logic pipe_out_rdy;
logic [31:0] regwr_data;
logic [4:0] regwr_sel;
logic regwr_en;
hazardEX_t ex_hazard;

kronos_ID u_id (
    .clk         (clk         ),
    .rstz        (rstz        ),
    .fetch       (fetch       ),
    .pipe_in_vld (pipe_in_vld ),
    .pipe_in_rdy (pipe_in_rdy ),
    .decode      (decode      ),
    .pipe_out_vld(pipe_out_vld),
    .pipe_out_rdy(pipe_out_rdy),
    .regwr_data  (regwr_data  ),
    .regwr_sel   (regwr_sel   ),
    .regwr_en    (regwr_en    ),
    .ex_hazard   (ex_hazard   )
);

default clocking cb @(posedge clk);
    default input #10ps output #10ps;
    input pipe_out_vld, decode;
    input negedge pipe_in_rdy;
    output pipe_in_vld, fetch;
    output negedge pipe_out_rdy;
endclocking

// ============================================================

logic [31:0] REG [32];

`TEST_SUITE begin
    `TEST_SUITE_SETUP begin
        clk = 0;
        rstz = 0;

        fetch = '0;
        pipe_in_vld = 0;
        pipe_out_rdy = 0;
        regwr_data = '0;
        regwr_en = 0;
        regwr_sel = 0;

        // init regfile with random values
        for(int i=0; i<32; i++) begin
            u_id.REG1[i] = $urandom;
            u_id.REG2[i] = u_id.REG1[i];
            REG[i] = u_id.REG1[i];
        end

        // Zero out TB's REG[0] (x0)
        REG[0] = 0;

        fork 
            forever #1ns clk = ~clk;
        join_none

        ##4 rstz = 1;
    end

    `TEST_CASE("decode") begin
        pipeIFID_t tinstr;
        pipeIDEX_t tdecode, rdecode;
        string optype;

        repeat (2**10) begin

            rand_instr(tinstr, tdecode, optype);

            $display("OPTYPE=%s", optype);
            $display("IFID: PC=%h, IR=%h", tinstr.pc, tinstr.ir);
            $display("Expected IDEX:");
            print_decode(tdecode);

            fork 
                begin
                    @(cb);
                    cb.fetch <= tinstr;
                    cb.pipe_in_vld <= 1;
                    repeat (16) begin
                        @(cb) if (cb.pipe_in_rdy) begin
                            cb.pipe_in_vld <= 0;
                            break;
                        end
                    end
                end

                begin
                    @(cb iff pipe_out_vld) begin
                        //check
                        rdecode = decode;

                        $display("Got IDEX:");
                        print_decode(rdecode);

                        cb.pipe_out_rdy <= 1;
                        ##1 cb.pipe_out_rdy <= 0;

                        assert(rdecode == tdecode);
                    end
                end
            join

            $display("-----------------\n\n");
        end

        ##64;
    end

end

`WATCHDOG(1ms);

// ============================================================
// METHODS
// ============================================================

task automatic print_decode(input pipeIDEX_t d);
    $display("---- OP --------");
    $display("  op1: %h",           d.op1);
    $display("  op2: %h",           d.op2);
    $display("  op3: %h",           d.op3);
    $display("  op4: %h",           d.op4);
    $display("---- EXCTRL ----");
    $display("  cin: %b",           d.cin);
    $display("  rev: %b",           d.rev);
    $display("  uns: %b",           d.uns);
    $display("  eq: %b",            d.eq);
    $display("  inv: %b",           d.inv);
    $display("  align: %b",         d.align);
    $display("  sel: %h",           d.sel);
    $display("---- WBCTRL ----");
    $display("  rd: %d",            d.rd);
    $display("  rd_write: %h",      d.rd_write);
    $display("  branch: %h",        d.branch);
    $display("  branch_cond: %h",   d.branch_cond);
    $display("  ld_size: %h",       d.ld_size);    
    $display("  ld_sign: %h",       d.ld_sign);
    $display("  st: %h",            d.st);
    $display("  illegal: %h",       d.illegal);
endtask

task automatic rand_instr(output pipeIFID_t instr, output pipeIDEX_t decode, output string optype);
    /*
    Generate constrained-random instr

    Note: This would have been a breeze with SV constraints.
        However, the "free" version of modelsim doesn't support
        that feature (along with many other things, like 
        coverage, properties, sequences, etc)
        Hence, we get by with just the humble $urandom

        You can do A LOT of things with just $urandom
    */

    int op;

    logic [6:0] opcode;
    logic [4:0] rs1, rs2, rd;
    logic [2:0] funct3;
    logic [6:0] funct7;
    logic [31:0] imm;

    // generate scenario
    op = $urandom_range(0,20);
    imm = $urandom();
    rs1 = $urandom();
    rs2 = $urandom();
    rd = $urandom_range(1,31);

    instr.pc = $urandom;

    // Blank out decode
    // EX Operands ------------
    decode.op1 = instr.pc;
    decode.op2 = 4;
    decode.op3 = instr.pc;
    decode.op4 = 0;
    // ------------------------
    // EX controls
    decode.cin = 0;
    decode.rev = 0;
    decode.uns = 0;
    decode.eq = 0;
    decode.inv = 0;
    decode.align = 0;
    decode.sel = 0;
    // ------------------------
    // WB controls
    decode.rd = 0;
    decode.rd_write = 0;
    decode.branch = 0;
    decode.branch_cond = 0;
    decode.ld_size = 0;
    decode.ld_sign = 0;
    decode.st = 0;
    decode.illegal = 0;


    // painstakingly build random-valid instructions
    // and expected decode
    case(op)
        0: begin
            optype = "ADDI";
            instr.ir = rv32_addi(rd, rs1, imm);

            decode.op1 = REG[rs1];
            decode.op2 = signed'(imm[11:0]);
            decode.rd  = rd;
            decode.rd_write = 1;
        end

        1: begin
            optype = "SLTI";
            instr.ir = rv32_slti(rd, rs1, imm);

            decode.op1 = REG[rs1];
            decode.op2 = signed'(imm[11:0]);
            decode.rd  = rd;
            decode.rd_write = 1;

            decode.cin = 1;
            decode.sel = ALU_COMP;
        end

        2: begin
            optype = "SLTIU";
            instr.ir = rv32_sltiu(rd, rs1, imm);

            decode.op1 = REG[rs1];
            decode.op2 = signed'(imm[11:0]);
            decode.rd  = rd;
            decode.rd_write = 1;

            decode.cin = 1;
            decode.uns = 1;
            decode.sel = ALU_COMP;
        end

        3: begin
            optype = "XORI";
            instr.ir = rv32_xori(rd, rs1, imm);

            decode.op1 = REG[rs1];
            decode.op2 = signed'(imm[11:0]);
            decode.rd  = rd;
            decode.rd_write = 1;

            decode.sel = ALU_XOR;
        end

        4: begin
            optype = "ORI";
            instr.ir = rv32_ori(rd, rs1, imm);

            decode.op1 = REG[rs1];
            decode.op2 = signed'(imm[11:0]);
            decode.rd  = rd;
            decode.rd_write = 1;

            decode.sel = ALU_OR;
        end

        5: begin
            optype = "ANDI";
            instr.ir = rv32_andi(rd, rs1, imm);

            decode.op1 = REG[rs1];
            decode.op2 = signed'(imm[11:0]);
            decode.rd  = rd;
            decode.rd_write = 1;

            decode.sel = ALU_AND;
        end

        6: begin
            optype = "SLLI";
            instr.ir = rv32_slli(rd, rs1, imm);

            decode.op1 = REG[rs1];
            decode.op2 = signed'({7'b0, imm[4:0]});
            decode.rd  = rd;
            decode.rd_write = 1;

            decode.rev = 1;
            decode.uns = 1;
            decode.sel = ALU_SHIFT;
        end

        7: begin
            optype = "SRLI";
            instr.ir = rv32_srli(rd, rs1, imm);

            decode.op1 = REG[rs1];
            decode.op2 = signed'({7'b0, imm[4:0]});
            decode.rd  = rd;
            decode.rd_write = 1;

            decode.uns = 1;
            decode.sel = ALU_SHIFT;
        end

        8: begin
            optype = "SRAI";
            instr.ir = rv32_srai(rd, rs1, imm);

            decode.op1 = REG[rs1];
            decode.op2 = signed'({7'b0100000,imm[4:0]});
            decode.rd  = rd;
            decode.rd_write = 1;

            decode.sel = ALU_SHIFT;
        end

        9: begin
            optype = "ADD";
            instr.ir = rv32_add(rd, rs1, rs2);

            decode.op1 = REG[rs1];
            decode.op2 = REG[rs2];
            decode.rd  = rd;
            decode.rd_write = 1;
        end

        10: begin
            optype = "SUB";
            instr.ir = rv32_sub(rd, rs1, rs2);

            decode.op1 = REG[rs1];
            decode.op2 = REG[rs2];
            decode.rd  = rd;
            decode.rd_write = 1;

            decode.cin = 1;
        end

        11: begin
            optype = "SLL";
            instr.ir = rv32_sll(rd, rs1, rs2);

            decode.op1 = REG[rs1];
            decode.op2 = REG[rs2];
            decode.rd  = rd;
            decode.rd_write = 1;

            decode.rev = 1;
            decode.uns = 1;
            decode.sel = ALU_SHIFT;
        end

        12: begin
            optype = "SLT";
            instr.ir = rv32_slt(rd, rs1, rs2);

            decode.op1 = REG[rs1];
            decode.op2 = REG[rs2];
            decode.rd  = rd;
            decode.rd_write = 1;

            decode.cin = 1;
            decode.sel = ALU_COMP;
        end


        13: begin
            optype = "SLTU";
            instr.ir = rv32_sltu(rd, rs1, rs2);

            decode.op1 = REG[rs1];
            decode.op2 = REG[rs2];
            decode.rd  = rd;
            decode.rd_write = 1;

            decode.cin = 1;
            decode.uns = 1;
            decode.sel = ALU_COMP;
        end

        14: begin
            optype = "XOR";
            instr.ir = rv32_xor(rd, rs1, rs2);

            decode.op1 = REG[rs1];
            decode.op2 = REG[rs2];
            decode.rd  = rd;
            decode.rd_write = 1;

            decode.sel = ALU_XOR;
        end

        15: begin
            optype = "SRL";
            instr.ir = rv32_srl(rd, rs1, rs2);

            decode.op1 = REG[rs1];
            decode.op2 = REG[rs2];
            decode.rd  = rd;
            decode.rd_write = 1;

            decode.uns = 1;
            decode.sel = ALU_SHIFT;
        end

        16: begin
            optype = "SRA";
            instr.ir = rv32_sra(rd, rs1, rs2);

            decode.op1 = REG[rs1];
            decode.op2 = REG[rs2];
            decode.rd  = rd;
            decode.rd_write = 1;

            decode.sel = ALU_SHIFT;
        end

        17: begin
            optype = "OR";
            instr.ir = rv32_or(rd, rs1, rs2);

            decode.op1 = REG[rs1];
            decode.op2 = REG[rs2];
            decode.rd  = rd;
            decode.rd_write = 1;

            decode.sel = ALU_OR;
        end

        18: begin
            optype = "AND";
            instr.ir = rv32_and(rd, rs1, rs2);

            decode.op1 = REG[rs1];
            decode.op2 = REG[rs2];
            decode.rd  = rd;
            decode.rd_write = 1;

            decode.sel = ALU_AND;
        end

        19: begin
            optype = "LUI";
            instr.ir = rv32_lui(rd, imm);

            decode.op1 = 0;
            decode.op2 = {imm[31:12], 12'b0};
            decode.rd  = rd;
            decode.rd_write = 1;
        end

        20: begin
            optype = "AUIPC";
            instr.ir = rv32_auipc(rd, imm);

            decode.op1 = instr.pc;
            decode.op2 = {imm[31:12], 12'b0};
            decode.rd  = rd;
            decode.rd_write = 1;
        end
    endcase // instr
endtask

endmodule