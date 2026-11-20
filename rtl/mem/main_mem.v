`default_nettype none
`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// main_mem : shared lower-level memory (Phase II), one port, code AND data
//
//   physical words   0..255 : program (PROG_FILE)  byte 0x000-0x3FF
//   physical words 256..511 : data    (DATA_FILE)  byte 0x400-0x7FF
//   (the same layout as the Phase I shared_mem). DATA_BASE_W moves the data
//   image (used only for the placement-sensitivity experiment).
//
// Handshake: the requester raises req (with we/addr/wdata) and holds it until
// ready = 1. ready rises in the LATENCY-th cycle of the request:
//
//     cycle      1     2   ...   L
//     req        1     1         1
//     ready      0     0         1     <- read data valid / write done at this edge
//
// LATENCY = 1 gives ready in the same cycle as req: this is the ideal
// combinational memory of Phase I.
//
// Reads return the whole aligned line (LINE_WORDS words) that contains addr,
// so a cache refill is one transfer. Writes are single words (write-through
// stores). The memory stands for block RAM or off-chip DRAM; synthesis treats
// it as a black box.
// -----------------------------------------------------------------------------
module main_mem #(
    parameter DEPTH_WORDS = 512,
    parameter LINE_WORDS  = 4,
    parameter LATENCY     = 1,          // 1..255 cycles
    parameter DATA_BASE_W = 256,        // word index of data word 0
    parameter PROG_FILE   = "",
    parameter DATA_FILE   = ""
) (
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     req,
    input  wire                     we,
    input  wire [31:0]              addr,
    input  wire [31:0]              wdata,
    output wire                     ready,
    output wire [LINE_WORDS*32-1:0] rdata
);
    reg [31:0] mem [0:DEPTH_WORDS-1];
    reg [7:0]  cnt;                     // cycles of the current request already spent

    integer i;
    initial begin
        for (i = 0; i < DEPTH_WORDS; i = i + 1)
            mem[i] = 32'h0000_0000;
        if (PROG_FILE != "")
            $readmemh(PROG_FILE, mem, 0, 255);
        if (DATA_FILE != "")
            $readmemh(DATA_FILE, mem, DATA_BASE_W, DATA_BASE_W + 255);
    end

    assign ready = req && (cnt == LATENCY - 1);

    always @(posedge clk) begin
        if (rst || !req || ready)
            cnt <= 8'd0;
        else
            cnt <= cnt + 8'd1;
    end

    wire [31:0] word      = (addr >> 2) & (DEPTH_WORDS - 1);
    wire [31:0] line_base = word & ~(LINE_WORDS - 1);

    always @(posedge clk) begin
        if (req && we && ready)
            mem[word] <= wdata;
    end

    genvar w;
    generate
        for (w = 0; w < LINE_WORDS; w = w + 1) begin : g_line
            assign rdata[w*32 +: 32] = mem[line_base + w];
        end
    endgenerate
endmodule
`default_nettype wire
