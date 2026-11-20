`default_nettype none
`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// control : main decoder. Looks at opcode/funct3/funct7 and drives the datapath.
//
//   instr        reg_we alu_src alu_op mem_re mem_we mem_to_reg  extra
//   ADD/SUB/AND/OR  1      0    op       0      0       0
//   XOR/SLT/SLL/SRL 1      0    op       0      0       0        (Phase II)
//   ADDI            1      1    ADD      0      0       0
//   XORI/SLTI       1      1    XOR/SLT  0      0       0        (Phase II)
//   SLLI/SRLI       1      1    SLL/SRL  0      0       0        (Phase II, funct7 = 0)
//   LW              1      1    ADD      1      0       1
//   SW              0      1    ADD      0      1       0
//   BEQ/BNE         0      0    SUB      0      0       0        is_beq / is_bne
//   BLT/BGE         0      0    SLT      0      0       0        is_blt / is_bge (Phase II)
//   JAL             1      -     -       0      0       0        is_jal : rd = PC+4, PC = PC+immJ
//   JALR            1      1    ADD      0      0       0        is_jalr: rd = PC+4, PC = (rs1+imm)&~1
//   LUI             1      -     -       0      0       0        is_lui : rd = immU
//   EBREAK          0      0     -       0      0       0        is_halt
//   other           all zero (behaves as a NOP)
//
// The Phase I outputs keep their exact meaning, so a datapath that ignores
// the new outputs still executes the Phase I subset unchanged.
// -----------------------------------------------------------------------------
module control (
    input  wire [31:0] instr,
    output reg         reg_we,
    output reg         alu_src,
    output reg  [2:0]  alu_op,
    output reg         mem_re,
    output reg         mem_we,
    output reg         mem_to_reg,
    output reg         is_beq,
    output reg         is_bne,
    output reg         is_halt,
    output reg         is_blt,
    output reg         is_bge,
    output reg         is_jal,
    output reg         is_jalr,
    output reg         is_lui
);
    localparam ALU_ADD = 3'b000, ALU_SUB = 3'b001, ALU_AND = 3'b010, ALU_OR  = 3'b011,
               ALU_XOR = 3'b100, ALU_SLT = 3'b101, ALU_SLL = 3'b110, ALU_SRL = 3'b111;

    wire [6:0] opcode = instr[6:0];
    wire [2:0] funct3 = instr[14:12];
    wire [6:0] funct7 = instr[31:25];

    always @(*) begin
        // defaults = NOP
        reg_we     = 1'b0;
        alu_src    = 1'b0;
        alu_op     = ALU_ADD;
        mem_re     = 1'b0;
        mem_we     = 1'b0;
        mem_to_reg = 1'b0;
        is_beq     = 1'b0;
        is_bne     = 1'b0;
        is_halt    = 1'b0;
        is_blt     = 1'b0;
        is_bge     = 1'b0;
        is_jal     = 1'b0;
        is_jalr    = 1'b0;
        is_lui     = 1'b0;

        if (instr == 32'h0010_0073) begin
            is_halt = 1'b1;                                         // EBREAK
        end else begin
            case (opcode)
                7'b0110011: begin                                   // R-type
                    case ({funct7, funct3})
                        {7'b0000000, 3'b000}: begin reg_we = 1'b1; alu_op = ALU_ADD; end
                        {7'b0100000, 3'b000}: begin reg_we = 1'b1; alu_op = ALU_SUB; end
                        {7'b0000000, 3'b111}: begin reg_we = 1'b1; alu_op = ALU_AND; end
                        {7'b0000000, 3'b110}: begin reg_we = 1'b1; alu_op = ALU_OR;  end
                        {7'b0000000, 3'b100}: begin reg_we = 1'b1; alu_op = ALU_XOR; end
                        {7'b0000000, 3'b010}: begin reg_we = 1'b1; alu_op = ALU_SLT; end
                        {7'b0000000, 3'b001}: begin reg_we = 1'b1; alu_op = ALU_SLL; end
                        {7'b0000000, 3'b101}: begin reg_we = 1'b1; alu_op = ALU_SRL; end
                        default: ;                                  // NOP
                    endcase
                end
                7'b0010011: begin                                   // I-type ALU
                    case (funct3)
                        3'b000: begin reg_we = 1'b1; alu_src = 1'b1; alu_op = ALU_ADD; end  // ADDI
                        3'b100: begin reg_we = 1'b1; alu_src = 1'b1; alu_op = ALU_XOR; end  // XORI
                        3'b010: begin reg_we = 1'b1; alu_src = 1'b1; alu_op = ALU_SLT; end  // SLTI
                        3'b001: if (funct7 == 7'b0000000) begin                             // SLLI
                                    reg_we = 1'b1; alu_src = 1'b1; alu_op = ALU_SLL;
                                end
                        3'b101: if (funct7 == 7'b0000000) begin                             // SRLI
                                    reg_we = 1'b1; alu_src = 1'b1; alu_op = ALU_SRL;
                                end
                        default: ;                                  // NOP
                    endcase
                end
                7'b0000011: if (funct3 == 3'b010) begin             // LW
                    reg_we = 1'b1; alu_src = 1'b1; mem_re = 1'b1; mem_to_reg = 1'b1;
                end
                7'b0100011: if (funct3 == 3'b010) begin             // SW
                    alu_src = 1'b1; mem_we = 1'b1;
                end
                7'b1100011: begin                                   // branches
                    case (funct3)
                        3'b000: begin alu_op = ALU_SUB; is_beq = 1'b1; end
                        3'b001: begin alu_op = ALU_SUB; is_bne = 1'b1; end
                        3'b100: begin alu_op = ALU_SLT; is_blt = 1'b1; end
                        3'b101: begin alu_op = ALU_SLT; is_bge = 1'b1; end
                        default: alu_op = ALU_SUB;                  // NOP
                    endcase
                end
                7'b1101111: begin                                   // JAL
                    reg_we = 1'b1; is_jal = 1'b1;
                end
                7'b1100111: if (funct3 == 3'b000) begin             // JALR
                    reg_we = 1'b1; alu_src = 1'b1; is_jalr = 1'b1;
                end
                7'b0110111: begin                                   // LUI
                    reg_we = 1'b1; is_lui = 1'b1;
                end
                default: ;                                          // NOP
            endcase
        end
    end
endmodule
`default_nettype wire
