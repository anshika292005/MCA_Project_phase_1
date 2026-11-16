`default_nettype none
`timescale 1ns/1ps
// tb_compare: run the SAME program on harvard_top and vn_top side by side.
// Checks:
//   1. all 32 registers and all 256 data words are identical on both designs
//   2. out_port identical
//   3. Harvard cycles == Harvard instructions             (CPI = 1)
//   4. baseline cycles == Harvard cycles + Harvard d_access_count
// Prints one markdown table row for results/comparison.md.
module tb_compare;
    parameter PROG_NAME = "basic";
    parameter PROG_FILE = "../programs/basic.hex";
    parameter DATA_FILE = "../programs/basic_data.hex";
    parameter TIMEOUT   = 10000;

    reg clk = 0, rst = 1;
    always #5 clk = ~clk;

    wire        h_halt, v_halt;
    wire [31:0] h_out, h_cyc, h_ins, h_dacc, h_sim;
    wire [31:0] v_out, v_cyc, v_ins, v_dacc, v_sim;

    harvard_top #(.PROG_FILE(PROG_FILE), .DATA_FILE(DATA_FILE)) h (
        .clk(clk), .rst(rst), .halt(h_halt), .out_port(h_out),
        .cycle_count(h_cyc), .instr_count(h_ins), .d_access_count(h_dacc), .simul_count(h_sim));

    vn_top #(.PROG_FILE(PROG_FILE), .DATA_FILE(DATA_FILE)) v (
        .clk(clk), .rst(rst), .halt(v_halt), .out_port(v_out),
        .cycle_count(v_cyc), .instr_count(v_ins), .d_access_count(v_dacc), .simul_count(v_sim));

    integer errors = 0, cyc, n;
    real    h_cpi, v_cpi, ls_frac, speedup;

    initial begin
        $dumpfile({"build/tb_compare_", PROG_NAME, ".vcd"});
        $dumpvars(0, tb_compare);
        repeat (2) @(posedge clk);
        @(negedge clk) rst = 0;

        cyc = 0;
        while (!(h_halt && v_halt) && cyc < TIMEOUT) begin
            @(posedge clk); cyc = cyc + 1;
        end
        if (!(h_halt && v_halt)) begin
            $display("FAIL timeout: harvard halt=%b vn halt=%b", h_halt, v_halt);
            errors = errors + 1;
        end
        repeat (3) @(posedge clk);
        #1;

        for (n = 0; n < 32; n = n + 1)
            if (h.u_core.u_regfile.regs[n] !== v.u_core.u_regfile.regs[n]) begin
                $display("FAIL x%0d: harvard=%h vn=%h", n,
                         h.u_core.u_regfile.regs[n], v.u_core.u_regfile.regs[n]);
                errors = errors + 1;
            end
        for (n = 0; n < 256; n = n + 1)
            if (h.u_mem.u_dmem.mem[n] !== v.u_mem.mem[256 + n]) begin
                $display("FAIL data[%0d]: harvard=%h vn=%h", n,
                         h.u_mem.u_dmem.mem[n], v.u_mem.mem[256 + n]);
                errors = errors + 1;
            end
        if (h_out !== v_out) begin
            $display("FAIL out_port: harvard=%0d vn=%0d", h_out, v_out); errors = errors + 1;
        end
        if (h_ins !== v_ins) begin
            $display("FAIL instr_count: harvard=%0d vn=%0d", h_ins, v_ins); errors = errors + 1;
        end
        if (h_cyc !== h_ins) begin
            $display("FAIL harvard cycles %0d != instrs %0d", h_cyc, h_ins); errors = errors + 1;
        end
        if (v_cyc !== h_cyc + h_dacc) begin
            $display("FAIL vn cycles %0d != harvard cycles %0d + d_access %0d", v_cyc, h_cyc, h_dacc);
            errors = errors + 1;
        end

        h_cpi   = h_cyc * 1.0 / h_ins;
        v_cpi   = v_cyc * 1.0 / v_ins;
        ls_frac = h_dacc * 100.0 / h_ins;
        speedup = v_cyc * 1.0 / h_cyc;

        $display("| %-10s | %4d | %5.1f%% | %5d | %4.2f | %5d | %4.2f | %4.2fx | %5d |",
                 PROG_NAME, h_ins, ls_frac, h_cyc, h_cpi, v_cyc, v_cpi, speedup, h_sim);
        if (errors == 0) $display("tb_compare(%0s): PASS", PROG_NAME);
        else             $display("tb_compare(%0s): FAIL (%0d errors)", PROG_NAME, errors);
        $finish;
    end
endmodule
`default_nettype wire
