# basic.s - uses every instruction at least once, with easy-to-predict results.
# Expected final state:
#   x1=5 x2=7 x3=12 x4=2 x5=5 x6=7 x7=12 x8=0 (branch skipped it) x9=-1
#   x10=0 (out_port reads as 0)  x11=0 (invalid address reads as 0)  x12=0x808
#   data word 0 = 12, data word 1 = 0xFFFFFFFF, data word 2 = 0, out_port = 12
        addi x1, x0, 5          # x1 = 5
        addi x2, x0, 7          # x2 = 7
        add  x3, x1, x2         # x3 = 12
        sub  x4, x2, x1         # x4 = 2
        and  x5, x1, x2         # x5 = 5 & 7 = 5
        or   x6, x1, x2         # x6 = 5 | 7 = 7
        sw   x3, 0(x0)          # data[0] = 12
        lw   x7, 0(x0)          # x7 = 12
        beq  x3, x7, eq_ok      # taken (12 == 12)
        addi x8, x0, 99         # skipped
eq_ok:  bne  x3, x7, fail       # not taken
        addi x9, x0, -1         # x9 = 0xFFFFFFFF
        sw   x9, 4(x0)          # data[1] = 0xFFFFFFFF
        addi x12, x0, 2047
        addi x12, x12, 9        # x12 = 0x808 (outside the data map)
        sw   x4, 0(x12)         # invalid write of 2: must be ignored, d_fault = 1
                                # (0x808 aliases data word 2 on Harvard and code word 2
                                #  on the baseline; neither is written by anything else,
                                #  so a write that leaks through the decoder is caught)
        lw   x11, 0(x12)        # invalid read: returns 0, d_fault = 1
        sw   x3, 1024(x0)       # out_port = 12
        lw   x10, 1024(x0)      # out_port is write-only, reads as 0
        ebreak
fail:   addi x8, x0, 1          # only reached if BNE is broken
        sw   x8, 1024(x0)
        ebreak
