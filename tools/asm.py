#!/usr/bin/env python3
"""Tiny assembler for the Project 9 RV32I subset.

Phase I : add sub and or addi lw sw beq bne ebreak
Phase II: xor slt sll srl xori slti slli srli blt bge jal jalr lui
Pseudo-ops: nop (= addi x0,x0,0), j label (= jal x0,label), ret (= jalr x0,0(x1)),
            jal label (= jal x1,label), mv rd,rs (= addi rd,rs,0).
Labels end with ':', comments start with '#' or ';'.
Registers are x0..x31 (ABI names zero, ra, sp are accepted too).
Immediates may be decimal, negative, or 0x hex.

Usage:
    python3 tools/asm.py prog.s -o prog.hex      # one 32-bit hex word per line
    python3 tools/asm.py --selftest
"""
import argparse
import re
import sys

OP_R, OP_I, OP_LW, OP_SW, OP_B = 0b0110011, 0b0010011, 0b0000011, 0b0100011, 0b1100011
OP_JAL, OP_JALR, OP_LUI = 0b1101111, 0b1100111, 0b0110111

R_TYPE = {  # name: (funct7, funct3)
    "add": (0b0000000, 0b000),
    "sub": (0b0100000, 0b000),
    "and": (0b0000000, 0b111),
    "or":  (0b0000000, 0b110),
    "xor": (0b0000000, 0b100),
    "slt": (0b0000000, 0b010),
    "sll": (0b0000000, 0b001),
    "srl": (0b0000000, 0b101),
}
I_ALU = {"addi": 0b000, "xori": 0b100, "slti": 0b010}     # 12-bit signed immediate
I_SHIFT = {"slli": 0b001, "srli": 0b101}                   # 5-bit shift amount, funct7 = 0
B_TYPE = {"beq": 0b000, "bne": 0b001, "blt": 0b100, "bge": 0b101}
ABI = {"zero": 0, "ra": 1, "sp": 2}


class AsmError(Exception):
    pass


def reg(tok):
    t = tok.strip().lower()
    if t in ABI:
        return ABI[t]
    m = re.fullmatch(r"x(\d+)", t)
    if not m or int(m.group(1)) > 31:
        raise AsmError(f"bad register '{tok}'")
    return int(m.group(1))


def num(tok):
    try:
        return int(tok.strip(), 0)
    except ValueError:
        raise AsmError(f"bad number '{tok}'")


def check_range(val, bits, what):
    lo, hi = -(1 << (bits - 1)), (1 << (bits - 1)) - 1
    if not lo <= val <= hi:
        raise AsmError(f"{what} {val} out of range [{lo}, {hi}]")


def mem_operand(tok):
    """'8(x2)' -> (8, 2)"""
    m = re.fullmatch(r"\s*(-?\w*)\s*\(\s*(\w+)\s*\)\s*", tok)
    if not m:
        raise AsmError(f"bad memory operand '{tok}', expected imm(xN)")
    return (num(m.group(1)) if m.group(1) else 0), reg(m.group(2))


