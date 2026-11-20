`default_nettype none
`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// mh_top : modified Harvard system (Phase II)
//
//              i_addr/i_req  +---------+  line refill
//        +------------------>| I-cache |<-------------+
//        |   i_rdata/i_ready +---------+              |    +---------+   +----------+
//   +----------+                                      +--->|         |   |          |
//   | cpu_core |                                           | arbiter |-->| main_mem |
//   +----------+  d_addr  +---------+ RAM +---------+ +--->| (I > D) |   | code and |
//        |  ------------->| decoder |---->| D-cache |-+    +---------+   | data, L  |
//        |  <-------------| rw_ctrl |     +---------+                    | cycles)  |
//        |                +---------+--> out_port (IO), fault: bypass    +----------+
//
// The core still has separate instruction and data ports (Harvard at L1),
// but both caches refill from ONE shared memory through the arbiter.
//
//   * I-cache : read only, no write buffer. Its request is i_req = ~halted,
//               a register, so a fetched EBREAK cannot loop back into it.
//   * D-side  : the Phase I addr_decoder and rw_ctrl split the data space.
//               Only data-RAM accesses (0x000-0x3FF) go to the D-cache, at
//               physical address d_addr + 0x400. out_port (0x400) and invalid
//               addresses bypass the cache and finish in their cycle.
//   * Timing rule: neither cache forwards refill data to the core, so there
//               is no combinational path memory -> core -> request address.
//
// With LATENCY = 1 a miss still costs one cycle (refill, then hit), so this
// system is slower than the ideal harvard_top even at L = 1; that is the cost
// of having a real, shared memory behind small caches.
// -----------------------------------------------------------------------------
module mh_top #(
    parameter PROG_FILE  = "",
    parameter DATA_FILE  = "",
    parameter LINE_WORDS = 4,
    parameter I_LINES    = 8,
    parameter D_LINES    = 8,
    parameter WBUF       = 1,
    parameter LATENCY    = 1,
    // physical byte address of data word 0. 0x400 everywhere except in the
    // placement-sensitivity experiment, which uses 0x480 and a 1024-word memory.
    parameter DATA_BASE  = 32'h0000_0400,
    parameter MEM_WORDS  = 512
) (
    input  wire        clk,
    input  wire        rst,
    output wire        halt,
    output reg  [31:0] out_port,
    output wire [31:0] cycle_count,
    output wire [31:0] instr_count,
    output wire [31:0] d_access_count,
    output wire [31:0] simul_count,
    output wire        d_fault,
    output wire [31:0] i_miss_count,
    output wire [31:0] d_miss_count,
    output wire [31:0] i_stall_count,
    output wire [31:0] d_stall_count,
    output wire [31:0] wb_stall_count,
    output wire [31:0] conflict_count
);
    localparam LWB = LINE_WORDS * 32;

    // core <-> L1
    wire [31:0] i_addr, i_rdata, d_addr, d_wdata, d_rdata;
    wire        i_req, i_ready, d_we, d_re, d_ready, instr_done;
    // decoder / rw_ctrl
    wire        sel_ram, sel_io, addr_fault, io_we;
    // D-cache
    wire [31:0] dc_rdata;
    wire        dc_ready, dc_req;
    // L1 <-> arbiter
    wire        ic_mreq, ic_mwe, ic_mready, dc_mreq, dc_mwe, dc_mready;
    wire [31:0] ic_maddr, ic_mwdata, dc_maddr, dc_mwdata;
    // arbiter <-> memory
    wire        m_req, m_we, m_ready;
    wire [31:0] m_addr, m_wdata;
    wire [LWB-1:0] m_rdata;
    // events
    wire        ic_refill, dc_refill, dc_wb_stall, conflict, ic_wb_stall_unused;
    wire        ic_wb_busy_unused, dc_wb_busy;

    cpu_core u_core (
        .clk       (clk),
        .rst       (rst),
        .i_addr    (i_addr),
        .i_req     (i_req),
        .i_rdata   (i_rdata),
        .i_ready   (i_ready),
        .d_addr    (d_addr),
        .d_wdata   (d_wdata),
        .d_we      (d_we),
        .d_re      (d_re),
        .d_rdata   (d_rdata),
        .d_ready   (d_ready),
        .halt      (halt),
        .instr_done(instr_done)
    );

    // ---------------- instruction side ----------------
    cache #(.LINE_WORDS(LINE_WORDS), .NUM_LINES(I_LINES), .WBUF(0), .ENABLE(1)) u_icache (
        .clk        (clk),
        .rst        (rst),
        .req        (i_req),
        .we         (1'b0),
        .addr       (i_addr),
        .wdata      (32'd0),
        .ready      (i_ready),
        .rdata      (i_rdata),
        .mem_req    (ic_mreq),
        .mem_we     (ic_mwe),
        .mem_addr   (ic_maddr),
        .mem_wdata  (ic_mwdata),
        .mem_ready  (ic_mready),
        .mem_rdata  (m_rdata),
        .ev_refill  (ic_refill),
        .ev_wb_stall(ic_wb_stall_unused),
        .wb_busy    (ic_wb_busy_unused)
    );

    // ---------------- data side ----------------
    addr_decoder u_dec (
        .addr      (d_addr),
        .sel_ram   (sel_ram),
        .sel_io    (sel_io),
        .addr_fault(addr_fault)
    );

    rw_ctrl u_rw (
        .d_we     (d_we),
        .d_re     (d_re),
        .sel_ram  (sel_ram),
        .sel_io   (sel_io),
        .ram_rdata(dc_rdata),
        .ram_we   (),                 // the D-cache takes d_we itself
        .io_we    (io_we),
        .d_rdata  (d_rdata)
    );

    assign dc_req  = (d_re | d_we) & sel_ram;
    assign d_ready = dc_ready;        // 1 whenever the D-cache is not used (IO, fault, no access)

    cache #(.LINE_WORDS(LINE_WORDS), .NUM_LINES(D_LINES), .WBUF(WBUF), .ENABLE(1)) u_dcache (
        .clk        (clk),
        .rst        (rst),
        .req        (dc_req),
        .we         (d_we),
        .addr       (d_addr + DATA_BASE),       // data RAM lives at physical 0x400-0x7FF
        .wdata      (d_wdata),
        .ready      (dc_ready),
        .rdata      (dc_rdata),
        .mem_req    (dc_mreq),
        .mem_we     (dc_mwe),
        .mem_addr   (dc_maddr),
        .mem_wdata  (dc_mwdata),
        .mem_ready  (dc_mready),
        .mem_rdata  (m_rdata),
        .ev_refill  (dc_refill),
        .ev_wb_stall(dc_wb_stall),
        .wb_busy    (dc_wb_busy)
    );

    always @(posedge clk) begin
        if (rst)
            out_port <= 32'h0000_0000;
        else if (io_we)
            out_port <= d_wdata;
    end

    assign d_fault = (d_we | d_re) & addr_fault;

    // ---------------- shared lower level ----------------
    arbiter u_arb (
        .clk     (clk),
        .rst     (rst),
        .i_req   (ic_mreq),
        .i_we    (ic_mwe),
        .i_addr  (ic_maddr),
        .i_wdata (ic_mwdata),
        .i_ready (ic_mready),
        .d_req   (dc_mreq),
        .d_we    (dc_mwe),
        .d_addr  (dc_maddr),
        .d_wdata (dc_mwdata),
        .d_ready (dc_mready),
        .m_req   (m_req),
        .m_we    (m_we),
        .m_addr  (m_addr),
        .m_wdata (m_wdata),
        .m_ready (m_ready),
        .conflict(conflict)
    );

    main_mem #(.DEPTH_WORDS(MEM_WORDS), .LINE_WORDS(LINE_WORDS), .LATENCY(LATENCY),
               .DATA_BASE_W(DATA_BASE / 4),
               .PROG_FILE(PROG_FILE), .DATA_FILE(DATA_FILE)) u_mem (
        .clk  (clk),
        .rst  (rst),
        .req  (m_req),
        .we   (m_we),
        .addr (m_addr),
        .wdata(m_wdata),
        .ready(m_ready),
        .rdata(m_rdata)
    );

    // ---------------- counters ----------------
    perf_counters u_perf (
        .clk           (clk),
        .rst           (rst),
        .halt          (halt),
        .instr_done    (instr_done),
        .i_access      (i_req & i_ready),
        .d_access      ((d_we | d_re) & d_ready),
        .cycle_count   (cycle_count),
        .instr_count   (instr_count),
        .d_access_count(d_access_count),
        .simul_count   (simul_count)
    );

    event_counters u_ev (
        .clk           (clk),
        .rst           (rst),
        .halt          (halt),
        .i_miss        (ic_refill),
        .d_miss        (dc_refill),
        .i_stall       (i_req & ~i_ready),
        .d_stall       (i_ready & (d_we | d_re) & ~d_ready),
        .wb_stall      (dc_wb_stall),
        .conflict      (conflict),
        .i_miss_count  (i_miss_count),
        .d_miss_count  (d_miss_count),
        .i_stall_count (i_stall_count),
        .d_stall_count (d_stall_count),
        .wb_stall_count(wb_stall_count),
        .conflict_count(conflict_count)
    );
endmodule
`default_nettype wire
