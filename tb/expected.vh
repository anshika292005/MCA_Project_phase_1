// expected.vh - expected final state of each test program, shared by
// tb_harvard_top and tb_vn_top. The including testbench defines:
//   `REG(n)   -> register n of its DUT
//   `DMEM(n)  -> data word n of its DUT
// and has: parameter PROG_NAME, integer errors, wire [31:0] out_port,
// and task chk(input [8*24-1:0] what, input [31:0] got, input [31:0] exp).
//
// exp_instr / exp_daccess are the hand-counted dynamic instruction count and
// number of LW/SW executed, used to check the cycle counts.

integer exp_instr, exp_daccess;
integer k;

task check_program;
    begin
        exp_instr = -1; exp_daccess = -1;
        if (PROG_NAME == "basic") begin
            exp_instr = 19; exp_daccess = 7;
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
            chk("x12", `REG(12), 32'h800);
            chk("mem[0]", `DMEM(0), 12);
            chk("mem[1]", `DMEM(1), 32'hFFFF_FFFF);
            chk("out_port", out_port, 12);
        end else if (PROG_NAME == "array_sum") begin
            exp_instr = 38; exp_daccess = 10;
            chk("x3", `REG(3), 31);
            chk("mem[8]", `DMEM(8), 31);
            chk("out_port", out_port, 31);
        end else if (PROG_NAME == "memcopy") begin
            exp_instr = 54; exp_daccess = 17;
            for (k = 0; k < 8; k = k + 1)
                chk("copy", `DMEM(16 + k), 10 * (k + 1));
            chk("x5", `REG(5), 360);
            chk("out_port", out_port, 360);
        end else if (PROG_NAME == "count_loop") begin
            exp_instr = 64; exp_daccess = 1;
            chk("x1", `REG(1), 0);
            chk("x2", `REG(2), 210);
            chk("out_port", out_port, 210);
        end else begin
            $display("NOTE: no expected values for program '%0s', only counters checked", PROG_NAME);
        end
    end
endtask
