`default_nettype none
`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// control : main decoder. Looks at opcode/funct3/funct7 and drives the datapath.
//
//   instr   reg_we alu_src alu_op mem_re mem_we mem_to_reg  branch  halt
//   ADD       1      0     ADD     0      0       0          -       -
//   SUB       1      0     SUB     0      0       0          -       -
//   AND       1      0     AND     0      0       0          -       -
//   OR        1      0     OR      0      0       0          -       -
//   ADDI      1      1     ADD     0      0       0          -       -
//   LW        1      1     ADD     1      0       1          -       -
//   SW        0      1     ADD     0      1       0          -       -
//   BEQ/BNE   0      0     SUB     0      0       0        is_beq/bne -
//   EBREAK    0      0      -      0      0       0          -       1
//   other     all zero (behaves as a NOP)
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
    output reg         is_halt
);
    localparam ALU_ADD = 3'b000, ALU_SUB = 3'b001, ALU_AND = 3'b010, ALU_OR = 3'b011;

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
                        default: ;                                  // NOP
                    endcase
                end
                7'b0010011: if (funct3 == 3'b000) begin             // ADDI
                    reg_we = 1'b1; alu_src = 1'b1;
                end
                7'b0000011: if (funct3 == 3'b010) begin             // LW
                    reg_we = 1'b1; alu_src = 1'b1; mem_re = 1'b1; mem_to_reg = 1'b1;
                end
                7'b0100011: if (funct3 == 3'b010) begin             // SW
                    alu_src = 1'b1; mem_we = 1'b1;
                end
                7'b1100011: begin                                   // BEQ / BNE
                    alu_op = ALU_SUB;
                    if (funct3 == 3'b000) is_beq = 1'b1;
                    if (funct3 == 3'b001) is_bne = 1'b1;
                end
                default: ;                                          // NOP
            endcase
        end
    end
endmodule
`default_nettype wire
