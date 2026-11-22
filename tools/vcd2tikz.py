#!/usr/bin/env python3
"""Turn a VCD from tb_compare (Phase I) or tb_system (Phase II) into a TikZ
timing figure for the report.

The figure is generated from the real simulation output (not drawn by hand):
each column is one clock cycle, values are sampled at the falling edge,
i.e. in the middle of the cycle when all combinational signals are stable.

Usage:
    python3 tools/vcd2tikz.py sim/build/tb_compare_memcopy.vcd -o report/figures/wave.tex \
        --cycles 12
    python3 tools/vcd2tikz.py sim/build/tb_system_memcopy.vcd -o report/figures/wave2.tex \
        --set phase2 --first 0 --cycles 24
"""
import argparse
import sys

# (label, VCD path, kind) ; kind: 'hex' bus, 'bit' single wire, 'state' FSM
ROWS = [
    ("Harvard",          None,                              "title"),
    ("i\\_addr",         "tb_compare.h.u_core.i_addr",      "hex"),
    ("d\\_addr",         "tb_compare.h.u_core.d_addr",      "hex_if_daccess_h"),
    ("d\\_we",           "tb_compare.h.u_core.d_we",        "bit"),
    ("d\\_re",           "tb_compare.h.u_core.d_re",        "bit"),
    ("Shared memory",    None,                              "title"),
    ("m\\_addr",         "tb_compare.v.u_core.m_addr",      "hex"),
    ("m\\_is\\_data",    "tb_compare.v.u_core.m_is_data",   "bit"),
    ("state",            "tb_compare.v.u_core.state",       "state"),
]
CLK, RST = "tb_compare.clk", "tb_compare.rst"
H_DACC = ("tb_compare.h.u_core.d_we", "tb_compare.h.u_core.d_re")

# Phase II: modified Harvard system inside tb_system.
#   'hexif:<p1>|<p2>' shows the bus value only when one of the paths is 1
#   'owner' shows which cache the arbiter selects (I or D) while m_req is 1
MH = "tb_system.mh"
ROWS2 = [
    ("Core / L1",        None,                       "title"),
    ("i\\_addr",         f"{MH}.u_core.i_addr",      "hex"),
    ("i\\_ready",        f"{MH}.i_ready",            "bit"),
    ("d\\_addr",         f"{MH}.u_core.d_addr",      f"hexif:{MH}.u_core.d_we|{MH}.u_core.d_re"),
    ("d\\_ready",        f"{MH}.d_ready",            "bit"),
    ("wb\\_busy",        f"{MH}.dc_wb_busy",         "bit"),
    ("Shared memory",    None,                       "title"),
    ("m\\_req",          f"{MH}.m_req",              "bit"),
    ("grant",            f"{MH}.u_arb.sel_d",        "owner"),
    ("m\\_addr",         f"{MH}.m_addr",             f"hexif:{MH}.m_req"),
    ("m\\_ready",        f"{MH}.m_ready",            "bit"),
]
CLK2, RST2 = "tb_system.clk", "tb_system.rst"


def parse_vcd(path, wanted):
    """Return {path: [(time, value_str), ...]} for the wanted signal paths."""
    ids, scope, changes = {}, [], {}
    t = 0
    with open(path) as f:
        in_defs = True
        for line in f:
            tok = line.split()
            if not tok:
                continue
            if in_defs:
                if tok[0] == "$scope":
                    scope.append(tok[2])
                elif tok[0] == "$upscope":
                    scope.pop()
                elif tok[0] == "$var":
                    code, name = tok[3], tok[4]
                    full = ".".join(scope + [name])
                    if full in wanted:
                        ids.setdefault(code, []).append(full)
                elif tok[0] == "$enddefinitions":
                    in_defs = False
                continue
            c = tok[0]
            if c[0] == "#":
                t = int(c[1:])
            elif c[0] in "01xzXZ" and len(tok) == 1:
                for p in ids.get(c[1:], []):
                    changes.setdefault(p, []).append((t, c[0]))
            elif c[0] in "bB":
                for p in ids.get(tok[1], []):
                    changes.setdefault(p, []).append((t, c[1:]))
    missing = [w for w in wanted if w not in changes]
    if missing:
        sys.exit(f"signals not found in VCD: {missing}")
    return changes


def value_at(chg, t):
    v = None
    for ct, cv in chg:
        if ct > t:
            break
        v = cv
    return v


