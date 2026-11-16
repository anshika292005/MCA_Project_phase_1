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
// Halt: when EBREAK is decoded, halt goes high in that cycle and the PC stops.
// The 'halted' flag keeps halt high afterwards and makes sure EBREAK is
// counted as retired exactly once (instr_done is high in the EBREAK cycle only).
// -----------------------------------------------------------------------------
module cpu_core (
    input  wire        clk,
    input  wire        rst,
    output wire [31:0] i_addr,
    input  wire [31:0] i_rdata,
    output wire [31:0] d_addr,
    output wire [31:0] d_wdata,
    output wire        d_we,
    output wire        d_re,
    input  wire [31:0] d_rdata,
    output wire        halt,
    output wire        instr_done
);
    wire [31:0] pc, pc_next;
    wire [31:0] instr = i_rdata;

    // control signals
    wire       reg_we, alu_src, mem_re, mem_we, mem_to_reg, is_beq, is_bne, is_halt;
    wire [2:0] alu_op;

    // datapath values
    wire [31:0] rs1_val, rs2_val, imm, alu_b, alu_y, wb_data;
    wire        alu_zero;

    reg halted;                       // set after EBREAK has retired

    // ---------------- fetch ----------------
    pc_reg u_pc (
        .clk    (clk),
        .rst    (rst),
        .en     (~halt),              // PC freezes in the EBREAK cycle and after
        .pc_next(pc_next),
        .pc     (pc)
    );
    assign i_addr = pc;

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
        .is_halt   (is_halt)
    );

    imm_gen u_imm (
        .instr(instr),
        .imm  (imm)
    );

    regfile u_regfile (
        .clk(clk),
        .we (reg_we & ~halt),
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

    // branch: ALU does rs1 - rs2, zero flag means equal
    wire branch_taken = (is_beq & alu_zero) | (is_bne & ~alu_zero);
    assign pc_next = branch_taken ? (pc + imm) : (pc + 32'd4);

    // ---------------- memory (data port, same cycle as the fetch) -------------
    assign d_addr  = alu_y;
    assign d_wdata = rs2_val;
    assign d_we    = mem_we & ~halt;
    assign d_re    = mem_re & ~halt;

    // ---------------- write back ----------------
    assign wb_data = mem_to_reg ? d_rdata : alu_y;

    // ---------------- halt / retire ----------------
    always @(posedge clk) begin
        if (rst)
            halted <= 1'b0;
        else if (is_halt)
            halted <= 1'b1;
    end

    assign halt       = halted | is_halt;
    assign instr_done = ~halted;      // one instruction per cycle until halted
endmodule
`default_nettype wire
