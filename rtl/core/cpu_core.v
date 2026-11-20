`default_nettype none
`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// cpu_core : single-cycle RV32I-subset processor for the Harvard system
//
// Every cycle, in one pass of combinational logic:
//   fetch   : i_addr = PC, instruction comes back on i_rdata (instruction port)
//   decode  : control + imm_gen + register reads
//   execute : ALU computes a result, a data address, or a branch compare
//   memory  : LW/SW use the data port (d_addr/d_we/d_re) IN THE SAME CYCLE
//   write   : result written to rd and PC updated on the next rising edge
//
// The core contains no memory; it only talks to the i_* and d_* ports.
//
// Phase II stall interface (both tied to 1 in harvard_top, which then behaves
// exactly as in Phase I):
//   i_ready = 0 : the instruction port has no valid instruction this cycle
//                 (I-cache miss). The core decodes a NOP and holds all state.
//   d_ready = 0 : the LW/SW of this cycle has not finished (D-cache miss,
//                 store waiting for memory). PC and register file are held,
//                 d_addr/d_we/d_re stay asserted until d_ready = 1.
//   i_req       : = ~halted, the request/enable for the instruction port.
//                 It depends only on a register, never on the fetched
//                 instruction, so it cannot form a combinational loop
//                 through the I-cache (fetched EBREAK -> is_halt -> i_req).
//
// Halt: when EBREAK is decoded, halt goes high in that cycle and the PC stops.
// The 'halted' flag keeps halt high afterwards and makes sure EBREAK is
// counted as retired exactly once (instr_done is high in the EBREAK cycle only).
// -----------------------------------------------------------------------------
module cpu_core (
    input  wire        clk,
    input  wire        rst,
    output wire [31:0] i_addr,
    output wire        i_req,
    input  wire [31:0] i_rdata,
    input  wire        i_ready,
    output wire [31:0] d_addr,
    output wire [31:0] d_wdata,
    output wire        d_we,
    output wire        d_re,
    input  wire [31:0] d_rdata,
    input  wire        d_ready,
    output wire        halt,
    output wire        instr_done
);
    localparam [31:0] NOP = 32'h0000_0013;   // addi x0, x0, 0

    wire [31:0] pc, pc_next;
    // no valid instruction yet -> execute a NOP (writes nothing, accesses nothing)
    wire [31:0] instr = i_ready ? i_rdata : NOP;

    // control signals
    wire       reg_we, alu_src, mem_re, mem_we, mem_to_reg, is_beq, is_bne, is_halt;
    wire       is_blt, is_bge, is_jal, is_jalr, is_lui;
    wire [2:0] alu_op;

    // datapath values
    wire [31:0] rs1_val, rs2_val, imm, alu_b, alu_y, wb_data;
    wire        alu_zero;

    reg halted;                       // set after EBREAK has retired

    // the LW/SW of this cycle is still waiting for the data port
    wire d_stall = (mem_re | mem_we) & ~d_ready;
    // the instruction of this cycle completes at the next rising edge
    wire advance = i_ready & ~d_stall & ~halt;

    // ---------------- fetch ----------------
    pc_reg u_pc (
        .clk    (clk),
        .rst    (rst),
        .en     (advance),            // PC freezes on a stall, in the EBREAK cycle and after
        .pc_next(pc_next),
        .pc     (pc)
    );
    assign i_addr = pc;
    assign i_req  = ~halted;

    // ---------------- decode ----------------
    control u_ctrl (
        .instr     (instr),
        .reg_we    (reg_we),
        .alu_src   (alu_src),
        .alu_op    (alu_op),
        .mem_re    (mem_re),
        .mem_we    (mem_we),
        .mem_to_reg(mem_to_reg),
        .is_beq    (is_beq),
        .is_bne    (is_bne),
        .is_halt   (is_halt),
        .is_blt    (is_blt),
        .is_bge    (is_bge),
        .is_jal    (is_jal),
        .is_jalr   (is_jalr),
        .is_lui    (is_lui)
    );

    imm_gen u_imm (
        .instr(instr),
        .imm  (imm)
    );

    regfile u_regfile (
        .clk(clk),
        .we (reg_we & advance),
        .ra1(instr[19:15]),           // rs1
        .ra2(instr[24:20]),           // rs2
        .wa (instr[11:7]),            // rd
        .wd (wb_data),
        .rd1(rs1_val),
        .rd2(rs2_val)
    );

    // ---------------- execute ----------------
    assign alu_b = alu_src ? imm : rs2_val;

    alu u_alu (
        .a   (rs1_val),
        .b   (alu_b),
        .op  (alu_op),
        .y   (alu_y),
        .zero(alu_zero)
    );

    // BEQ/BNE: ALU does rs1 - rs2, zero means equal.
    // BLT/BGE: ALU does SLT(rs1, rs2), zero means rs1 >= rs2.
    wire branch_taken = (is_beq & alu_zero) | (is_bne & ~alu_zero) |
                        (is_blt & ~alu_zero) | (is_bge & alu_zero);
    wire [31:0] pc_plus4 = pc + 32'd4;
    assign pc_next = is_jalr                ? {alu_y[31:1], 1'b0} :
                     (branch_taken | is_jal) ? (pc + imm)          : pc_plus4;

    // ---------------- memory (data port, same cycle as the fetch) -------------
    assign d_addr  = alu_y;
    assign d_wdata = rs2_val;
    assign d_we    = mem_we & ~halt;
    assign d_re    = mem_re & ~halt;

    // ---------------- write back ----------------
    assign wb_data = mem_to_reg           ? d_rdata  :
                     (is_jal | is_jalr)   ? pc_plus4 :
                     is_lui               ? imm      : alu_y;

    // ---------------- halt / retire ----------------
    always @(posedge clk) begin
        if (rst)
            halted <= 1'b0;
        else if (is_halt)
            halted <= 1'b1;
    end

    assign halt       = halted | is_halt;
    // one instruction per cycle until halted, except in stall cycles
    assign instr_done = ~halted & i_ready & ~d_stall;
endmodule
`default_nettype wire
