# bubble_sort.s - sort 16 signed words in place (temporal locality, store bursts)
# Data image (bubble_sort_data.hex): 23 -5 17 8 42 0 -12 99 3 15 -7 61 4 30 11 -1 at words 0..15
# Each swap is two back-to-back stores (a store burst for the write buffer).
# Expected: words 0..15 = -12 -7 -5 -1 0 3 4 8 11 15 17 23 30 42 61 99
#           x12 = out_port = 15 (number of in-order neighbour pairs after the sort)
        addi x10, x0, 64        # x10 = end of the unsorted part (16 words * 4)
outer:  addi x1, x0, 0          # x1  = pointer to a[i]
        addi x7, x0, 0          # x7  = "swapped in this pass" flag
        addi x11, x10, -4       # x11 = address of the last pair
inner:  lw   x2, 0(x1)          # a[i]
        lw   x3, 4(x1)          # a[i+1]
        bge  x3, x2, noswap     # already in order (signed compare)
        sw   x3, 0(x1)          # swap: two stores in a row
        sw   x2, 4(x1)
        addi x7, x0, 1
noswap: addi x1, x1, 4
        blt  x1, x11, inner
        addi x10, x10, -4       # the largest element is now in place
        bne  x7, x0, outer      # repeat until a pass makes no swap
# check: count neighbour pairs that are in order (15 if sorted)
        addi x1, x0, 0
        addi x12, x0, 0
        addi x13, x0, 60
check:  lw   x2, 0(x1)
        lw   x3, 4(x1)
        slt  x4, x3, x2         # 1 if out of order
        xori x4, x4, 1          # 1 if in order
        add  x12, x12, x4
        addi x1, x1, 4
        bne  x1, x13, check
        sw   x12, 1024(x0)      # out_port = 15
        ebreak
