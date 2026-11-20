`default_nettype none
`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// harvard_top : complete Harvard system = cpu_core + harvard_mem + perf_counters
//   i_access = !halt        (the core fetches every cycle until it halts)
//   d_access = d_we | d_re  (LW or SW in this cycle)
// The memories are ideal (combinational read), so the core's Phase II stall
// inputs i_ready and d_ready are tied to 1: this top level is the Phase II
// "ideal Harvard" reference and has exactly the Phase I cycle behaviour.
// Because the two ports are independent, every LW/SW cycle is also a fetch
// cycle, so simul_count ends up equal to d_access_count.
// -----------------------------------------------------------------------------
module harvard_top #(
    parameter PROG_FILE = "",
    parameter DATA_FILE = ""
) (
    input  wire        clk,
    input  wire        rst,
    output wire        halt,
    output wire [31:0] out_port,
    output wire [31:0] cycle_count,
    output wire [31:0] instr_count,
    output wire [31:0] d_access_count,
    output wire [31:0] simul_count,
    output wire        d_fault      // 1 in a cycle that reads/writes an invalid data address
);
    wire [31:0] i_addr, i_rdata;
    wire [31:0] d_addr, d_wdata, d_rdata;
    wire        d_we, d_re, instr_done;

    cpu_core u_core (
        .clk       (clk),
        .rst       (rst),
        .i_addr    (i_addr),
        .i_req     (),                // ideal ROM: always ready, no request needed
        .i_rdata   (i_rdata),
        .i_ready   (1'b1),
        .d_addr    (d_addr),
        .d_wdata   (d_wdata),
        .d_we      (d_we),
        .d_re      (d_re),
        .d_rdata   (d_rdata),
        .d_ready   (1'b1),            // ideal data RAM: every access finishes in its cycle
        .halt      (halt),
        .instr_done(instr_done)
    );

    harvard_mem #(.PROG_FILE(PROG_FILE), .DATA_FILE(DATA_FILE)) u_mem (
        .clk     (clk),
        .rst     (rst),
        .i_addr  (i_addr),
        .i_rdata (i_rdata),
        .d_addr  (d_addr),
        .d_wdata (d_wdata),
        .d_we    (d_we),
        .d_re    (d_re),
        .d_rdata (d_rdata),
        .d_fault (d_fault),
        .out_port(out_port)
    );

    perf_counters u_perf (
        .clk           (clk),
        .rst           (rst),
        .halt          (halt),
        .instr_done    (instr_done),
        .i_access      (~halt),
        .d_access      (d_we | d_re),
        .cycle_count   (cycle_count),
        .instr_count   (instr_count),
        .d_access_count(d_access_count),
        .simul_count   (simul_count)
    );
endmodule
`default_nettype wire
