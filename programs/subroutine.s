# subroutine.s - subroutine calls (JAL/JALR, a stack, a nested call): I-cache footprint
# Data image (subroutine_data.hex): a[0..7] at words 0..7, b[0..7] at words 8..15
#   a = 12 18 7 40 9 25 16 30     b = 8 27 21 15 6 10 24 45
# For i = 0..7: r[i] = a*b + gcd(a,b) stored at words 16..23, acc += popcount(r[i])
# Then out_port = square(acc) xor 0x0A5A5000 (nested call through the stack).
# Expected: r = 100 495 154 605 57 255 392 1365, acc = 42, out_port = 42*42 xor 0x0A5A5000 = 0x0A5A56E4
        addi sp, x0, 512        # stack pointer: top of data words 0..127
        addi x20, x0, 0         # i
        addi x21, x0, 8         # n
        addi x22, x0, 0         # acc
loop:   slli x5, x20, 2         # byte offset of element i
        lw   x10, 0(x5)
        lw   x11, 32(x5)
        jal  ra, mul            # x10 = a * b
        mv   x23, x10
        lw   x10, 0(x5)
        lw   x11, 32(x5)
        jal  ra, gcd            # x10 = gcd(a, b)
        add  x23, x23, x10
        sw   x23, 64(x5)        # r[i]
        mv   x10, x23
        jal  ra, popcnt         # x10 = number of 1 bits
        add  x22, x22, x10
        addi x20, x20, 1
        blt  x20, x21, loop
        mv   x10, x22
        jal  ra, sqxor          # nested call: saves ra on the stack
        sw   x10, 1024(x0)      # out_port
        ebreak

# mul: x10 = x10 * x11 (shift and add); uses x6, x7, x8
mul:    addi x6, x0, 0
        addi x8, x0, 1
mul_l:  beq  x11, x0, mul_d
        and  x7, x11, x8
        beq  x7, x0, mul_s
        add  x6, x6, x10
mul_s:  slli x10, x10, 1
        srli x11, x11, 1
        j    mul_l
mul_d:  mv   x10, x6
        ret

# gcd: x10 = gcd(x10, x11) for positive inputs (subtraction form)
gcd:    beq  x10, x11, gcd_d
        blt  x10, x11, gcd_s
        sub  x10, x10, x11
        j    gcd
gcd_s:  sub  x11, x11, x10
        j    gcd
gcd_d:  ret

# popcnt: x10 = number of 1 bits in x10; uses x6, x7, x8
popcnt: addi x6, x0, 0
        addi x8, x0, 1
pop_l:  beq  x10, x0, pop_d
        and  x7, x10, x8
        add  x6, x6, x7
        srli x10, x10, 1
        j    pop_l
pop_d:  mv   x10, x6
        ret

# sqxor: x10 = (x10 * x10) xor 0x0A5A5000; calls mul, so ra goes on the stack
sqxor:  addi sp, sp, -4
        sw   ra, 0(sp)
        mv   x11, x10
        jal  ra, mul
        lui  x6, 0x0A5A5
        xor  x10, x10, x6
        lw   ra, 0(sp)
        addi sp, sp, 4
        jalr x0, 0(ra)          # same as ret
