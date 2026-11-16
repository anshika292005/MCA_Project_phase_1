`default_nettype none
`timescale 1ns/1ps
// Unit test: harvard_mem. The key case: an instruction fetch and a data write
// in the SAME clock cycle, both checked. Also out_port, invalid access, rst.
module tb_harvard_mem;
    parameter PROG_FILE = "../programs/basic.hex";

    reg         clk = 0, rst = 1;
    reg  [31:0] i_addr = 0, d_addr = 0, d_wdata = 0;
    reg         d_we = 0, d_re = 0;
    wire [31:0] i_rdata, d_rdata, out_port;
    wire        d_fault;
    integer     errors = 0;

    harvard_mem #(.PROG_FILE(PROG_FILE)) dut (
        .clk(clk), .rst(rst),
        .i_addr(i_addr), .i_rdata(i_rdata),
        .d_addr(d_addr), .d_wdata(d_wdata), .d_we(d_we), .d_re(d_re),
        .d_rdata(d_rdata), .d_fault(d_fault), .out_port(out_port));

    always #5 clk = ~clk;

    task fail(input [8*48-1:0] msg);
        begin $display("FAIL %0s", msg); errors = errors + 1; end
    endtask

    initial begin
        $dumpfile("build/tb_harvard_mem.vcd");
        $dumpvars(0, tb_harvard_mem);
        @(negedge clk); rst = 0;

        // cycle A: fetch word 0 AND write data word 2, same cycle
        @(negedge clk);
        i_addr = 32'h0; d_addr = 32'h8; d_wdata = 32'hCAFE_0001; d_we = 1; d_re = 0;
        #1;
        if (i_rdata !== 32'h00500093) fail("fetch during data write");
        if (d_fault)                  fail("fault on valid write");

        // cycle B: fetch word 1 AND read back data word 2, same cycle
        @(negedge clk);
        if (dut.u_dmem.mem[2] !== 32'hCAFE_0001) fail("data word 2 not written");
        i_addr = 32'h4; d_addr = 32'h8; d_we = 0; d_re = 1;
        #1;
        if (i_rdata !== 32'h00700113) fail("fetch during data read");
        if (d_rdata !== 32'hCAFE_0001) fail("read back");

        // cycle C: write out_port
        @(negedge clk);
        d_addr = 32'h400; d_wdata = 32'd42; d_we = 1; d_re = 0;
        @(negedge clk);
        if (out_port !== 32'd42) fail("out_port write");
        d_we = 0; d_re = 1;                        // out_port reads as 0
        #1;
        if (d_rdata !== 32'h0) fail("out_port must read 0");

        // cycle D: invalid write and read
        @(negedge clk);
        d_addr = 32'h800; d_wdata = 32'hBAD; d_we = 1; d_re = 0;
        #1;
        if (!d_fault) fail("no fault on invalid write");
        if (dut.u_rw.ram_we) fail("RAM written on invalid addr");
        @(negedge clk);
        d_we = 0; d_re = 1;
        #1;
        if (!d_fault)          fail("no fault on invalid read");
        if (d_rdata !== 32'h0) fail("invalid read not 0");
        if (dut.u_dmem.mem[0] !== 32'h0) fail("invalid write aliased into RAM");

        // idle: no access -> no fault even with a bad address
        d_re = 0;
        #1;
        if (d_fault) fail("fault without access");

        // reset clears out_port
        @(negedge clk); rst = 1;
        @(negedge clk); rst = 0;
        if (out_port !== 32'h0) fail("out_port not cleared by rst");

        if (errors == 0) $display("tb_harvard_mem: PASS");
        else             $display("tb_harvard_mem: FAIL (%0d errors)", errors);
        $finish;
    end
endmodule
`default_nettype wire
