`default_nettype none
`timescale 1ns/1ps
// Unit test: instr_mem. Loads a program and checks combinational, word-aligned reads.
module tb_instr_mem;
    parameter PROG_FILE = "../programs/basic.hex";

    reg  [31:0] addr;
    wire [31:0] rdata;
    integer     errors = 0;

    instr_mem #(.DEPTH_WORDS(256), .INIT_FILE(PROG_FILE)) dut (.addr(addr), .rdata(rdata));

    task check(input [31:0] a, input [31:0] exp);
        begin
            addr = a;
            #1;                                   // no clock: read is combinational
            if (rdata !== exp) begin
                $display("FAIL addr=%h rdata=%h expected %h", a, rdata, exp);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("build/tb_instr_mem.vcd");
        $dumpvars(0, tb_instr_mem);
        check(32'h000, 32'h00500093);   // addi x1,x0,5
        check(32'h004, 32'h00700113);   // addi x2,x0,7
        check(32'h008, 32'h002081b3);   // add x3,x1,x2
        check(32'h04C, 32'h00100073);   // word 19: ebreak
        check(32'h3FC, 32'h00000000);   // last word, not loaded -> 0
        check(32'h006, 32'h00700113);   // low 2 bits ignored (aligned only)
        if (errors == 0) $display("tb_instr_mem: PASS");
        else             $display("tb_instr_mem: FAIL (%0d errors)", errors);
        $finish;
    end
endmodule
`default_nettype wire
