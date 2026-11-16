`default_nettype none
`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// pc_reg : program counter register
//   - synchronous reset to 0
//   - loads pc_next on the rising edge only when en = 1 (en = 0 freezes the PC)
// -----------------------------------------------------------------------------
module pc_reg (
    input  wire        clk,
    input  wire        rst,
    input  wire        en,
    input  wire [31:0] pc_next,
    output reg  [31:0] pc
);
    always @(posedge clk) begin
        if (rst)
            pc <= 32'h0000_0000;
        else if (en)
            pc <= pc_next;
    end
endmodule
`default_nettype wire
