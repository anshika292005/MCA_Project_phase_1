`default_nettype none
`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// data_mem : data RAM (Harvard data port)
//   - synchronous write on the rising edge when we = 1
//   - combinational read: rdata follows addr in the same cycle
//   - optional initial image from INIT_FILE, otherwise all zeros
// -----------------------------------------------------------------------------
module data_mem #(
    parameter DEPTH_WORDS = 256,
    parameter INIT_FILE   = ""
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
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    always @(posedge clk) begin
        if (we)
            mem[addr[AW+1:2]] <= wdata;
    end

    assign rdata = mem[addr[AW+1:2]];
endmodule
`default_nettype wire
