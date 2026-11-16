`default_nettype none
`timescale 1ns/1ps
// Unit test: data_mem. Synchronous write, combinational read, write-enable honoured.
module tb_data_mem;
    reg         clk = 0, we = 0;
    reg  [31:0] addr = 0, wdata = 0;
    wire [31:0] rdata;
    integer     errors = 0;

    data_mem #(.DEPTH_WORDS(256)) dut (.clk(clk), .we(we), .addr(addr), .wdata(wdata), .rdata(rdata));

    always #5 clk = ~clk;

    task expect_rd(input [31:0] a, input [31:0] exp);
        begin
            addr = a; we = 0;
            #1;
            if (rdata !== exp) begin
                $display("FAIL read addr=%h rdata=%h expected %h", a, rdata, exp);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("build/tb_data_mem.vcd");
        $dumpvars(0, tb_data_mem);
        expect_rd(32'h0, 32'h0);                     // zero-initialised

        // write word 3; value must NOT appear before the clock edge
        @(negedge clk); addr = 32'hC; wdata = 32'hDEAD_BEEF; we = 1;
        #1;
        if (rdata !== 32'h0) begin $display("FAIL write visible before edge"); errors = errors + 1; end
        @(negedge clk); we = 0;
        expect_rd(32'hC, 32'hDEAD_BEEF);

        // last word
        @(negedge clk); addr = 32'h3FC; wdata = 32'h1234_5678; we = 1;
        @(negedge clk); we = 0;
        expect_rd(32'h3FC, 32'h1234_5678);

        // we = 0 must not write
        @(negedge clk); addr = 32'hC; wdata = 32'hFFFF_FFFF; we = 0;
        @(negedge clk);
        expect_rd(32'hC, 32'hDEAD_BEEF);

        if (errors == 0) $display("tb_data_mem: PASS");
        else             $display("tb_data_mem: FAIL (%0d errors)", errors);
        $finish;
    end
endmodule
`default_nettype wire
