`default_nettype none
`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// shared_mem : ONE single-port memory holding both code and data (Von Neumann)
//   physical words   0..255 : program (PROG_FILE)  byte 0x000-0x3FF
//   physical words 256..511 : data    (DATA_FILE)  byte 0x400-0x7FF
//   combinational read, synchronous write, one address bus.
// Because there is only one addr input, a fetch and a data access can never
// happen in the same cycle -- that is the bottleneck we are measuring.
// -----------------------------------------------------------------------------
module shared_mem #(
    parameter DEPTH_WORDS = 512,
    parameter PROG_FILE   = "",
    parameter DATA_FILE   = ""
) (
    input  wire        clk,
    input  wire        we,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    output wire [31:0] rdata
);
    function integer clog2;
        input integer value;
        integer v;
        begin
            v = value - 1;
            for (clog2 = 0; v > 0; clog2 = clog2 + 1)
                v = v >> 1;
        end
    endfunction
    localparam AW = clog2(DEPTH_WORDS);

    reg [31:0] mem [0:DEPTH_WORDS-1];

    integer i;
    initial begin
        for (i = 0; i < DEPTH_WORDS; i = i + 1)
            mem[i] = 32'h0000_0000;
        if (PROG_FILE != "")
            $readmemh(PROG_FILE, mem, 0, 255);
        if (DATA_FILE != "")
            $readmemh(DATA_FILE, mem, 256, 511);
    end

    always @(posedge clk) begin
        if (we)
            mem[addr[AW+1:2]] <= wdata;
    end

    assign rdata = mem[addr[AW+1:2]];
endmodule
`default_nettype wire
