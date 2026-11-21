`default_nettype none
`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// arbiter : lets the I-cache and the D-cache share ONE lower-level memory port
//           (modified Harvard: split L1 caches, unified memory below them)
//
//   * Fixed priority: an instruction request wins over a data request when
//     both start in the same cycle (the core cannot do anything without its
//     next instruction).
//   * No pre-emption: once a transfer has started and not finished
//     (m_req & ~m_ready), the same requester keeps the port until m_ready,
//     even if the other side asks with higher priority. Otherwise the memory's
//     latency counter would be handed to the wrong request.
//   * conflict = 1 in every cycle in which both caches want the memory, so one
//     of them is waiting only because the port is shared.
//
// The grant depends on the requests and on one register, and the ready
// signals depend on the grant and on m_ready. Nothing is forwarded from the
// memory back into a request, so this block cannot close a combinational loop
// as long as the caches do not forward refill data to the core.
// -----------------------------------------------------------------------------
module arbiter (
    input  wire        clk,
    input  wire        rst,
    // I-cache side
    input  wire        i_req,
    input  wire        i_we,
    input  wire [31:0] i_addr,
    input  wire [31:0] i_wdata,
    output wire        i_ready,
    // D-cache side
    input  wire        d_req,
    input  wire        d_we,
    input  wire [31:0] d_addr,
    input  wire [31:0] d_wdata,
    output wire        d_ready,
    // shared memory side
    output wire        m_req,
    output wire        m_we,
    output wire [31:0] m_addr,
    output wire [31:0] m_wdata,
    input  wire        m_ready,
    // event
    output wire        conflict
);
    reg locked;          // a transfer is in progress
    reg owner_d;         // 0 = I-cache owns it, 1 = D-cache owns it

    // who uses the port this cycle
    wire sel_d = locked ? owner_d : (~i_req & d_req);

    assign m_req   = sel_d ? d_req   : i_req;
    assign m_we    = sel_d ? d_we    : i_we;
    assign m_addr  = sel_d ? d_addr  : i_addr;
    assign m_wdata = sel_d ? d_wdata : i_wdata;

    assign i_ready = ~sel_d & m_ready;
    assign d_ready =  sel_d & m_ready;

    always @(posedge clk) begin
        if (rst) begin
            locked  <= 1'b0;
            owner_d <= 1'b0;
        end else if (m_req & ~m_ready) begin
            locked  <= 1'b1;             // keep the port until the transfer ends
            owner_d <= sel_d;
        end else begin
            locked  <= 1'b0;
        end
    end

    assign conflict = i_req & d_req;
endmodule
`default_nettype wire
