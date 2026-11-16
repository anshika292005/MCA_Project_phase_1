`default_nettype none
`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// alu : 32-bit arithmetic/logic unit
//   op 000 ADD, 001 SUB, 010 AND, 011 OR (others -> 0)
//   zero = 1 when the result is 0 (used by BEQ/BNE after a SUB)
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
            default: y = 32'h0000_0000;
        endcase
    end

    assign zero = (y == 32'h0000_0000);
endmodule
`default_nettype wire
