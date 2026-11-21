#!/usr/bin/env python3
"""Golden-model instruction-set simulator for the Project 9 RV32I subset.

Written independently of the RTL and of tools/asm.py: it decodes the instruction
bits itself, so an encoding mistake in the assembler or a decode mistake in the
RTL shows up as a mismatch.

It predicts, for one program:
  * final registers x0..x31, the 256 data words and out_port;
  * retired instructions (EBREAK included), loads, stores, data accesses and
    d_fault events;
  * cache misses of direct-mapped caches (write-through, no-write-allocate):
      - split   : I-cache sees every fetch, D-cache every load to data RAM;
      - unified : one cache sees fetches and data-RAM loads in program order.
    Stores never allocate a line, so they never miss. Accesses to out_port and
    to invalid addresses bypass the caches.

Memory model (identical to the RTL):
  code        : word i of the program image at byte address 4*i (256 words)
  data space  : 0x000-0x3FF data RAM (256 words), 0x400 out_port (write-only,
                reads 0), anything else invalid (write ignored, read 0, fault)
  physical    : the unified lower-level memory keeps code at 0x000-0x3FF and
                the data RAM at 0x400-0x7FF (data address + 0x400), so the
                caches index with these physical addresses.

Usage:
  python3 tools/iss.py programs/memcopy.hex programs/memcopy_data.hex
  python3 tools/iss.py P.hex D.hex --json --cache 4:8      # line words : lines
  python3 tools/iss.py --selftest
"""
import argparse
import json
import sys

MASK = 0xFFFFFFFF
DATA_BASE = 0x400          # physical byte address of data word 0
IO_ADDR = 0x400            # out_port, in data space


def sx(val, bits):
    """sign-extend the low 'bits' bits of val"""
    val &= (1 << bits) - 1
    return val - (1 << bits) if val >> (bits - 1) else val


def signed(v):
    return v - (1 << 32) if v & 0x80000000 else v


def read_hex(path, words=256):
    mem = [0] * words
    if path:
        i = 0
        with open(path) as f:
            for line in f:
                line = line.split("//")[0].strip()
                if not line:
                    continue
                if line.startswith("@"):
                    i = int(line[1:], 16)
                    continue
                for tok in line.split():
                    if i < words:
                        mem[i] = int(tok, 16) & MASK
                    i += 1
    return mem


class DMCache:
    """Direct-mapped cache model: only tags and valid bits matter for misses."""

    def __init__(self, line_words, lines):
        self.lw, self.n = line_words, lines
        self.tags = [None] * lines
        self.misses = self.accesses = 0
        self.kind_misses = {"i": 0, "d": 0}         # unified cache: fetch vs data misses

    def _split(self, byte_addr):
        line = (byte_addr >> 2) // self.lw
        return line % self.n, line // self.n

    def read(self, byte_addr, kind="i"):
        self.accesses += 1
        idx, tag = self._split(byte_addr)
        if self.tags[idx] != tag:
            self.misses += 1
            self.kind_misses[kind] += 1
            self.tags[idx] = tag          # refill (whole line)


