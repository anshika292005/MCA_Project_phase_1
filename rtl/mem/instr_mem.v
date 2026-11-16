`default_nettype none
`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// instr_mem : read-only instruction memory (Harvard instruction port)
//   - DEPTH_WORDS 32-bit words, loaded from INIT_FILE with $readmemh
//   - combinational read: rdata follows addr in the same cycle
//   - byte address in, word index = addr[AW+1:2] (aligned accesses only)
// -----------------------------------------------------------------------------
module instr_mem #(
    parameter DEPTH_WORDS = 256,
    parameter INIT_FILE   = ""
) (
    input  wire [31:0] addr,
    output wire [31:0] rdata
);
    // number of word-index bits (8 for 256 words)
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
        // unused words read as 0 (all-zero is not a valid instruction -> NOP)
        for (i = 0; i < DEPTH_WORDS; i = i + 1)
            mem[i] = 32'h0000_0000;
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    assign rdata = mem[addr[AW+1:2]];
endmodule
`default_nettype wire
