`default_nettype none
`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// harvard_top : complete Harvard system = cpu_core + harvard_mem + perf_counters
//   i_access = !halt        (the core fetches every cycle until it halts)
//   d_access = d_we | d_re  (LW or SW in this cycle)
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
    output wire [31:0] simul_count
);
    wire [31:0] i_addr, i_rdata;
    wire [31:0] d_addr, d_wdata, d_rdata;
    wire        d_we, d_re, d_fault, instr_done;

    cpu_core u_core (
        .clk       (clk),
        .rst       (rst),
        .i_addr    (i_addr),
        .i_rdata   (i_rdata),
        .d_addr    (d_addr),
        .d_wdata   (d_wdata),
        .d_we      (d_we),
        .d_re      (d_re),
        .d_rdata   (d_rdata),
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
        .d_fault (d_fault),     // not a top-level port; visible as dut.d_fault
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
