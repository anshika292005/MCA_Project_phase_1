# isa_test.s - every Phase II instruction once, with hand-computed results
# (no data image needed). Results are also stored to data words 0..11.
# Expected:
#   x1 = 0xFFFFFFFA (-6)   x2 = 5
#   x3  = xor  x1,x2      = 0xFFFFFFFF
#   x4  = slt  x1,x2      = 1           (-6 < 5, signed)
#   x5  = sll  x2,x2      = 160         (5 << 5)
#   x6  = srl  x1,x2      = 0x07FFFFFF  (logical shift, no sign fill)
#   x7  = xori x2,15      = 10
#   x8  = slti x2,-1      = 0
#   x9  = slli x2,28      = 0x50000000
#   x10 = srli x9,30      = 1
#   x11 = lui  0xDEADB    = 0xDEADB000
#   blt x2,x1 not taken, bge x2,x1 taken -> x31 stays 0
#   x12 = jal link        = 0x3C (the jal is at 0x38, x12 = next address)
#   x14 = 77 (set in func, which returns with jalr)
#   out_port = x11 + x14  = 0xDEADB04D
        addi x1, x0, -6
        addi x2, x0, 5
        xor  x3, x1, x2
        slt  x4, x1, x2
        sll  x5, x2, x2
        srl  x6, x1, x2
        xori x7, x2, 15
        slti x8, x2, -1
        slli x9, x2, 28
        srli x10, x9, 30
        lui  x11, 0xDEADB
        blt  x2, x1, fail1      # must not be taken
        bge  x2, x1, ok1        # must be taken
fail1:  addi x31, x0, 1         # only reached if BLT or BGE is wrong
ok1:    jal  x12, func          # x12 = 0x3C
        sw   x3, 0(x0)
        sw   x4, 4(x0)
        sw   x5, 8(x0)
        sw   x6, 12(x0)
        sw   x7, 16(x0)
        sw   x8, 20(x0)
        sw   x9, 24(x0)
        sw   x10, 28(x0)
        sw   x11, 32(x0)
        sw   x12, 36(x0)
        sw   x14, 40(x0)
        sw   x31, 44(x0)
        add  x15, x11, x14
        sw   x15, 1024(x0)      # out_port = 0xDEADB04D
        ebreak
func:   addi x14, x0, 77
        jalr x0, 0(x12)         # return
