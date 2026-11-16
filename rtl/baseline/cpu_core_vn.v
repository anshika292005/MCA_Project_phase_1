`default_nettype none
`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// cpu_core_vn : same instruction behaviour as cpu_core, but with ONE memory bus
//
// Two-state FSM:
//
//             non-memory instr (ALU, branch, EBREAK): done, PC updated
//            +-----+
//            |     v
//         +------------+   LW / SW: latch instr   +-------+
//   rst ->| FETCH_EXEC |------------------------->|  MEM  |
//         +------------+ <------------------------+-------+
//                         data access done, PC+4
//
//   FETCH_EXEC : bus carries the PC (instruction fetch). ALU/branch/EBREAK
//                finish here. LW/SW cannot use the bus again this cycle, so
//                the instruction is latched in 'ir' and we go to MEM.
//   MEM        : bus carries the data address (m_is_data = 1). SW writes, LW
//                reads and writes the register; the PC advances.
//
// The register file is not written in FETCH_EXEC for LW/SW, so in MEM the
// same rs1/rs2 values are read again and the ALU recomputes the address from
// the latched instruction.
// -----------------------------------------------------------------------------
module cpu_core_vn (
    input  wire        clk,
    input  wire        rst,
    output wire [31:0] m_addr,
    output wire [31:0] m_wdata,
    output wire        m_we,
    output wire        m_re,
    output wire        m_is_data,
    input  wire [31:0] m_rdata,
    output wire        halt,
    output wire        instr_done
);
    localparam FETCH_EXEC = 1'b0, MEM = 1'b1;

    reg        state;
    reg [31:0] pc;
    reg [31:0] ir;          // instruction latched for the MEM cycle
    reg        halted;

    // in FETCH_EXEC the instruction arrives on the bus; in MEM use the latched one
    wire [31:0] instr = (state == MEM) ? ir : m_rdata;

    wire       reg_we, alu_src, mem_re, mem_we, mem_to_reg, is_beq, is_bne, is_halt;
    wire [2:0] alu_op;
    wire [31:0] rs1_val, rs2_val, imm, alu_y, wb_data;
    wire        alu_zero;

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

    wire is_mem_op = mem_re | mem_we;

    // register write: non-memory instrs in FETCH_EXEC, LW in MEM
    wire rf_we = ~halt & reg_we & ((state == FETCH_EXEC) ? ~is_mem_op : 1'b1);

    regfile u_regfile (
        .clk(clk),
        .we (rf_we),
        .ra1(instr[19:15]),
        .ra2(instr[24:20]),
        .wa (instr[11:7]),
        .wd (wb_data),
        .rd1(rs1_val),
        .rd2(rs2_val)
    );

    alu u_alu (
        .a   (rs1_val),
        .b   (alu_src ? imm : rs2_val),
        .op  (alu_op),
        .y   (alu_y),
        .zero(alu_zero)
    );

    assign wb_data = mem_to_reg ? m_rdata : alu_y;

    wire branch_taken = (is_beq & alu_zero) | (is_bne & ~alu_zero);

    // ---------------- the single memory bus ----------------
    assign m_is_data = (state == MEM);
    assign m_addr    = (state == MEM) ? alu_y : pc;      // data address or PC
    assign m_wdata   = rs2_val;
    assign m_we      = (state == MEM) & mem_we;
    assign m_re      = (state == MEM) ? mem_re : ~halted; // fetch read until halted

    // ---------------- halt / retire ----------------
    assign halt       = halted | ((state == FETCH_EXEC) & is_halt);
    assign instr_done = ~halted & ((state == MEM) | ~is_mem_op);

    // ---------------- state, PC, latched instruction ----------------
    always @(posedge clk) begin
        if (rst) begin
            state  <= FETCH_EXEC;
            pc     <= 32'h0000_0000;
            ir     <= 32'h0000_0000;
            halted <= 1'b0;
        end else if (state == FETCH_EXEC) begin
            if (halt) begin
                halted <= 1'b1;                          // EBREAK: PC frozen
            end else if (is_mem_op) begin
                ir    <= m_rdata;                        // keep LW/SW for MEM
                state <= MEM;                            // PC waits
            end else begin
                pc <= branch_taken ? (pc + imm) : (pc + 32'd4);
            end
        end else begin                                   // MEM
            pc    <= pc + 32'd4;
            state <= FETCH_EXEC;
        end
    end
endmodule
`default_nettype wire
