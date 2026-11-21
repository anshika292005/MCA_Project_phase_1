# transpose.s - 8x8 matrix transpose B = A^T (spatial locality, strided writes)
# Data image (transpose_data.hex): A[i][j] = 8*i + j + 1 at words 0..63 (row-major)
# B is written to words 64..127: rows of A are read sequentially (one cache line
# serves 4 loads), columns of B are written with a stride of 8 words.
# Expected: B[j][i] = A[i][j], i.e. word 64 + 8*j + i = 8*i + j + 1
#           out_port = checksum over B (x10 = (x10 << 1) xor B[k], k = 0..63)
        addi x1, x0, 0          # x1 = pointer into A, walks row by row
        addi x2, x0, 256        # x2 = &B[0][0]
        addi x3, x0, 0          # x3 = 4 * i  (column of B)
        addi x8, x0, 8          # inner trip count
        addi x9, x0, 32         # 4 * 8 rows
outer:  add  x4, x2, x3         # x4 = &B[0][i]
        addi x5, x0, 0          # j
inner:  lw   x6, 0(x1)          # A[i][j]
        sw   x6, 0(x4)          # B[j][i]
        addi x1, x1, 4
        addi x4, x4, 32         # next row of B
        addi x5, x5, 1
        blt  x5, x8, inner
        addi x3, x3, 4
        blt  x3, x9, outer
# checksum of B in storage order
        addi x1, x0, 256
        addi x7, x0, 512
        addi x10, x0, 0
sum:    lw   x6, 0(x1)
        slli x10, x10, 1
        xor  x10, x10, x6
        addi x1, x1, 4
        bne  x1, x7, sum
        sw   x10, 1024(x0)      # out_port = checksum
        ebreak
