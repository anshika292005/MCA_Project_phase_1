`default_nettype none
`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// vnc_top : von Neumann system with a memory hierarchy (Phase II)
//
//   +-------------+  m_addr  +---------------+  line / word  +----------+
//   | cpu_core_vn |--------->| unified cache |-------------->| main_mem |
//   |  (one bus,  |<---------|  CACHE_EN = 1 |<--------------| code and |
//   |  FETCH/MEM) | m_ready  |  or uncached  |    ready      | data, L  |
//   +-------------+          |  CACHE_EN = 0 |               +----------+
//         |                  +---------------+
//         +--> decoder: out_port (IO) and invalid data addresses bypass the cache
//
//   CACHE_EN = 1 : unified cache of U_LINES lines. For the same total capacity
//                  as the split design, U_LINES = I_LINES + D_LINES.
//   CACHE_EN = 0 : no cache. Every fetch and data access goes to main_mem.
//                  With LATENCY = 1 this system is cycle-for-cycle the Phase I
//                  vn_top (checked by tb_system).
//
// Addresses: fetches use the PC unchanged (code = physical 0x000-0x3FF), data
// RAM accesses add 0x400 (physical 0x400-0x7FF), exactly as in vn_top, so code
// and data words with the same offset map to the same cache index.
//
// Timing note: the single bus already has the Phase I false loop
// (m_addr -> memory -> m_rdata -> instr -> ALU -> m_addr, which can never be
// active because FETCH uses only the PC and MEM uses only the latched
// instruction). The cache adds m_addr -> hit -> m_ready -> instr mux on the
// same false path. See results/synth for the synthesis warnings.
// -----------------------------------------------------------------------------
module vnc_top #(
    parameter PROG_FILE  = "",
    parameter DATA_FILE  = "",
    parameter CACHE_EN   = 1,
    parameter LINE_WORDS = 4,
    parameter U_LINES    = 16,
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

    wire [31:0] m_addr, m_wdata, m_rdata, c_rdata;
    wire        m_we, m_re, m_is_data, m_ready, instr_done;
    wire        sel_ram, sel_io, addr_fault;
    wire        c_req, c_ready, refill, wb_stall, wb_busy;
    wire        mm_req, mm_we, mm_ready;
    wire [31:0] mm_addr, mm_wdata;
    wire [LWB-1:0] mm_rdata;

    cpu_core_vn u_core (
        .clk       (clk),
        .rst       (rst),
        .m_addr    (m_addr),
        .m_wdata   (m_wdata),
        .m_we      (m_we),
        .m_re      (m_re),
        .m_is_data (m_is_data),
        .m_rdata   (m_rdata),
        .m_ready   (m_ready),
        .halt      (halt),
        .instr_done(instr_done)
    );

    // decode data-space addresses BEFORE translating them (same map as Harvard)
    addr_decoder u_dec (
        .addr      (m_addr),
        .sel_ram   (sel_ram),
        .sel_io    (sel_io),
        .addr_fault(addr_fault)
    );

    wire data_ram = m_is_data & sel_ram;
    wire bypass   = m_is_data & ~sel_ram;            // out_port or invalid: never cached
    assign c_req  = (m_re | m_we) & ~bypass;

    cache #(.LINE_WORDS(LINE_WORDS), .NUM_LINES(U_LINES), .WBUF(WBUF),
            .ENABLE(CACHE_EN)) u_cache (
        .clk        (clk),
        .rst        (rst),
        .req        (c_req),
        .we         (m_we & data_ram),
        .addr       (data_ram ? (m_addr + DATA_BASE) : m_addr),
        .wdata      (m_wdata),
        .ready      (c_ready),
        .rdata      (c_rdata),
        .mem_req    (mm_req),
        .mem_we     (mm_we),
        .mem_addr   (mm_addr),
        .mem_wdata  (mm_wdata),
        .mem_ready  (mm_ready),
        .mem_rdata  (mm_rdata),
        .ev_refill  (refill),
        .ev_wb_stall(wb_stall),
        .wb_busy    (wb_busy)
    );

    main_mem #(.DEPTH_WORDS(MEM_WORDS), .LINE_WORDS(LINE_WORDS), .LATENCY(LATENCY),
               .DATA_BASE_W(DATA_BASE / 4),
               .PROG_FILE(PROG_FILE), .DATA_FILE(DATA_FILE)) u_mem (
        .clk  (clk),
        .rst  (rst),
        .req  (mm_req),
        .we   (mm_we),
        .addr (mm_addr),
        .wdata(mm_wdata),
        .ready(mm_ready),
        .rdata(mm_rdata)
    );

    assign m_ready = c_ready;                        // 1 whenever the cache is not used
    // what the core sees: instructions always; data only for a RAM read
    assign m_rdata = ~m_is_data       ? c_rdata :
                     (m_re & sel_ram) ? c_rdata : 32'h0000_0000;

    always @(posedge clk) begin
        if (rst)
            out_port <= 32'h0000_0000;
        else if (m_is_data & m_we & sel_io)
            out_port <= m_wdata;
    end

    assign d_fault = m_is_data & (m_we | m_re) & addr_fault;

    perf_counters u_perf (
        .clk           (clk),
        .rst           (rst),
        .halt          (halt),
        .instr_done    (instr_done),
        .i_access      (~m_is_data & m_re & m_ready),
        .d_access      (m_is_data & (m_we | m_re) & m_ready),
        .cycle_count   (cycle_count),
        .instr_count   (instr_count),
        .d_access_count(d_access_count),
        .simul_count   (simul_count)
    );

    event_counters u_ev (
        .clk           (clk),
        .rst           (rst),
        .halt          (halt),
        .i_miss        (refill & ~m_is_data),
        .d_miss        (refill &  m_is_data),
        .i_stall       (~m_is_data & m_re & ~m_ready),
        .d_stall       ( m_is_data & ~m_ready),
        .wb_stall      (wb_stall),
        .conflict      (1'b0),                       // one requester, nothing to arbitrate
        .i_miss_count  (i_miss_count),
        .d_miss_count  (d_miss_count),
        .i_stall_count (i_stall_count),
        .d_stall_count (d_stall_count),
        .wb_stall_count(wb_stall_count),
        .conflict_count(conflict_count)
    );
endmodule
`default_nettype wire
