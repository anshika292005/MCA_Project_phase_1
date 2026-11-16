`default_nettype none
`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// perf_counters : performance counters shared by the Harvard and baseline tops
//   cycle_count    : clock cycles until (and including) the halt cycle
//   instr_count    : retired instructions (instr_done pulses)
//   d_access_count : cycles with a data-memory access
//   simul_count    : cycles with an instruction fetch AND a data access
//
// Freeze rule: the cycle in which halt first goes high (the EBREAK cycle) is
// still counted, then every counter freezes. 'stopped' remembers that.
// -----------------------------------------------------------------------------
module perf_counters (
    input  wire        clk,
    input  wire        rst,
    input  wire        halt,
    input  wire        instr_done,
    input  wire        i_access,
    input  wire        d_access,
    output reg  [31:0] cycle_count,
    output reg  [31:0] instr_count,
    output reg  [31:0] d_access_count,
    output reg  [31:0] simul_count
);
    reg stopped;

    always @(posedge clk) begin
        if (rst) begin
            stopped        <= 1'b0;
            cycle_count    <= 32'd0;
            instr_count    <= 32'd0;
            d_access_count <= 32'd0;
            simul_count    <= 32'd0;
        end else if (!stopped) begin
            cycle_count <= cycle_count + 32'd1;
            if (instr_done)           instr_count    <= instr_count    + 32'd1;
            if (d_access)             d_access_count <= d_access_count + 32'd1;
            if (i_access && d_access) simul_count    <= simul_count    + 32'd1;
            if (halt)                 stopped        <= 1'b1;
        end
    end
endmodule
`default_nettype wire