def to_int(v):
    return int(v, 2) if v and all(ch in "01" for ch in v) else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("vcd")
    ap.add_argument("-o", "--out", required=True)
    ap.add_argument("--cycles", type=int, default=12)
    ap.add_argument("--first", type=int, default=0, help="first cycle after reset to show")
    ap.add_argument("--set", choices=["phase1", "phase2"], default="phase1",
                    help="phase1: tb_compare Harvard vs baseline; phase2: tb_system modified Harvard")
    a = ap.parse_args()

    global ROWS, CLK, RST
    if a.set == "phase2":
        ROWS, CLK, RST = ROWS2, CLK2, RST2
    conds = {c for _, _, k in ROWS if k.startswith("hexif:") for c in k[6:].split("|")}
    wanted = {CLK, RST} | {p for _, p, _ in ROWS if p} | conds
    if a.set == "phase2":
        wanted.add(f"{MH}.m_req")
    else:
        wanted |= set(H_DACC)
    ch = parse_vcd(a.vcd, wanted)

    # sample points: falling edges of clk after reset is released
    rst_low = next(t for t, v in ch[RST] if v == "0")
    falls = [t for t, v in ch[CLK] if v == "0" and t >= rst_low]
    samples = falls[a.first:a.first + a.cycles]

    def sample(p):
        return [value_at(ch[p], t) for t in samples]

    h_dacc = [to_int(value_at(ch[H_DACC[0]], t)) or to_int(value_at(ch[H_DACC[1]], t))
              for t in samples] if a.set == "phase1" else []

    W, H = 1.05, 0.55           # cycle width, row height (cm)
    LBL = -0.2
    n = len(samples)
    out = ["% generated by tools/vcd2tikz.py from " + a.vcd.split("/")[-1] + " -- do not edit",
           "\\begin{tikzpicture}[font=\\scriptsize\\ttfamily, x=1cm, y=1cm]"]
    # cycle numbers + grid
    for i in range(n):
        out.append(f"\\node at ({(i + .5) * W:.2f},0.35) {{{a.first + i}}};")
    out.append(f"\\node[anchor=east] at ({LBL},0.35) {{\\normalfont cycle}};")
    for i in range(n + 1):
        out.append(f"\\draw[gray!40] ({i * W:.2f},0.15) -- ({i * W:.2f},{-H * len(ROWS):.2f});")

    for r, (label, path, kind) in enumerate(ROWS):
        y = -(r + 0.5) * H
        if kind == "title":
            out.append(f"\\node[anchor=east,font=\\normalfont\\bfseries\\scriptsize] at ({LBL},{y:.2f}) {{{label}}};")
            continue
        out.append(f"\\node[anchor=east] at ({LBL},{y:.2f}) {{{label}}};")
        vals = sample(path)
        for i, v in enumerate(vals):
            x0, x1 = i * W, (i + 1) * W
            iv = to_int(v)
            if kind == "bit":
                yy = y + (0.17 if iv else -0.17)
                out.append(f"\\draw[thick] ({x0:.2f},{yy:.2f}) -- ({x1:.2f},{yy:.2f});")
                prev = to_int(vals[i - 1]) if i else iv
                if i and prev != iv:
                    out.append(f"\\draw[thick] ({x0:.2f},{y - .17:.2f}) -- ({x0:.2f},{y + .17:.2f});")
                if iv:
                    out.append(f"\\fill[blue!15] ({x0:.2f},{y - .17:.2f}) rectangle ({x1:.2f},{y + .17:.2f});")
            else:
                if kind == "state":
                    text, fill = ("MEM", "orange!30") if iv else ("F/E", "white")
                elif kind == "hex_if_daccess_h" and not h_dacc[i]:
                    text, fill = "--", "gray!10"
                elif kind.startswith("hexif:"):
                    on = any(to_int(value_at(ch[c], samples[i])) for c in kind[6:].split("|"))
                    if on:
                        text, fill = ("x" if iv is None else f"{iv:03x}"), "green!25"
                    else:
                        text, fill = "--", "gray!10"
                elif kind == "owner":
                    if to_int(value_at(ch[f"{MH}.m_req"], samples[i])):
                        text, fill = ("D", "orange!30") if iv else ("I", "blue!15")
                    else:
                        text, fill = "--", "gray!10"
                else:
                    text = "x" if iv is None else f"{iv:03x}"
                    fill = "white"
                    if a.set == "phase1" and path.endswith("m_addr") and \
                            to_int(sample("tb_compare.v.u_core.m_is_data")[i]):
                        fill = "orange!30"
                    if kind == "hex_if_daccess_h":
                        fill = "green!25"
                out.append(f"\\draw[fill={fill}] ({x0 + .03:.2f},{y - .2:.2f}) -- ({x0 + .1:.2f},{y + .2:.2f}) -- "
                           f"({x1 - .1:.2f},{y + .2:.2f}) -- ({x1 - .03:.2f},{y - .2:.2f}) -- cycle;")
                out.append(f"\\node at ({(x0 + x1) / 2:.2f},{y:.2f}) {{{text}}};")
    out.append("\\end{tikzpicture}")
    with open(a.out, "w") as f:
        f.write("\n".join(out) + "\n")
    print(f"wrote {a.out}: {n} cycles from {a.vcd}")


if __name__ == "__main__":
    main()