class ISS:
    def __init__(self, prog, data, caches=(), data_base=DATA_BASE):
        self.data_base = data_base
        self.imem = list(prog)
        self.dmem = list(data)
        self.x = [0] * 32
        self.pc = 0
        self.out_port = 0
        self.n_instr = self.n_load = self.n_store = self.n_fault = 0
        self.n_load_ram = self.n_store_ram = 0      # accesses that reach the data RAM
        self.halted = False
        # caches: list of (line_words, lines) for the split I/D pair; unified gets 2x lines
        self.split = [(DMCache(w, n), DMCache(w, n)) for (w, n) in caches]
        self.unified = [DMCache(w, 2 * n) for (w, n) in caches]

    # ---- cache event hooks ----
    def _fetch_event(self, pc):
        for ic, _ in self.split:
            ic.read(pc)
        for uc in self.unified:
            uc.read(pc)

    def _load_event(self, data_addr):
        phys = data_addr + self.data_base
        for _, dc in self.split:
            dc.read(phys, "d")
        for uc in self.unified:
            uc.read(phys, "d")

    # ---- data space ----
    def _region(self, a):
        if a >> 10 == 0:
            return "ram"
        if a == IO_ADDR:
            return "io"
        return "bad"

    def load(self, a):
        self.n_load += 1
        r = self._region(a)
        if r == "ram":
            self.n_load_ram += 1
            self._load_event(a)
            return self.dmem[(a >> 2) & 0xFF]
        if r == "bad":
            self.n_fault += 1
        return 0

    def store(self, a, v):
        self.n_store += 1
        r = self._region(a)
        if r == "ram":
            self.n_store_ram += 1
            self.dmem[(a >> 2) & 0xFF] = v      # no-write-allocate: caches untouched
        elif r == "io":
            self.out_port = v
        else:
            self.n_fault += 1

    def wr(self, rd, v):
        if rd:
            self.x[rd] = v & MASK

    def step(self):
        pc = self.pc
        self._fetch_event(pc)
        ins = self.imem[(pc >> 2) & 0xFF]
        op = ins & 0x7F
        rd = (ins >> 7) & 0x1F
        f3 = (ins >> 12) & 0x7
        rs1 = (ins >> 15) & 0x1F
        rs2 = (ins >> 20) & 0x1F
        f7 = ins >> 25
        a, b = self.x[rs1], self.x[rs2]
        imm_i = sx(ins >> 20, 12)
        imm_s = sx(((ins >> 25) << 5) | ((ins >> 7) & 0x1F), 12)
        imm_b = sx((((ins >> 31) & 1) << 12) | (((ins >> 7) & 1) << 11)
                   | (((ins >> 25) & 0x3F) << 5) | (((ins >> 8) & 0xF) << 1), 13)
        imm_j = sx((((ins >> 31) & 1) << 20) | (((ins >> 12) & 0xFF) << 12)
                   | (((ins >> 20) & 1) << 11) | (((ins >> 21) & 0x3FF) << 1), 21)
        nxt = (pc + 4) & MASK
        self.n_instr += 1

        if ins == 0x00100073:                                   # EBREAK
            self.halted = True
            return
        if op == 0b0110011:                                     # R-type
            key = (f7, f3)
            res = {(0, 0): a + b, (0x20, 0): a - b, (0, 7): a & b, (0, 6): a | b,
                   (0, 4): a ^ b, (0, 2): int(signed(a) < signed(b)),
                   (0, 1): a << (b & 31), (0, 5): a >> (b & 31)}.get(key)
            if res is not None:
                self.wr(rd, res)
        elif op == 0b0010011:                                   # I-type ALU
            sh = imm_i & 31
            if f3 == 0:
                self.wr(rd, a + imm_i)
            elif f3 == 4:
                self.wr(rd, a ^ (imm_i & MASK))
            elif f3 == 2:
                self.wr(rd, int(signed(a) < imm_i))
            elif f3 == 1 and f7 == 0:
                self.wr(rd, a << sh)
            elif f3 == 5 and f7 == 0:
                self.wr(rd, a >> sh)
        elif op == 0b0000011 and f3 == 2:                       # LW
            self.wr(rd, self.load((a + imm_i) & MASK))
        elif op == 0b0100011 and f3 == 2:                       # SW
            self.store((a + imm_s) & MASK, b)
        elif op == 0b1100011:                                   # branches
            taken = {0: a == b, 1: a != b, 4: signed(a) < signed(b),
                     5: signed(a) >= signed(b)}.get(f3, False)
            if taken:
                nxt = (pc + imm_b) & MASK
        elif op == 0b1101111:                                   # JAL
            self.wr(rd, pc + 4)
            nxt = (pc + imm_j) & MASK
        elif op == 0b1100111 and f3 == 0:                       # JALR
            t = (a + imm_i) & MASK & ~1
            self.wr(rd, pc + 4)
            nxt = t
        elif op == 0b0110111:                                   # LUI
            self.wr(rd, ins & 0xFFFFF000)
        # anything else: NOP (same as the RTL decoder)
        self.pc = nxt

    def run(self, max_steps=200000):
        while not self.halted and self.n_instr < max_steps:
            self.step()
        if not self.halted:
            raise RuntimeError(f"no EBREAK within {max_steps} instructions")
        return self

    def report(self):
        r = {
            "instr": self.n_instr, "loads": self.n_load, "stores": self.n_store,
            "d_access": self.n_load + self.n_store, "faults": self.n_fault,
            "loads_ram": self.n_load_ram, "stores_ram": self.n_store_ram,
            "out_port": self.out_port, "regs": list(self.x), "dmem": list(self.dmem),
            "caches": [],
        }
        for (ic, dc), uc in zip(self.split, self.unified):
            r["caches"].append({
                "line_words": ic.lw, "lines": ic.n,
                "i_miss": ic.misses, "d_miss": dc.misses, "u_miss": uc.misses,
                "u_imiss": uc.kind_misses["i"], "u_dmiss": uc.kind_misses["d"],
                "i_acc": ic.accesses, "d_acc": dc.accesses, "u_acc": uc.accesses,
            })
        return r


