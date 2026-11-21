`default_nettype none
`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// vn_top : shared-memory (Von Neumann) baseline system
//   cpu_core_vn + shared_mem + perf_counters, same ports as harvard_top.
//
// Data accesses (m_is_data = 1) go through the same addr_decoder as Harvard:
//   RAM  (0x000-0x3FF) : physical address = addr + 0x400  (data lives in words 256..511)
//   IO   (0x400)       : out_port register, reads as 0, never touches shared_mem
//   else               : write ignored, read returns 0, d_fault = 1
// Instruction fetches (m_is_data = 0) use the address unchanged (code = words 0..255).
//
// The memory is ideal, so the core's Phase II stall input m_ready is tied to 1
// and this top level keeps exactly the Phase I cycle behaviour.
//
// i_access is high only in fetch cycles and d_access only in MEM cycles, so
// simul_count is always 0: one port cannot do both in the same cycle.
// -----------------------------------------------------------------------------
module vn_top #(
    parameter PROG_FILE = "",
    parameter DATA_FILE = ""
) (
    input  wire        clk,
    input  wire        rst,
    output wire        halt,
    output reg  [31:0] out_port,
    output wire [31:0] cycle_count,
    output wire [31:0] instr_count,
    output wire [31:0] d_access_count,
    output wire [31:0] simul_count,
    output wire        d_fault      // 1 in a cycle that reads/writes an invalid data address
);
    wire [31:0] m_addr, m_wdata, m_rdata, mem_rdata;
    wire        m_we, m_re, m_is_data, instr_done;
    wire        sel_ram, sel_io, addr_fault;

    cpu_core_vn u_core (
        .clk       (clk),
        .rst       (rst),
        .m_addr    (m_addr),
        .m_wdata   (m_wdata),
        .m_we      (m_we),
        .m_re      (m_re),
        .m_is_data (m_is_data),
        .m_rdata   (m_rdata),
        .m_ready   (1'b1),            // ideal single-port memory: every transfer takes one cycle
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
    wire [31:0] phys_addr = data_ram ? (m_addr + 32'h0000_0400) : m_addr;

    shared_mem #(.DEPTH_WORDS(512), .PROG_FILE(PROG_FILE), .DATA_FILE(DATA_FILE)) u_mem (
        .clk  (clk),
        .we   (m_we & data_ram),
        .addr (phys_addr),
        .wdata(m_wdata),
        .rdata(mem_rdata)
    );

    // what the core sees: instructions always; data only for a RAM read
    assign m_rdata = ~m_is_data          ? mem_rdata :
                     (m_re & sel_ram)    ? mem_rdata : 32'h0000_0000;

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
        .i_access      (~m_is_data & m_re),
        .d_access      (m_is_data & (m_we | m_re)),
        .cycle_count   (cycle_count),
        .instr_count   (instr_count),
        .d_access_count(d_access_count),
        .simul_count   (simul_count)
    );
endmodule
`default_nettype wire
