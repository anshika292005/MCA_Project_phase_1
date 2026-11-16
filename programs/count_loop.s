# count_loop.s - count down in registers, almost no memory access (compute-heavy)
# Computes 20 + 19 + ... + 1 = 210
# Expected: x1 = 0, x2 = 210, out_port = 210
        addi x1, x0, 20         # x1 = counter
        addi x2, x0, 0          # x2 = accumulator
loop:   add  x2, x2, x1
        addi x1, x1, -1
        bne  x1, x0, loop
        sw   x2, 1024(x0)       # the only data access
        ebreak
