# memcopy.s - copy 8 words from data 0x00 to data 0x40 (load AND store every iteration)
# Data image (memcopy_data.hex): 10 20 30 40 50 60 70 80 (decimal) at words 0..7
# Expected: words 16..23 = words 0..7, x5 = checksum = 360, out_port = 360
        addi x1, x0, 0          # x1 = source pointer
        addi x2, x0, 64         # x2 = destination pointer (word 16)
        addi x3, x0, 32         # x3 = source end
        addi x5, x0, 0          # x5 = checksum
loop:   lw   x4, 0(x1)
        sw   x4, 0(x2)
        add  x5, x5, x4
        addi x1, x1, 4
        addi x2, x2, 4
        bne  x1, x3, loop
        sw   x5, 1024(x0)       # out_port = checksum
        ebreak
