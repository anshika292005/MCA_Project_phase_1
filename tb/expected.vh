// expected.vh - expected final state of each test program, shared by
// tb_harvard_top and tb_vn_top. The including testbench defines:
//   `REG(n)   -> register n of its DUT
//   `DMEM(n)  -> data word n of its DUT
// and has: parameter PROG_NAME, integer errors, wire [31:0] out_port,
// and task chk(input [8*24-1:0] what, input [31:0] got, input [31:0] exp).
//
// exp_instr / exp_daccess are the hand-counted dynamic instruction count and
// number of LW/SW executed, used to check the cycle counts.
// exp_faults is the number of cycles in which d_fault must be 1 (invalid data address).
// Phase II programs (bubble_sort, subroutine, transpose, isa_test): the final
// values are worked out by hand in each .s file (and cross-checked with plain
// Python); the instruction and load/store counts are the golden model's
// (tools/iss.py), because they are too long to count by hand.

integer exp_instr, exp_daccess, exp_faults;
integer k;

task check_program;
    begin
        exp_instr = -1; exp_daccess = -1; exp_faults = -1;
        if (PROG_NAME == "basic") begin
            exp_instr = 19; exp_daccess = 7; exp_faults = 2;   // SW + LW to 0x808
            chk("x1",  `REG(1),  5);
            chk("x2",  `REG(2),  7);
            chk("x3",  `REG(3),  12);
            chk("x4",  `REG(4),  2);
            chk("x5",  `REG(5),  5);
            chk("x6",  `REG(6),  7);
            chk("x7",  `REG(7),  12);
            chk("x8",  `REG(8),  0);
            chk("x9",  `REG(9),  32'hFFFF_FFFF);
            chk("x10", `REG(10), 0);
            chk("x11", `REG(11), 0);
            chk("x12", `REG(12), 32'h808);
            chk("mem[0]", `DMEM(0), 12);
            chk("mem[1]", `DMEM(1), 32'hFFFF_FFFF);
            chk("mem[2] (bad write)", `DMEM(2), 0);
            chk("out_port", out_port, 12);
        end else if (PROG_NAME == "array_sum") begin
            exp_instr = 38; exp_daccess = 10; exp_faults = 0;
            chk("x3", `REG(3), 31);
            chk("mem[8]", `DMEM(8), 31);
            chk("out_port", out_port, 31);
        end else if (PROG_NAME == "memcopy") begin
            exp_instr = 54; exp_daccess = 17; exp_faults = 0;
            for (k = 0; k < 8; k = k + 1)
                chk("copy", `DMEM(16 + k), 10 * (k + 1));
            chk("x5", `REG(5), 360);
            chk("out_port", out_port, 360);
        end else if (PROG_NAME == "count_loop") begin
            exp_instr = 64; exp_daccess = 1; exp_faults = 0;
            chk("x1", `REG(1), 0);
            chk("x2", `REG(2), 210);
            chk("out_port", out_port, 210);
        end else if (PROG_NAME == "bubble_sort") begin
            exp_instr = 947; exp_daccess = 389; exp_faults = 0;
            chk("a[0]",  `DMEM(0),  -12);  chk("a[1]",  `DMEM(1),  -7);
            chk("a[2]",  `DMEM(2),  -5);   chk("a[3]",  `DMEM(3),  -1);
            chk("a[4]",  `DMEM(4),  0);    chk("a[5]",  `DMEM(5),  3);
            chk("a[6]",  `DMEM(6),  4);    chk("a[7]",  `DMEM(7),  8);
            chk("a[8]",  `DMEM(8),  11);   chk("a[9]",  `DMEM(9),  15);
            chk("a[10]", `DMEM(10), 17);   chk("a[11]", `DMEM(11), 23);
            chk("a[12]", `DMEM(12), 30);   chk("a[13]", `DMEM(13), 42);
            chk("a[14]", `DMEM(14), 61);   chk("a[15]", `DMEM(15), 99);
            chk("out_port", out_port, 15);
        end else if (PROG_NAME == "subroutine") begin
            exp_instr = 931; exp_daccess = 43; exp_faults = 0;
            chk("r[0]", `DMEM(16), 100);  chk("r[1]", `DMEM(17), 495);
            chk("r[2]", `DMEM(18), 154);  chk("r[3]", `DMEM(19), 605);
            chk("r[4]", `DMEM(20), 57);   chk("r[5]", `DMEM(21), 255);
            chk("r[6]", `DMEM(22), 392);  chk("r[7]", `DMEM(23), 1365);
            chk("acc x22", `REG(22), 42);
            chk("sp restored", `REG(2), 512);
            chk("out_port", out_port, 32'h0A5A_56E4);
        end else if (PROG_NAME == "transpose") begin
            exp_instr = 746; exp_daccess = 193; exp_faults = 0;
            for (k = 0; k < 64; k = k + 1)
                chk("B[j][i]", `DMEM(64 + k), 8 * (k % 8) + (k / 8) + 1);
            chk("out_port", out_port, 32'h7978_85B0);
        end else if (PROG_NAME == "isa_test") begin
            exp_instr = 31; exp_daccess = 13; exp_faults = 0;
            chk("xor  x3",  `REG(3),  32'hFFFF_FFFF);
            chk("slt  x4",  `REG(4),  1);
            chk("sll  x5",  `REG(5),  160);
            chk("srl  x6",  `REG(6),  32'h07FF_FFFF);
            chk("xori x7",  `REG(7),  10);
            chk("slti x8",  `REG(8),  0);
            chk("slli x9",  `REG(9),  32'h5000_0000);
            chk("srli x10", `REG(10), 1);
            chk("lui  x11", `REG(11), 32'hDEAD_B000);
            chk("jal  x12", `REG(12), 32'h3C);
            chk("jalr x14", `REG(14), 77);
            chk("blt/bge x31", `REG(31), 0);
            chk("mem[9] link", `DMEM(9), 32'h3C);
            chk("out_port", out_port, 32'hDEAD_B04D);
        end else begin
            $display("NOTE: no expected values for program '%0s', only counters checked", PROG_NAME);
        end
    end
endtask
