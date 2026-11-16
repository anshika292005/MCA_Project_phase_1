# array_sum.s - sum an 8-element array from data memory (memory-heavy loop)
# Data image (array_sum_data.hex): 3 1 4 1 5 9 2 6 at data words 0..7
# Expected: x3 = 31, data word 8 = 31, out_port = 31
        addi x1, x0, 0          # x1 = pointer (byte address)
        addi x2, x0, 32         # x2 = end pointer (8 words * 4 bytes)
        addi x3, x0, 0          # x3 = sum
loop:   lw   x4, 0(x1)          # x4 = array[i]
        add  x3, x3, x4         # sum += x4
        addi x1, x1, 4          # next word
        bne  x1, x2, loop
        sw   x3, 32(x0)         # data word 8 = sum
        sw   x3, 1024(x0)       # out_port = sum
        ebreak
