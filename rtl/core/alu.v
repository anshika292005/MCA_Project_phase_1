`default_nettype none
`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// alu : 32-bit arithmetic/logic unit
//   op 000 ADD, 001 SUB, 010 AND, 011 OR        (Phase I)
//   op 100 XOR, 101 SLT (signed), 110 SLL, 111 SRL   (Phase II)
//   Shifts use b[4:0] as the shift amount, as RV32I specifies.
//   zero = 1 when the result is 0:
//     BEQ/BNE use it after a SUB (equal <=> zero),
//     BLT/BGE use it after an SLT (rs1 < rs2 <=> result 1 <=> not zero).
// -----------------------------------------------------------------------------
module alu (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [2:0]  op,
    output reg  [31:0] y,
    output wire        zero
);
    always @(*) begin
        case (op)
            3'b000:  y = a + b;
            3'b001:  y = a - b;
            3'b010:  y = a & b;
            3'b011:  y = a | b;
            3'b100:  y = a ^ b;
            3'b101:  y = {31'd0, $signed(a) < $signed(b)};
            3'b110:  y = a << b[4:0];
            default: y = a >> b[4:0];                    // 3'b111 SRL (logical)
        endcase
    end

    assign zero = (y == 32'h0000_0000);
endmodule
`default_nettype wire
