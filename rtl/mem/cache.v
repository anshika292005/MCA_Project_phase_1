`default_nettype none
`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// cache : one reusable direct-mapped cache (Phase II)
//
// Used three ways: I-cache and D-cache of the modified Harvard system, and the
// unified cache of the single-bus system. ENABLE = 0 turns it into an uncached
// pass-through (the "no cache" system), with the same write buffer option.
//
//   organisation : NUM_LINES lines of LINE_WORDS 32-bit words (both powers of 2),
//                  direct-mapped, one valid bit and one tag per line
//   reads        : hit  -> completes in the same cycle (combinational array read)
//                  miss -> fetches the whole line from the lower level, writes it
//                          into the array, and completes as a hit in the NEXT cycle.
//                          The core waits exactly LATENCY cycles (the miss penalty).
//                          Refill data is NOT forwarded to the core: forwarding would
//                          close a combinational loop memory -> core -> next address
//                          -> arbiter -> memory.
//   writes       : write-through, no-write-allocate. A write hit also updates the
//                  line; a write miss leaves the cache unchanged.
//   write buffer : WBUF = 1 adds a one-entry buffer. A store completes as soon as
//                  the buffer is free (or frees in this very cycle). If the buffer
//                  is empty, the store is offered to memory at once; if memory
//                  does not finish it in this cycle, the buffer captures it and
//                  keeps the same request up until memory is done (the latency
//                  count simply continues). So with LATENCY = 1 the buffer is
//                  never used, and a store never costs more than without it.
//                  WBUF = 0: the store waits for memory.
//                  A read miss waits until the buffer is empty, so the line it
//                  fetches already contains the buffered store (no RAW hazard).
//   uncached     : ENABLE = 0. Every read goes to memory and its word is passed
//                  straight back (rdata = memory data, ready = memory ready), so
//                  with LATENCY = 1 it behaves exactly like the ideal Phase I memory.
//
// Address split (byte address, only the low ABITS bits are used):
//   [1:0] byte (ignored, word accesses) | offset (log2 LINE_WORDS) |
//   index (log2 NUM_LINES) | tag (the rest of ABITS)
// The fields are computed with shifts and masks on 32-bit values, so
// LINE_WORDS = 1 or NUM_LINES = 1 (zero-width fields) work as well.
// -----------------------------------------------------------------------------
module cache #(
    parameter LINE_WORDS = 4,       // words per line (power of 2)
    parameter NUM_LINES  = 8,       // lines (power of 2)
    parameter WBUF       = 1,       // 1 = one-entry write buffer
    parameter ENABLE     = 1,       // 0 = uncached pass-through
    parameter ABITS      = 12       // physical byte-address bits (4 KB space)
) (
    input  wire                     clk,
    input  wire                     rst,
    // core side: hold req/we/addr/wdata stable until ready
    input  wire                     req,
    input  wire                     we,
    input  wire [31:0]              addr,
    input  wire [31:0]              wdata,
    output wire                     ready,
    output wire [31:0]              rdata,
    // lower-level side: line read / word write, request held until mem_ready
    output wire                     mem_req,
    output wire                     mem_we,
    output wire [31:0]              mem_addr,
    output wire [31:0]              mem_wdata,
    input  wire                     mem_ready,
    input  wire [LINE_WORDS*32-1:0] mem_rdata,
    // events for the performance counters
    output wire                     ev_refill,    // 1-cycle pulse: a line (or uncached word) arrived
    output wire                     ev_wb_stall,  // this cycle the access waits for the write buffer
    output wire                     wb_busy       // write buffer holds a store
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

    localparam OW = clog2(LINE_WORDS);
    localparam IW = clog2(NUM_LINES);
    localparam TW = ABITS - 2 - OW - IW;          // must be >= 1
    localparam LW = LINE_WORDS * 32;

    // ---------------- address fields ----------------
    wire [31:0] word_addr = {2'b00, addr[31:2]} & ((32'd1 << (ABITS - 2)) - 32'd1);
    wire [31:0] line_addr = word_addr >> OW;
    wire [31:0] off       = word_addr & (LINE_WORDS - 1);
    wire [31:0] idx       = line_addr & (NUM_LINES - 1);
    wire [31:0] tag_full  = line_addr >> IW;
    wire [TW-1:0] tag     = tag_full[TW-1:0];

    // ---------------- storage ----------------
    reg [LW-1:0]        lines [0:NUM_LINES-1];
    reg [TW-1:0]        tags  [0:NUM_LINES-1];
    reg [NUM_LINES-1:0] valid;

    reg        wb_valid;
    reg [31:0] wb_addr, wb_data;

    wire [LW-1:0] line_q   = lines[idx];
    wire [31:0]   hit_word = line_q[off*32 +: 32];
    wire [31:0]   mem_word = mem_rdata[off*32 +: 32];

    wire hit = (ENABLE != 0) && valid[idx] && (tags[idx] == tag);

    // ---------------- control ----------------
    wire is_rd = req & ~we;
    wire is_wr = req &  we;

    // users of the lower-level port (at most one at a time)
    wire drain     = (WBUF != 0) & wb_valid;              // write buffer -> memory
    wire wr_direct = (WBUF == 0) & is_wr;                 // store without a buffer
    wire wr_try    = (WBUF != 0) & is_wr & ~wb_valid;     // empty buffer: offer store to memory now
    wire rd_mem    = is_rd & ~hit & ~wb_valid;            // refill / uncached read

    assign mem_req   = drain | wr_direct | wr_try | rd_mem;
    assign mem_we    = drain | wr_direct | wr_try;
    assign mem_addr  = drain ? wb_addr : addr;
    assign mem_wdata = drain ? wb_data : wdata;

    wire drain_done  = drain & mem_ready;
    wire wr_try_done = wr_try & mem_ready;                // store finished without the buffer
    wire wb_free     = ~wb_valid | drain_done;

    wire ready_rd = (ENABLE != 0) ? hit : (rd_mem & mem_ready);
    wire ready_wr = (WBUF != 0) ? wb_free : mem_ready;

    assign ready = is_rd ? ready_rd : (is_wr ? ready_wr : 1'b1);
    assign rdata = (ENABLE != 0) ? hit_word : mem_word;

    // ---------------- array updates ----------------
    wire do_refill = (ENABLE != 0) & rd_mem & mem_ready;
    wire do_wupd   = (ENABLE != 0) & is_wr & ready_wr & hit;

    // write hit: replace one word of the line (read-modify-write of one line)
    wire [LW-1:0] ones32 = 32'hFFFF_FFFF;
    wire [LW-1:0] wdat32 = wdata;
    wire [LW-1:0] wmask  = ones32 << (off * 32);
    wire [LW-1:0] merged = (line_q & ~wmask) | ((wdat32 << (off * 32)) & wmask);

    always @(posedge clk) begin
        if (do_refill | do_wupd)
            lines[idx] <= do_refill ? mem_rdata : merged;
        if (do_refill)
            tags[idx] <= tag;
    end

    always @(posedge clk) begin
        if (rst)
            valid <= {NUM_LINES{1'b0}};
        else if (do_refill)
            valid[idx] <= 1'b1;
    end

    // ---------------- write buffer ----------------
    always @(posedge clk) begin
        if (rst || WBUF == 0) begin
            wb_valid <= 1'b0;
            wb_addr  <= 32'd0;
            wb_data  <= 32'd0;
        end else begin
            if (is_wr & wb_free & ~wr_try_done) begin     // capture (possibly as the old one leaves)
                wb_valid <= 1'b1;
                wb_addr  <= addr;
                wb_data  <= wdata;
            end else if (drain_done) begin
                wb_valid <= 1'b0;
            end
        end
    end

    // ---------------- events ----------------
    assign ev_refill   = rd_mem & mem_ready;
    assign ev_wb_stall = (WBUF != 0) & ((is_wr & ~wb_free) | (is_rd & ~hit & wb_valid));
    assign wb_busy     = wb_valid;
endmodule
`default_nettype wire
