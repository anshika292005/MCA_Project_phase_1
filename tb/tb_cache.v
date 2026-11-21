`default_nettype none
`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// tb_cache : unit test of rtl/mem/cache.v in front of rtl/mem/main_mem.v
//
// Three caches, each with its own memory of latency L = 3:
//   wb : ENABLE = 1, WBUF = 1   (4 lines x 4 words)
//   nb : ENABLE = 1, WBUF = 0
//   un : ENABLE = 0 (uncached), WBUF = 0
// plus one uncached cache on an L = 1 memory (must behave like Phase I memory).
//
// acc() drives one access and returns how many cycles it took
// (1 = finished in the cycle it was issued). Checked:
//   1. read miss takes 1 + L cycles (penalty exactly L), the next read of the
//      same line is a hit in 1 cycle and returns the right word;
//   2. buffered store finishes in 1 cycle and reaches memory L cycles later;
//      a second store has to wait for the busy buffer;
//   3. no-write-allocate: a store miss leaves the line out of the cache, a
//      later read of it misses and sees the stored value (waits for the buffer);
//   4. conflict eviction: two lines with the same index evict each other;
//   5. store hit updates the cached line (write-through, both copies agree);
//   6. without a buffer a store takes L cycles;
//   7. uncached mode: every read goes to memory (L cycles, no refill kept);
//      with L = 1 every access finishes in its own cycle.
// -----------------------------------------------------------------------------
module tb_cache;
    localparam LW = 4, L = 3;

    reg clk = 0, rst = 1;
    always #5 clk = ~clk;

    reg         req = 0, we = 0;
    reg  [31:0] addr = 0, wdata = 0;
    reg  [1:0]  sel = 0;                     // which cache is driven

    wire [3:0]  rdy;
    wire [31:0] rd [0:3];
    wire [3:0]  refill;

    // ------------- generate the four cache + memory pairs -------------
    genvar k;
    generate
        for (k = 0; k < 4; k = k + 1) begin : g
            localparam EN  = (k == 2 || k == 3) ? 0 : 1;
            localparam WB  = (k == 0) ? 1 : 0;
            localparam LAT = (k == 3) ? 1 : L;
            wire mreq, mwe, mrdy;
            wire [31:0] maddr, mwdata;
            wire [LW*32-1:0] mrdata;
            cache #(.LINE_WORDS(LW), .NUM_LINES(4), .WBUF(WB), .ENABLE(EN)) c (
                .clk(clk), .rst(rst), .req(req & (sel == k)), .we(we), .addr(addr),
                .wdata(wdata), .ready(rdy[k]), .rdata(rd[k]),
                .mem_req(mreq), .mem_we(mwe), .mem_addr(maddr), .mem_wdata(mwdata),
                .mem_ready(mrdy), .mem_rdata(mrdata),
                .ev_refill(refill[k]), .ev_wb_stall(), .wb_busy());
            main_mem #(.DEPTH_WORDS(512), .LINE_WORDS(LW), .LATENCY(LAT)) m (
                .clk(clk), .rst(rst), .req(mreq), .we(mwe), .addr(maddr), .wdata(mwdata),
                .ready(mrdy), .rdata(mrdata));
        end
    endgenerate

    integer errors = 0, n_refill [0:3];
    integer i;
    initial for (i = 0; i < 4; i = i + 1) n_refill[i] = 0;
    always @(posedge clk) if (!rst)
        for (i = 0; i < 4; i = i + 1) if (refill[i]) n_refill[i] = n_refill[i] + 1;

    // memory word w = 0x1000_0000 + w in every memory
    integer w;
    initial begin
        #1;
        for (w = 0; w < 512; w = w + 1) begin
            g[0].m.mem[w] = 32'h1000_0000 + w;
            g[1].m.mem[w] = 32'h1000_0000 + w;
            g[2].m.mem[w] = 32'h1000_0000 + w;
            g[3].m.mem[w] = 32'h1000_0000 + w;
        end
    end

    task chk(input [8*48-1:0] what, input [31:0] got, input [31:0] exp);
        if (got !== exp) begin
            $display("FAIL %0s: got %0d (0x%h), expected %0d (0x%h)", what, got, got, exp, exp);
            errors = errors + 1;
        end
    endtask

    // one access on cache 'sel'; cyc = cycles until ready (1 = same cycle)
    integer    cyc;
    reg [31:0] q;
    task acc(input w_en, input [31:0] a, input [31:0] d);
        begin
            @(negedge clk);
            req = 1; we = w_en; addr = a; wdata = d; cyc = 1;
            #1;
            while (!rdy[sel]) begin
                @(negedge clk); #1; cyc = cyc + 1;
            end
            q = rd[sel];
            @(posedge clk); #1;
            req = 0; we = 0;
        end
    endtask

    task idle(input integer n);
        repeat (n) @(posedge clk);
    endtask

    initial begin
        $dumpfile("build/tb_cache.vcd");
        $dumpvars(0, tb_cache);
        repeat (2) @(posedge clk);
        @(negedge clk) rst = 0;

        // ---------------- 1. miss timing and hits (cache wb) ----------------
        sel = 0;
        acc(0, 32'h040, 0);                   // word 16, line 4 -> index 0, miss
        chk("1 read miss cycles (1+L)", cyc, 1 + L);
        chk("1 read miss data", q, 32'h1000_0010);
        acc(0, 32'h044, 0);                   // same line
        chk("1 hit cycles", cyc, 1);
        chk("1 hit data", q, 32'h1000_0011);
        acc(0, 32'h04C, 0);
        chk("1 hit last word", q, 32'h1000_0013);
        chk("1 refills so far", n_refill[0], 1);

        // ---------------- 2. buffered store, busy buffer ----------------
        acc(1, 32'h048, 32'hAAAA_0001);       // store hit, buffer empty
        chk("2 buffered store cycles", cyc, 1);
        chk("2 memory not yet written", g[0].m.mem[18], 32'h1000_0012);
        acc(1, 32'h04C, 32'hAAAA_0002);       // buffer still draining -> waits
        chk("2 store to busy buffer cycles", cyc, L - 1);
        chk("2 first store reached memory", g[0].m.mem[18], 32'hAAAA_0001);
        acc(0, 32'h048, 0);                   // read hit sees its own store
        chk("5 store hit updated line", q, 32'hAAAA_0001);
        chk("5 read hit while buffer busy", cyc, 1);
        idle(L + 1);
        chk("2 second store reached memory", g[0].m.mem[19], 32'hAAAA_0002);
        acc(0, 32'h04C, 0);
        chk("5 cache and memory agree", q, 32'hAAAA_0002);

        // ---------------- 3. no-write-allocate ----------------
        acc(1, 32'h100, 32'hBBBB_0001);       // word 64, line 16 -> index 0: miss, not allocated
        chk("3 store miss cycles (buffer)", cyc, 1);
        acc(0, 32'h044, 0);                   // line 4 still cached?
        chk("3 old line kept (hit)", cyc, 1);
        acc(0, 32'h040, 0);                   // same offset as the store: must be untouched
        chk("3 store miss did not touch line", q, 32'h1000_0010);
        chk("3 same-offset word hit", cyc, 1);
        chk("3 store miss reached memory", g[0].m.mem[64], 32'hBBBB_0001);
        // read-after-write: store miss to line 32 (index 0), then read it back AT ONCE,
        // while the store is still in the buffer. The read must wait for the drain.
        acc(1, 32'h200, 32'hBBBB_0002);
        chk("3 second store miss cycles", cyc, 1);
        acc(0, 32'h200, 0);
        chk("3 read after store miss = miss", n_refill[0], 2);
        chk("3 read sees buffered store (RAW)", q, 32'hBBBB_0002);
        chk("3 read waited for buffer + L", (cyc >= 1 + L), 1);

        // ---------------- 4. conflict eviction ----------------
        acc(0, 32'h040, 0);                   // line 4 (evicted by line 32) -> miss
        chk("4 evicted line misses", cyc, 1 + L);
        acc(0, 32'h100, 0);                   // line 16 -> miss again
        chk("4 conflict miss again", cyc, 1 + L);
        chk("4 refilled line has the store", q, 32'hBBBB_0001);
        acc(0, 32'h010, 0);                   // line 1 -> index 1, other index
        acc(0, 32'h100, 0);                   // still cached
        chk("4 other index does not evict", cyc, 1);
        chk("4 refill count", n_refill[0], 5);

        // ---------------- 6. store without buffer (cache nb) ----------------
        sel = 1;
        acc(0, 32'h040, 0);
        chk("6 nb read miss cycles", cyc, 1 + L);
        acc(1, 32'h040, 32'hCCCC_0001);
        chk("6 nb store cycles = L", cyc, L);
        chk("6 nb memory written", g[1].m.mem[16], 32'hCCCC_0001);
        acc(0, 32'h040, 0);
        chk("6 nb store hit updated line", q, 32'hCCCC_0001);
        chk("6 nb hit", cyc, 1);

        // ---------------- 7. uncached (cache un, L = 3) ----------------
        sel = 2;
        acc(0, 32'h040, 0);
        chk("7 uncached read cycles = L", cyc, L);
        chk("7 uncached data", q, 32'h1000_0010);
        acc(0, 32'h040, 0);
        chk("7 uncached never hits", cyc, L);
        acc(1, 32'h044, 32'hDDDD_0001);
        chk("7 uncached store cycles = L", cyc, L);
        acc(0, 32'h044, 0);
        chk("7 uncached reads memory", q, 32'hDDDD_0001);

        // ---------------- 7b. uncached with L = 1 = ideal memory ----------------
        sel = 3;
        acc(0, 32'h040, 0);
        chk("7b L=1 read in one cycle", cyc, 1);
        acc(1, 32'h040, 32'hEEEE_0001);
        chk("7b L=1 store in one cycle", cyc, 1);
        acc(0, 32'h040, 0);
        chk("7b L=1 read back", q, 32'hEEEE_0001);

        if (errors == 0) $display("tb_cache: PASS");
        else             $display("tb_cache: FAIL (%0d errors)", errors);
        $finish;
    end
endmodule
`default_nettype wire
