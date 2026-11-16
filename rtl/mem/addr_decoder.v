`default_nettype none
`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// addr_decoder : data-space memory map (purely combinational)
//   0x0000_0000 - 0x0000_03FF : data RAM (256 words)  -> sel_ram
//   0x0000_0400               : out_port register     -> sel_io
//   anything else             : invalid               -> addr_fault
// Exactly one of the three outputs is 1 for every address.
// -----------------------------------------------------------------------------
module addr_decoder (
    input  wire [31:0] addr,
    output wire        sel_ram,
    output wire        sel_io,
    output wire        addr_fault
);
    // RAM: the upper 22 bits are zero, i.e. addr < 0x400
    assign sel_ram    = (addr[31:10] == 22'd0);
    // IO: exactly one address
    assign sel_io     = (addr == 32'h0000_0400);
    assign addr_fault = ~(sel_ram | sel_io);
endmodule
`default_nettype wire
