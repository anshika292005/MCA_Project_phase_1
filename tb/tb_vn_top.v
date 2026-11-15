`default_nettype none
`timescale 1ns/1ps
// System test: run one program on the shared-memory baseline vn_top.
module tb_vn_top;
    parameter PROG_NAME = "basic";
    parameter PROG_FILE = "../programs/basic.hex";
    parameter DATA_FILE = "../programs/basic_data.hex";
    parameter TIMEOUT   = 10000;

    reg         clk = 0, rst = 1;
    wire        halt, d_fault;
    wire [31:0] out_port, cycle_count, instr_count, d_access_count, simul_count;
    integer     errors = 0;

    vn_top #(.PROG_FILE(PROG_FILE), .DATA_FILE(DATA_FILE)) dut (
        .clk(clk), .rst(rst), .halt(halt), .out_port(out_port),
        .cycle_count(cycle_count), .instr_count(instr_count),
        .d_access_count(d_access_count), .simul_count(simul_count), .d_fault(d_fault));

    always #5 clk = ~clk;

    `define REG(n)  dut.u_core.u_regfile.regs[n]
    `define DMEM(n) dut.u_mem.mem[256 + (n)]

    task chk(input [8*24-1:0] what, input [31:0] got, input [31:0] exp);
        if (got !== exp) begin
            $display("FAIL %0s = %0d (0x%h), expected %0d (0x%h)", what, got, got, exp, exp);
            errors = errors + 1;
        end
    endtask

    `include "expected.vh"

    // count and print every data-side fault, so invalid accesses are checked and visible
    integer fault_cycles = 0;
    always @(posedge clk)
        if (!rst && d_fault) begin
            fault_cycles = fault_cycles + 1;
            $display("  [%0t] d_fault: invalid data address 0x%h", $time, dut.m_addr);
        end

    integer cyc;
    initial begin
        $dumpfile({"build/tb_vn_top_", PROG_NAME, ".vcd"});
        $dumpvars(0, tb_vn_top);
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
        repeat (3) @(posedge clk);
        #1;

        check_program;
        // 0x808 (basic.s invalid write) aliases shared_mem word 2 = the program's third
        // instruction; it must not have been overwritten
        if (PROG_NAME == "basic")
            chk("code word 2", dut.u_mem.mem[2], 32'h0020_81B3);   // add x3, x1, x2
        if (exp_instr >= 0) begin
            chk("instr_count", instr_count, exp_instr);
            chk("d_access_count", d_access_count, exp_daccess);
            chk("d_fault cycles", fault_cycles, exp_faults);
        end
        // one port: each data access costs one extra cycle, never overlaps a fetch
        chk("cycles == instrs + d_access", cycle_count, instr_count + d_access_count);
        chk("simul == 0", simul_count, 0);

        $display("VN      %-10s cycles=%0d instrs=%0d d_access=%0d simul=%0d out_port=%0d",
                 PROG_NAME, cycle_count, instr_count, d_access_count, simul_count, out_port);
        if (errors == 0) $display("tb_vn_top(%0s): PASS", PROG_NAME);
        else             $display("tb_vn_top(%0s): FAIL (%0d errors)", PROG_NAME, errors);
        $finish;
    end
endmodule
`default_nettype wire