def simulate(prog_hex, data_hex, caches=(), data_base=DATA_BASE):
    return ISS(read_hex(prog_hex), read_hex(data_hex), caches, data_base).run().report()


def selftest():
    """Hand-checked micro programs, encoded here as raw words (not via asm.py)."""
    bad = 0

    def run(words, data=None):
        return ISS(words + [0] * (256 - len(words)), data or [0] * 256, [(4, 2)]).run()

    # addi x1,x0,-8 ; srli x2,x1,28 ; slli x3,x1,4 ; slti x4,x1,0 ; xori x5,x1,-1 ; ebreak
    s = run([0xFF800093, 0x01C0D113, 0x00409193, 0x0000A213, 0xFFF0C293, 0x00100073])
    for r, exp in ((1, 0xFFFFFFF8), (2, 0xF), (3, 0xFFFFFF80), (4, 1), (5, 7)):
        ok = s.x[r] == exp
        bad += not ok
        print(f"{'ok ' if ok else 'BAD'} x{r} = {s.x[r]:08x} (expected {exp:08x})")
    # lui x5,0x12345 ; jal x1,8 ; addi x6,x0,1 (skipped) ; ebreak
    s = run([0x123452B7, 0x008000EF, 0x00100313, 0x00100073])
    for name, got, exp in (("lui x5", s.x[5], 0x12345000), ("jal link x1", s.x[1], 8),
                           ("skipped x6", s.x[6], 0), ("instr", s.n_instr, 3)):
        ok = got == exp
        bad += not ok
        print(f"{'ok ' if ok else 'BAD'} {name} = {got:x} (expected {exp:x})")
    # split cache, 2 lines x 4 words: fetches 0,4,8,12 hit one line after one miss
    ok = s.split[0][0].misses == 1
    bad += not ok
    print(f"{'ok ' if ok else 'BAD'} I-misses = {s.split[0][0].misses} (expected 1)")
    print("ISS SELFTEST", "PASS" if bad == 0 else f"FAIL ({bad})")
    return bad == 0


def parse_cache(text):
    w, n = text.split(":")
    return int(w), int(n)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("prog", nargs="?")
    ap.add_argument("data", nargs="?")
    ap.add_argument("--cache", action="append", default=[], type=parse_cache,
                    help="LINE_WORDS:LINES of each split cache (unified = 2*LINES); repeatable")
    ap.add_argument("--json", action="store_true", help="print the full report as JSON")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        sys.exit(0 if selftest() else 1)
    if not a.prog:
        ap.error("program hex file required")
    r = simulate(a.prog, a.data, a.cache)
    if a.json:
        json.dump(r, sys.stdout)
        print()
        return
    print(f"instr={r['instr']} loads={r['loads']} stores={r['stores']} faults={r['faults']} "
          f"out_port={r['out_port']}")
    print("regs:", " ".join(f"x{i}={v:x}" for i, v in enumerate(r["regs"]) if v))
    for c in r["caches"]:
        print(f"cache {c['line_words']}w x {c['lines']} lines: I-miss={c['i_miss']} "
              f"D-miss={c['d_miss']} unified({2 * c['lines']} lines)-miss={c['u_miss']}")


if __name__ == "__main__":
    main()
