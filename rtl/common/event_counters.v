`default_nettype none
`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// event_counters : Phase II memory-hierarchy counters, used next to the
//                  Phase I perf_counters in every cached top level
//
//   i_miss_count    : I-side misses (line refills for instruction fetches)
//   d_miss_count    : D-side misses (line refills for loads)
//   i_stall_count   : cycles the core waits for an instruction
//   d_stall_count   : cycles the core waits for a load/store to finish
//   wb_stall_count  : cycles an access waits for the write buffer
//                     (store with a full buffer, or read miss while it drains)
//   conflict_count  : cycles in which the I- and D-cache both want the shared
//                     memory (arbiter); always 0 in the single-bus system
//
// Same freeze rule as perf_counters: the halt (EBREAK) cycle is still counted,
// then every counter stops. Stores still draining from the write buffer after
// the halt are therefore not counted (at most LATENCY cycles).
// -----------------------------------------------------------------------------
module event_counters (
    input  wire        clk,
    input  wire        rst,
    input  wire        halt,
    input  wire        i_miss,
    input  wire        d_miss,
    input  wire        i_stall,
    input  wire        d_stall,
    input  wire        wb_stall,
    input  wire        conflict,
    output reg  [31:0] i_miss_count,
    output reg  [31:0] d_miss_count,
    output reg  [31:0] i_stall_count,
    output reg  [31:0] d_stall_count,
    output reg  [31:0] wb_stall_count,
    output reg  [31:0] conflict_count
);
    reg stopped;

    always @(posedge clk) begin
        if (rst) begin
            stopped        <= 1'b0;
            i_miss_count   <= 32'd0;
            d_miss_count   <= 32'd0;
            i_stall_count  <= 32'd0;
            d_stall_count  <= 32'd0;
            wb_stall_count <= 32'd0;
            conflict_count <= 32'd0;
        end else if (!stopped) begin
            if (i_miss)   i_miss_count   <= i_miss_count   + 32'd1;
            if (d_miss)   d_miss_count   <= d_miss_count   + 32'd1;
            if (i_stall)  i_stall_count  <= i_stall_count  + 32'd1;
            if (d_stall)  d_stall_count  <= d_stall_count  + 32'd1;
            if (wb_stall) wb_stall_count <= wb_stall_count + 32'd1;
            if (conflict) conflict_count <= conflict_count + 32'd1;
            if (halt)     stopped        <= 1'b1;
        end
    end
endmodule
`default_nettype wire
