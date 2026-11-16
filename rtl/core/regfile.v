`default_nettype none
`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// regfile : 32 x 32-bit register file
//   - two combinational read ports (rs1, rs2)
//   - one synchronous write port (rd), written on the rising edge when we = 1
//   - x0 is hard-wired to zero: writes to it are ignored, reads return 0
// -----------------------------------------------------------------------------
module regfile (
    input  wire        clk,
    input  wire        we,
    input  wire [4:0]  ra1,
    input  wire [4:0]  ra2,
    input  wire [4:0]  wa,
    input  wire [31:0] wd,
    output wire [31:0] rd1,
    output wire [31:0] rd2
);
    reg [31:0] regs [0:31];

    integer i;
    initial begin
        for (i = 0; i < 32; i = i + 1)
            regs[i] = 32'h0000_0000;
    end

    always @(posedge clk) begin
        if (we && (wa != 5'd0))
            regs[wa] <= wd;
    end

    assign rd1 = (ra1 == 5'd0) ? 32'h0000_0000 : regs[ra1];
    assign rd2 = (ra2 == 5'd0) ? 32'h0000_0000 : regs[ra2];
endmodule
`default_nettype wire
