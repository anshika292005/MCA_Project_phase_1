`default_nettype none
`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// harvard_mem : complete Harvard memory subsystem
//
//   instruction port  i_addr ---> [ u_imem ] ---> i_rdata
//
//   data port         d_addr ---> [ u_dec ] --sel_ram/sel_io/fault-->
//                                      |
//                     d_we/d_re --> [ u_rw ] --ram_we--> [ u_dmem ]
//                                      |   \--io_we----> out_port register
//                                      \--> d_rdata
//
// The two ports share nothing: no common address bus, no common memory array,
// no arbitration. So a fetch and a data read/write complete in the same cycle.
// -----------------------------------------------------------------------------
module harvard_mem #(
    parameter PROG_FILE = "",
    parameter DATA_FILE = ""
) (
    input  wire        clk,
    input  wire        rst,
    // instruction port
    input  wire [31:0] i_addr,
    output wire [31:0] i_rdata,
    // data port
    input  wire [31:0] d_addr,
    input  wire [31:0] d_wdata,
    input  wire        d_we,
    input  wire        d_re,
    output wire [31:0] d_rdata,
    output wire        d_fault,
    output reg  [31:0] out_port
);
    wire        sel_ram, sel_io, addr_fault;
    wire        ram_we, io_we;
    wire [31:0] ram_rdata;

    instr_mem #(.DEPTH_WORDS(256), .INIT_FILE(PROG_FILE)) u_imem (
        .addr (i_addr),
        .rdata(i_rdata)
    );

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
        .ram_rdata(ram_rdata),
        .ram_we   (ram_we),
        .io_we    (io_we),
        .d_rdata  (d_rdata)
    );

    data_mem #(.DEPTH_WORDS(256), .INIT_FILE(DATA_FILE)) u_dmem (
        .clk  (clk),
        .we   (ram_we),
        .addr (d_addr),
        .wdata(d_wdata),
        .rdata(ram_rdata)
    );

    // memory-mapped output register at 0x400
    always @(posedge clk) begin
        if (rst)
            out_port <= 32'h0000_0000;
        else if (io_we)
            out_port <= d_wdata;
    end

    // fault only when an access is actually being made to an invalid address
    assign d_fault = (d_we | d_re) & addr_fault;
endmodule
`default_nettype wire