def enc_r(f7, rs2, rs1, f3, rd, op):
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def enc_i(imm, rs1, f3, rd, op):
    check_range(imm, 12, "I-immediate")
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def enc_s(imm, rs2, rs1, f3, op):
    check_range(imm, 12, "S-immediate")
    imm &= 0xFFF
    return ((imm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((imm & 0x1F) << 7) | op


def enc_b(off, rs2, rs1, f3, op):
    check_range(off, 13, "branch offset")
    if off % 2:
        raise AsmError("branch offset must be even")
    off &= 0x1FFF
    return (((off >> 12) & 1) << 31) | (((off >> 5) & 0x3F) << 25) | (rs2 << 20) | (rs1 << 15) \
        | (f3 << 12) | (((off >> 1) & 0xF) << 8) | (((off >> 11) & 1) << 7) | op


def enc_u(imm20, rd, op):
    if not 0 <= imm20 < (1 << 20):
        raise AsmError(f"U-immediate {imm20} out of range [0, 0xFFFFF]")
    return (imm20 << 12) | (rd << 7) | op


def enc_j(off, rd, op):
    check_range(off, 21, "jump offset")
    if off % 2:
        raise AsmError("jump offset must be even")
    off &= 0x1FFFFF
    return (((off >> 20) & 1) << 31) | (((off >> 1) & 0x3FF) << 21) | (((off >> 11) & 1) << 20) \
        | (((off >> 12) & 0xFF) << 12) | (rd << 7) | op


def target(tok, pc, labels):
    """label or numeric offset -> PC-relative offset"""
    return labels[tok] - pc if tok in labels else num(tok)


def split_lines(src):
    """Yield (line_no, label_list, mnemonic, operand_list)."""
    for n, raw in enumerate(src.splitlines(), 1):
        line = re.split(r"[#;]", raw, maxsplit=1)[0].strip()
        labels = []
        while True:
            m = re.match(r"([A-Za-z_]\w*)\s*:\s*(.*)", line)
            if not m:
                break
            labels.append(m.group(1))
            line = m.group(2)
        if line:
            parts = line.split(None, 1)
            ops = [o.strip() for o in parts[1].split(",")] if len(parts) > 1 else []
            yield n, labels, parts[0].lower(), ops
        else:
            yield n, labels, None, []


def assemble(src):
    # pass 1: label addresses
    labels, pc = {}, 0
    for n, labs, mnem, _ in split_lines(src):
        for lab in labs:
            if lab in labels:
                raise AsmError(f"line {n}: duplicate label '{lab}'")
            labels[lab] = pc
        if mnem:
            pc += 4

    # pass 2: encode
    words, pc = [], 0
    for n, _, mnem, ops in split_lines(src):
        if not mnem:
            continue
        try:
            words.append(encode(mnem, ops, pc, labels))
        except AsmError as e:
            raise AsmError(f"line {n}: {e}")
        pc += 4
    if len(words) > 256:
        raise AsmError(f"program has {len(words)} words, instruction memory holds 256")
    return words


def want(ops, k, mnem):
    if len(ops) != k:
        raise AsmError(f"'{mnem}' takes {k} operands, got {len(ops)}")


def encode(mnem, ops, pc, labels):
    if mnem in R_TYPE:
        want(ops, 3, mnem)
        f7, f3 = R_TYPE[mnem]
        return enc_r(f7, reg(ops[2]), reg(ops[1]), f3, reg(ops[0]), OP_R)
    if mnem in I_ALU:
        want(ops, 3, mnem)
        return enc_i(num(ops[2]), reg(ops[1]), I_ALU[mnem], reg(ops[0]), OP_I)
    if mnem in I_SHIFT:
        want(ops, 3, mnem)
        sh = num(ops[2])
        if not 0 <= sh <= 31:
            raise AsmError(f"shift amount {sh} out of range [0, 31]")
        return enc_i(sh, reg(ops[1]), I_SHIFT[mnem], reg(ops[0]), OP_I)
    if mnem == "nop":
        want(ops, 0, mnem)
        return enc_i(0, 0, 0b000, 0, OP_I)
    if mnem == "mv":
        want(ops, 2, mnem)
        return enc_i(0, reg(ops[1]), 0b000, reg(ops[0]), OP_I)
    if mnem == "lui":
        want(ops, 2, mnem)
        return enc_u(num(ops[1]), reg(ops[0]), OP_LUI)
    if mnem == "jal":
        if len(ops) == 1:                                   # jal label  -> rd = ra
            return enc_j(target(ops[0], pc, labels), 1, OP_JAL)
        want(ops, 2, mnem)
        return enc_j(target(ops[1], pc, labels), reg(ops[0]), OP_JAL)
    if mnem == "j":
        want(ops, 1, mnem)
        return enc_j(target(ops[0], pc, labels), 0, OP_JAL)
    if mnem == "jalr":
        if len(ops) == 2:                                   # jalr rd, imm(rs1)
            imm, rs1 = mem_operand(ops[1])
        else:                                               # jalr rd, rs1, imm
            want(ops, 3, mnem)
            imm, rs1 = num(ops[2]), reg(ops[1])
        return enc_i(imm, rs1, 0b000, reg(ops[0]), OP_JALR)
    if mnem == "ret":
        want(ops, 0, mnem)
        return enc_i(0, 1, 0b000, 0, OP_JALR)
    if mnem == "lw":
        want(ops, 2, mnem)
        imm, rs1 = mem_operand(ops[1])
        return enc_i(imm, rs1, 0b010, reg(ops[0]), OP_LW)
    if mnem == "sw":
        want(ops, 2, mnem)
        imm, rs1 = mem_operand(ops[1])
        return enc_s(imm, reg(ops[0]), rs1, 0b010, OP_SW)
    if mnem in B_TYPE:
        want(ops, 3, mnem)
        off = target(ops[2], pc, labels)
        return enc_b(off, reg(ops[1]), reg(ops[0]), B_TYPE[mnem], OP_B)
    if mnem == "ebreak":
        want(ops, 0, mnem)
        return 0x00100073
    raise AsmError(f"unknown instruction '{mnem}'")


def selftest():
    # Expected values worked out by hand from the RV32I field layout:
    cases = [
        # addi x1,x0,5  : imm=000000000101 rs1=00000 f3=000 rd=00001 op=0010011
        ("addi x1, x0, 5", 0x00500093),
        # add x3,x1,x2  : f7=0000000 rs2=00010 rs1=00001 f3=000 rd=00011 op=0110011
        ("add x3, x1, x2", 0x002081B3),
        # sub x3,x1,x2  : f7=0100000 -> top bits 0x40...
        ("sub x3, x1, x2", 0x402081B3),
        ("and x3, x1, x2", 0x0020F1B3),
        ("or x3, x1, x2", 0x0020E1B3),
        # sw x3,0(x0)   : imm[11:5]=0 rs2=00011 rs1=0 f3=010 imm[4:0]=0 op=0100011
        ("sw x3, 0(x0)", 0x00302023),
        # lw x4,0(x0)   : imm=0 rs1=0 f3=010 rd=00100 op=0000011
        ("lw x4, 0(x0)", 0x00002203),
        # addi x5,x0,-1 : imm=0xFFF
        ("addi x5, x0, -1", 0xFFF00293),
        # sw x2,1024(x0): imm=0x400 -> imm[11:5]=0100000, imm[4:0]=0
        ("sw x2, 1024(x0)", 0x40202023),
        # beq x1,x2,8   : off=8 -> imm[4:1]=0100 at bits 11:8
        ("beq x1, x2, 8", 0x00208463),
        # bne x1,x0,-4  : off=-4 (0x1FFC) -> bit31=1, imm[10:5]=111111, imm[4:1]=1110, imm[11]=1
        ("bne x1, x0, -4", 0xFE009EE3),
        ("ebreak", 0x00100073),
        # ---- Phase II instructions ----
        # R-type, f7=0: only funct3 changes (xor 100, slt 010, sll 001, srl 101)
        ("xor x3, x1, x2", 0x0020C1B3),
        ("slt x3, x1, x2", 0x0020A1B3),
        ("sll x3, x1, x2", 0x002091B3),
        ("srl x3, x1, x2", 0x0020D1B3),
        # xori x1,x1,-1 (= not): imm=0xFFF rs1=1 f3=100 rd=1
        ("xori x1, x1, -1", 0xFFF0C093),
        # slti x1,x2,5: imm=5 rs1=2 f3=010 rd=1
        ("slti x1, x2, 5", 0x00512093),
        # slli x1,x1,3 / srli x1,x1,3: shamt=3 in imm[4:0], f7=0
        ("slli x1, x1, 3", 0x00309093),
        ("srli x1, x1, 3", 0x0030D093),
        ("blt x1, x2, 8", 0x0020C463),
        ("bge x1, x2, 8", 0x0020D463),
        # lui x5,0x12345: imm[31:12]=0x12345 rd=5 op=0110111
        ("lui x5, 0x12345", 0x123452B7),
        # jal x1,8: imm[10:1]=4 at bits 30:21 -> 0x00800000 | rd=1 | 1101111
        ("jal x1, 8", 0x008000EF),
        # jal x0,-8: off=0x1FFFF8 -> bit31=1, imm[10:1]=1111111100, imm[11]=1, imm[19:12]=0xFF
        ("j -8", 0xFF9FF06F),
        # jalr x1,0(x5): rs1=5 f3=000 rd=1 op=1100111
        ("jalr x1, 0(x5)", 0x000280E7),
        # ret = jalr x0,0(x1): the well-known encoding 0x00008067
        ("ret", 0x00008067),
    ]
    bad = 0
    for text, expect in cases:
        got = assemble(text)[0]
        ok = got == expect
        bad += not ok
        print(f"{'ok ' if ok else 'BAD'} {text:<20} {got:08x} (expected {expect:08x})")
    # label resolution: loop back by -4
    got = assemble("top: nop\n bne x1, x0, top")[1]
    ok = got == 0xFE009EE3
    bad += not ok
    print(f"{'ok ' if ok else 'BAD'} {'label backward':<20} {got:08x} (expected fe009ee3)")
    # forward jump to a label: jal ra, f with f two words ahead -> offset +8
    got = assemble("jal ra, f\n nop\nf: ret")[0]
    ok = got == 0x008000EF
    bad += not ok
    print(f"{'ok ' if ok else 'BAD'} {'label forward jal':<20} {got:08x} (expected 008000ef)")
    print("SELFTEST", "PASS" if bad == 0 else f"FAIL ({bad})")
    return bad == 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("src", nargs="?")
    ap.add_argument("-o", "--out")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--pad", type=int, default=256,
                    help="pad output with zero words to this length (instruction memory size)")
    a = ap.parse_args()
    if a.selftest:
        sys.exit(0 if selftest() else 1)
    if not a.src:
        ap.error("source file required")
    with open(a.src) as f:
        try:
            words = assemble(f.read())
        except AsmError as e:
            sys.exit(f"{a.src}: {e}")
    words += [0] * (a.pad - len(words))       # fill the rest of instr_mem with 0 (= NOP)
    text = "".join(f"{w:08x}\n" for w in words)
    if a.out:
        with open(a.out, "w") as f:
            f.write(text)
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
