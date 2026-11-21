`default_nettype none
`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// tb_system : Phase II system testbench. Runs ONE program on five systems:
//
//   ref : harvard_top (ideal Harvard, Phase I memories)          = the reference
//   mh  : mh_top      (modified Harvard: I-cache + D-cache + arbiter + main_mem)
//   vu  : vnc_top     (single bus + unified cache of 2*LINES lines)
//   vn  : vnc_top     (single bus, no cache)
//   v1  : vn_top      (Phase I shared-memory baseline, ideal memory)
//
// Compile-time parameters: LINE_WORDS, LINES (per split cache), WBUF, LATENCY.
// Run-time plusargs:
//   +PROG=<file.hex> +DATA=<file_data.hex> +NAME=<program name>
//   +DUMP=<prefix>   write the reference's final registers / data memory to
//                    <prefix>_regs.hex and <prefix>_dmem.hex (for tools/iss.py)
//   +VCD=<file>      dump a waveform
// DATA_BASE (default 0x400) moves the data image in main_mem of mh/vu/vn for
// the placement-sensitivity experiment; the reference and v1 are not affected.
//
// Checks (each failing check prints FAIL and counts as an error):
//   1. every system halts;
//   2. registers, all 256 data words, out_port, retired instructions, data
//      accesses and d_fault cycles are identical to the reference;
//   3. cycle accounting identities:
//        ref, v1 : cycles = instr (+ data accesses for v1)
//        mh      : cycles = instr + I-stall + D-stall
//        vu, vn  : cycles = instr + data accesses + I-stall + D-stall
//   4. single-bus systems never report arbiter conflicts; without a write
//      buffer, nothing reports write-buffer stalls and mh has no conflicts
//      (a data transfer only happens while the core waits for it);
//   5. LATENCY = 1: the no-cache system equals the Phase I baseline cycle for
//      cycle (same cycle count, same bus address and FSM state every cycle).
// Prints one RESULT line per system for tools/sweep.py.
// -----------------------------------------------------------------------------
module tb_system;
    parameter LINE_WORDS = 4;
    parameter LINES      = 8;
    parameter WBUF       = 1;
    parameter LATENCY    = 1;
    parameter TIMEOUT    = 400000;
    parameter DATA_BASE  = 32'h400;                       // physical byte address of data word 0
    localparam DBW       = DATA_BASE / 4;
    localparam MEM_WORDS = (DBW + 256 > 512) ? 1024 : 512;

    reg clk = 0, rst = 1;
    always #5 clk = ~clk;

    reg [8*256-1:0] prog_file, data_file, name, dump, vcd;

    // ---------------- the five systems ----------------
    wire        r_halt, r_fault;
    wire [31:0] r_out, r_cyc, r_ins, r_dacc, r_sim;
    harvard_top ref (.clk(clk), .rst(rst), .halt(r_halt), .out_port(r_out),
        .cycle_count(r_cyc), .instr_count(r_ins), .d_access_count(r_dacc),
        .simul_count(r_sim), .d_fault(r_fault));

    wire        v1_halt, v1_fault;
    wire [31:0] v1_out, v1_cyc, v1_ins, v1_dacc, v1_sim;
    vn_top v1 (.clk(clk), .rst(rst), .halt(v1_halt), .out_port(v1_out),
        .cycle_count(v1_cyc), .instr_count(v1_ins), .d_access_count(v1_dacc),
        .simul_count(v1_sim), .d_fault(v1_fault));

    // mh / vu / vn share one port list: c[k] = cycles, ins, dacc, sim, imiss, dmiss,
    // istall, dstall, wbstall, conflict
    wire        mh_halt, mh_fault, vu_halt, vu_fault, vn_halt, vn_fault;
    wire [31:0] mh_out, vu_out, vn_out;
    wire [31:0] mh_c [0:9];
    wire [31:0] vu_c [0:9];
    wire [31:0] vn_c [0:9];

    mh_top #(.LINE_WORDS(LINE_WORDS), .I_LINES(LINES), .D_LINES(LINES), .WBUF(WBUF),
             .LATENCY(LATENCY), .DATA_BASE(DATA_BASE), .MEM_WORDS(MEM_WORDS)) mh (
        .clk(clk), .rst(rst), .halt(mh_halt), .out_port(mh_out), .d_fault(mh_fault),
        .cycle_count(mh_c[0]), .instr_count(mh_c[1]), .d_access_count(mh_c[2]),
        .simul_count(mh_c[3]), .i_miss_count(mh_c[4]), .d_miss_count(mh_c[5]),
        .i_stall_count(mh_c[6]), .d_stall_count(mh_c[7]), .wb_stall_count(mh_c[8]),
        .conflict_count(mh_c[9]));

    vnc_top #(.CACHE_EN(1), .LINE_WORDS(LINE_WORDS), .U_LINES(2 * LINES), .WBUF(WBUF),
              .LATENCY(LATENCY), .DATA_BASE(DATA_BASE), .MEM_WORDS(MEM_WORDS)) vu (
        .clk(clk), .rst(rst), .halt(vu_halt), .out_port(vu_out), .d_fault(vu_fault),
        .cycle_count(vu_c[0]), .instr_count(vu_c[1]), .d_access_count(vu_c[2]),
        .simul_count(vu_c[3]), .i_miss_count(vu_c[4]), .d_miss_count(vu_c[5]),
        .i_stall_count(vu_c[6]), .d_stall_count(vu_c[7]), .wb_stall_count(vu_c[8]),
        .conflict_count(vu_c[9]));

    vnc_top #(.CACHE_EN(0), .LINE_WORDS(LINE_WORDS), .U_LINES(2 * LINES), .WBUF(WBUF),
              .LATENCY(LATENCY), .DATA_BASE(DATA_BASE), .MEM_WORDS(MEM_WORDS)) vn (
        .clk(clk), .rst(rst), .halt(vn_halt), .out_port(vn_out), .d_fault(vn_fault),
        .cycle_count(vn_c[0]), .instr_count(vn_c[1]), .d_access_count(vn_c[2]),
        .simul_count(vn_c[3]), .i_miss_count(vn_c[4]), .d_miss_count(vn_c[5]),
        .i_stall_count(vn_c[6]), .d_stall_count(vn_c[7]), .wb_stall_count(vn_c[8]),
        .conflict_count(vn_c[9]));

    integer errors = 0;
    task fail(input [8*64-1:0] what, input [31:0] got, input [31:0] exp);
        begin
            $display("FAIL %0s: got %0d (0x%h), expected %0d (0x%h)", what, got, got, exp, exp);
            errors = errors + 1;
        end
    endtask

    // ---------------- d_fault cycles, counted until each system halts ----------------
    integer f_r = 0, f_mh = 0, f_vu = 0, f_vn = 0, f_v1 = 0;
    always @(posedge clk) if (!rst) begin
        if (r_fault)  f_r  = f_r  + 1;
        if (mh_fault) f_mh = f_mh + 1;
        if (vu_fault) f_vu = f_vu + 1;
        if (vn_fault) f_vn = f_vn + 1;
        if (v1_fault) f_v1 = f_v1 + 1;
    end

    // ---------------- check 5: no-cache, L = 1 vs Phase I, every cycle ----------------
    integer lockstep_err = 0;
    always @(negedge clk) if (!rst && LATENCY == 1 && !(vn_halt && v1_halt)) begin
        if (vn.u_core.m_addr !== v1.u_core.m_addr || vn.u_core.state !== v1.u_core.state ||
            vn.m_ready !== 1'b1) begin
            if (lockstep_err < 5)
                $display("FAIL lockstep @%0t: no-cache m_addr=%h state=%b, Phase I m_addr=%h state=%b",
                         $time, vn.u_core.m_addr, vn.u_core.state, v1.u_core.m_addr, v1.u_core.state);
            lockstep_err = lockstep_err + 1;
        end
    end

    // ---------------- comparison helpers (hierarchical, per system) ----------------
    integer n;
    task compare_state(input [8*8-1:0] who, input integer sys);
        reg [31:0] g;
        begin
            for (n = 0; n < 32; n = n + 1) begin
                case (sys)
                    0: g = mh.u_core.u_regfile.regs[n];
                    1: g = vu.u_core.u_regfile.regs[n];
                    2: g = vn.u_core.u_regfile.regs[n];
                    default: g = v1.u_core.u_regfile.regs[n];
                endcase
                if (g !== ref.u_core.u_regfile.regs[n]) begin
                    $display("FAIL %0s x%0d = %h, reference %h", who, n, g, ref.u_core.u_regfile.regs[n]);
                    errors = errors + 1;
                end
            end
            for (n = 0; n < 256; n = n + 1) begin
                case (sys)
                    0: g = mh.u_mem.mem[DBW + n];
                    1: g = vu.u_mem.mem[DBW + n];
                    2: g = vn.u_mem.mem[DBW + n];
                    default: g = v1.u_mem.mem[256 + n];
                endcase
                if (g !== ref.u_mem.u_dmem.mem[n]) begin
                    $display("FAIL %0s data[%0d] = %h, reference %h", who, n, g, ref.u_mem.u_dmem.mem[n]);
                    errors = errors + 1;
                end
            end
        end
    endtask

    task check_cached(input [8*8-1:0] who, input [31:0] out, input integer faults,
                      input [31:0] cyc, input [31:0] ins, input [31:0] dacc,
                      input [31:0] istall, input [31:0] dstall, input [31:0] wbstall,
                      input [31:0] conflict, input single_bus);
        begin
            if (out !== r_out)     fail({who, " out_port"}, out, r_out);
            if (ins !== r_ins)     fail({who, " instr_count"}, ins, r_ins);
            if (dacc !== r_dacc)   fail({who, " d_access_count"}, dacc, r_dacc);
            if (faults !== f_r)    fail({who, " d_fault cycles"}, faults, f_r);
            if (single_bus) begin
                if (cyc !== ins + dacc + istall + dstall)
                    fail({who, " cycles = instr + dacc + I-stall + D-stall"}, cyc,
                         ins + dacc + istall + dstall);
                if (conflict !== 0) fail({who, " conflicts on a single bus"}, conflict, 0);
            end else begin
                if (cyc !== ins + istall + dstall)
                    fail({who, " cycles = instr + I-stall + D-stall"}, cyc, ins + istall + dstall);
                if (WBUF == 0 && conflict !== 0)
                    fail({who, " conflicts without write buffer"}, conflict, 0);
            end
            if (WBUF == 0 && wbstall !== 0) fail({who, " wb stalls without write buffer"}, wbstall, 0);
        end
    endtask

    task result(input [8*8-1:0] who, input [31:0] cyc, input [31:0] ins, input [31:0] dacc,
                input [31:0] imiss, input [31:0] dmiss, input [31:0] istall,
                input [31:0] dstall, input [31:0] wbstall, input [31:0] conflict);
        $display("RESULT prog=%0s design=%0s L=%0d lines=%0d line_words=%0d wbuf=%0d cycles=%0d instr=%0d dacc=%0d imiss=%0d dmiss=%0d istall=%0d dstall=%0d wbstall=%0d conflict=%0d",
                 name, who, LATENCY, LINES, LINE_WORDS, WBUF, cyc, ins, dacc, imiss, dmiss,
                 istall, dstall, wbstall, conflict);
    endtask

    integer cyc;
    initial begin
        if (!$value$plusargs("PROG=%s", prog_file)) begin
            $display("FAIL usage: +PROG=<hex> +DATA=<hex> +NAME=<name>");
            $finish;
        end
        if (!$value$plusargs("DATA=%s", data_file)) data_file = "";
        if (!$value$plusargs("NAME=%s", name))      name = "prog";
        if ($value$plusargs("VCD=%s", vcd)) begin
            $dumpfile(vcd);
            $dumpvars(0, tb_system);
        end

        // load the same images into every system (after their zero-fill at t = 0)
        #1;
        $readmemh(prog_file, ref.u_mem.u_imem.mem);
        $readmemh(prog_file, mh.u_mem.mem, 0, 255);
        $readmemh(prog_file, vu.u_mem.mem, 0, 255);
        $readmemh(prog_file, vn.u_mem.mem, 0, 255);
        $readmemh(prog_file, v1.u_mem.mem, 0, 255);
        if (data_file != "") begin
            $readmemh(data_file, ref.u_mem.u_dmem.mem);
            $readmemh(data_file, mh.u_mem.mem, DBW, DBW + 255);
            $readmemh(data_file, vu.u_mem.mem, DBW, DBW + 255);
            $readmemh(data_file, vn.u_mem.mem, DBW, DBW + 255);
            $readmemh(data_file, v1.u_mem.mem, 256, 511);
        end

        repeat (2) @(posedge clk);
        @(negedge clk) rst = 0;

        cyc = 0;
        while (!(r_halt && mh_halt && vu_halt && vn_halt && v1_halt) && cyc < TIMEOUT) begin
            @(posedge clk); cyc = cyc + 1;
        end
        if (!(r_halt && mh_halt && vu_halt && vn_halt && v1_halt)) begin
            $display("FAIL timeout: ref=%b mh=%b vu=%b vn=%b v1=%b",
                     r_halt, mh_halt, vu_halt, vn_halt, v1_halt);
            errors = errors + 1;
        end
        // let the write buffers drain to memory before comparing memory contents
        cyc = 0;
        while ((mh.u_dcache.wb_busy || vu.u_cache.wb_busy || vn.u_cache.wb_busy) && cyc < 1000) begin
            @(posedge clk); cyc = cyc + 1;
        end
        repeat (3) @(posedge clk);
        #1;

        if (r_cyc !== r_ins)            fail("ref cycles = instr", r_cyc, r_ins);
        if (v1_cyc !== v1_ins + v1_dacc) fail("v1 cycles = instr + dacc", v1_cyc, v1_ins + v1_dacc);
        if (v1_ins !== r_ins)           fail("v1 instr_count", v1_ins, r_ins);
        if (v1_out !== r_out)           fail("v1 out_port", v1_out, r_out);

        compare_state("mh", 0);
        compare_state("vu", 1);
        compare_state("vn", 2);
        compare_state("v1", 3);
        check_cached("mh", mh_out, f_mh, mh_c[0], mh_c[1], mh_c[2], mh_c[6], mh_c[7], mh_c[8], mh_c[9], 1'b0);
        check_cached("vu", vu_out, f_vu, vu_c[0], vu_c[1], vu_c[2], vu_c[6], vu_c[7], vu_c[8], vu_c[9], 1'b1);
        check_cached("vn", vn_out, f_vn, vn_c[0], vn_c[1], vn_c[2], vn_c[6], vn_c[7], vn_c[8], vn_c[9], 1'b1);

        if (LATENCY == 1) begin
            if (vn_c[0] !== v1_cyc) fail("no-cache L=1 cycles = Phase I baseline cycles", vn_c[0], v1_cyc);
            if (lockstep_err != 0)  fail("no-cache L=1 lockstep mismatches", lockstep_err, 0);
        end

        if ($value$plusargs("DUMP=%s", dump)) begin
            $writememh({dump, "_regs.hex"}, ref.u_core.u_regfile.regs);
            $writememh({dump, "_dmem.hex"}, ref.u_mem.u_dmem.mem);
        end

        result("ideal", r_cyc, r_ins, r_dacc, 0, 0, 0, 0, 0, 0);
        result("vn_ideal", v1_cyc, v1_ins, v1_dacc, 0, 0, 0, 0, 0, 0);
        result("mh", mh_c[0], mh_c[1], mh_c[2], mh_c[4], mh_c[5], mh_c[6], mh_c[7], mh_c[8], mh_c[9]);
        result("unified", vu_c[0], vu_c[1], vu_c[2], vu_c[4], vu_c[5], vu_c[6], vu_c[7], vu_c[8], vu_c[9]);
        result("nocache", vn_c[0], vn_c[1], vn_c[2], vn_c[4], vn_c[5], vn_c[6], vn_c[7], vn_c[8], vn_c[9]);
        $display("OUT prog=%0s out_port=%h", name, r_out);

        if (errors == 0) $display("tb_system(%0s L=%0d lines=%0d wbuf=%0d): PASS", name, LATENCY, LINES, WBUF);
        else             $display("tb_system(%0s L=%0d lines=%0d wbuf=%0d): FAIL (%0d errors)", name, LATENCY, LINES, WBUF, errors);
        $finish;
    end
endmodule
`default_nettype wire
