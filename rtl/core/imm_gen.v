`default_nettype none
`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// imm_gen : builds the sign-extended immediate for the current instruction
//   I-type (ADDI, LW) : imm[11:0]  = instr[31:20]
//   S-type (SW)       : imm[11:0]  = {instr[31:25], instr[11:7]}
//   B-type (BEQ, BNE) : imm[12:1]  = {instr[31], instr[7], instr[30:25], instr[11:8]}, imm[0] = 0
//   instr[31] is always the sign bit.
// -----------------------------------------------------------------------------
module imm_gen (
    input  wire [31:0] instr,
    output reg  [31:0] imm
);
    always @(*) begin
        case (instr[6:0])
            7'b0010011,                                             // ADDI
            7'b0000011: imm = {{20{instr[31]}}, instr[31:20]};      // LW
            7'b0100011: imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};               // SW
            7'b1100011: imm = {{19{instr[31]}}, instr[31], instr[7], instr[30:25],
                               instr[11:8], 1'b0};                                        // BEQ/BNE
            default:    imm = 32'h0000_0000;
        endcase
    end
endmodule
`default_nettype wire
