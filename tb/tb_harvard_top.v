`default_nettype none
`timescale 1ns/1ps
// System test: run one program on harvard_top until halt, check results and counters.
//   iverilog -P tb_harvard_top.PROG_NAME=\"basic\" -P tb_harvard_top.PROG_FILE=... -P ...DATA_FILE=...
module tb_harvard_top;
    parameter PROG_NAME = "basic";
    parameter PROG_FILE = "../programs/basic.hex";
    parameter DATA_FILE = "../programs/basic_data.hex";
    parameter TIMEOUT   = 10000;

    reg         clk = 0, rst = 1;
    wire        halt;
    wire [31:0] out_port, cycle_count, instr_count, d_access_count, simul_count;
    integer     errors = 0;

    harvard_top #(.PROG_FILE(PROG_FILE), .DATA_FILE(DATA_FILE)) dut (
        .clk(clk), .rst(rst), .halt(halt), .out_port(out_port),
        .cycle_count(cycle_count), .instr_count(instr_count),
        .d_access_count(d_access_count), .simul_count(simul_count));

    always #5 clk = ~clk;

    `define REG(n)  dut.u_core.u_regfile.regs[n]
    `define DMEM(n) dut.u_mem.u_dmem.mem[n]

    task chk(input [8*24-1:0] what, input [31:0] got, input [31:0] exp);
        if (got !== exp) begin
            $display("FAIL %0s = %0d (0x%h), expected %0d (0x%h)", what, got, got, exp, exp);
            errors = errors + 1;
        end
    endtask

    `include "expected.vh"

    // print every data-side fault, so invalid accesses are visible in the log
    always @(posedge clk)
        if (!rst && dut.d_fault)
            $display("  [%0t] d_fault: invalid data address 0x%h", $time, dut.u_core.d_addr);

    integer cyc;
    initial begin
        $dumpfile({"build/tb_harvard_top_", PROG_NAME, ".vcd"});
        $dumpvars(0, tb_harvard_top);
        repeat (2) @(posedge clk);
        @(negedge clk) rst = 0;

        cyc = 0;
        while (!halt && cyc < TIMEOUT) begin
            @(posedge clk); cyc = cyc + 1;
        end
        if (!halt) begin
            $display("FAIL timeout after %0d cycles", TIMEOUT);
            errors = errors + 1;
        end
        repeat (3) @(posedge clk);         // counters are frozen by now
        #1;

        check_program;
        if (exp_instr >= 0) begin
            chk("instr_count", instr_count, exp_instr);
            chk("d_access_count", d_access_count, exp_daccess);
        end
        chk("cycles == instrs (CPI 1)", cycle_count, instr_count);
        chk("simul == d_access", simul_count, d_access_count);

        $display("HARVARD %-10s cycles=%0d instrs=%0d d_access=%0d simul=%0d out_port=%0d",
                 PROG_NAME, cycle_count, instr_count, d_access_count, simul_count, out_port);
        if (errors == 0) $display("tb_harvard_top(%0s): PASS", PROG_NAME);
        else             $display("tb_harvard_top(%0s): FAIL (%0d errors)", PROG_NAME, errors);
        $finish;
    end
endmodule
`default_nettype wire
