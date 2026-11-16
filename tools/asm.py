#!/usr/bin/env python3
"""Tiny assembler for the Project 9 RV32I subset.

Supported: add sub and or addi lw sw beq bne ebreak, plus the pseudo-op `nop`
(= addi x0,x0,0).  Labels end with ':', comments start with '#' or ';'.
Registers are x0..x31.  Immediates may be decimal, negative, or 0x hex.

Usage:
    python3 tools/asm.py prog.s -o prog.hex      # one 32-bit hex word per line
    python3 tools/asm.py --selftest
"""
import argparse
import re
import sys

OP_R, OP_I, OP_LW, OP_SW, OP_B = 0b0110011, 0b0010011, 0b0000011, 0b0100011, 0b1100011

R_TYPE = {  # name: (funct7, funct3)
    "add": (0b0000000, 0b000),
    "sub": (0b0100000, 0b000),
    "and": (0b0000000, 0b111),
    "or":  (0b0000000, 0b110),
}
B_TYPE = {"beq": 0b000, "bne": 0b001}


class AsmError(Exception):
    pass


def reg(tok):
    m = re.fullmatch(r"x(\d+)", tok.strip().lower())
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
    m = re.fullmatch(r"\s*(-?\w*)\s*\(\s*(x\d+)\s*\)\s*", tok)
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
    if mnem == "addi":
        want(ops, 3, mnem)
        return enc_i(num(ops[2]), reg(ops[1]), 0b000, reg(ops[0]), OP_I)
    if mnem == "nop":
        want(ops, 0, mnem)
        return enc_i(0, 0, 0b000, 0, OP_I)
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
        tgt = ops[2]
        off = labels[tgt] - pc if tgt in labels else num(tgt)
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
