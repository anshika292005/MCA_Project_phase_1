`default_nettype none
`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// rw_ctrl : read/write control for the data side
//   - routes a write (d_we) to the RAM or to out_port, depending on the decoder
//   - a write to an invalid address goes nowhere (both enables stay 0)
//   - a read returns RAM data only for a RAM read; out_port and invalid
//     addresses read as 0
// -----------------------------------------------------------------------------
module rw_ctrl (
    input  wire        d_we,
    input  wire        d_re,
    input  wire        sel_ram,
    input  wire        sel_io,
    input  wire [31:0] ram_rdata,
    output wire        ram_we,
    output wire        io_we,
    output wire [31:0] d_rdata
);
    assign ram_we  = d_we & sel_ram;
    assign io_we   = d_we & sel_io;
    assign d_rdata = (d_re & sel_ram) ? ram_rdata : 32'h0000_0000;
endmodule
`default_nettype wire
