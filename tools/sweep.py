#!/usr/bin/env python3
"""Phase II parameter sweep: run tb_system over

    programs x memory latency L {1,2,4,8,16} x lines per split cache {1..32}
             x write buffer {off, on}            (line size 4 words)

and check every RTL number against the golden model (tools/iss.py):

  * instruction and data-access counts of every design = ISS;
  * modified Harvard I/D misses = ISS split caches (LINES lines each);
  * unified-cache fetch/data misses = ISS unified cache (2*LINES lines);
  * no-cache memory reads = every fetch and every data-RAM load;
  * reference final registers / data memory / out_port = ISS;
  * write buffer off: exact stall model
        cached   : I-stall = L * I-miss,
                   D-stall = L * D-miss + (L-1) * RAM stores
        no cache : I-stall = (L-1) * instructions,
                   D-stall = (L-1) * (RAM loads + RAM stores)
  * tb_system's own checks (state = reference, cycle identities, Phase I
    equivalence at L = 1) must PASS in every run.

Placement experiment: the same runs at L = 8, write buffer on, all sizes,
with the data image moved from physical 0x400 to 0x480 (DATA_BASE), so code
and data no longer alias perfectly in the unified cache.

Outputs (from the repository root):
  results/phase2/sweep.csv        one row per (program, design, L, lines, wbuf)
  results/phase2/summary.md       tables used in the report
  report/data/*.dat               plot data for pgfplots
  results/logs/sweep.log          check summary

Usage:  python3 tools/sweep.py [--quick] [--jobs N]
"""
import argparse
import concurrent.futures as cf
import csv
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import iss  # noqa: E402

PROGRAMS = ["basic", "array_sum", "memcopy", "count_loop",
            "bubble_sort", "subroutine", "transpose", "isa_test"]
LATENCIES = [1, 2, 4, 8, 16]
LINES = [1, 2, 4, 8, 16, 32]
WBUFS = [0, 1]
LINE_WORDS = 4
DESIGNS = ["ideal", "vn_ideal", "mh", "unified", "nocache"]
BASE, SKEW = 0x400, 0x480

RTL = """rtl/mem/instr_mem.v rtl/mem/data_mem.v rtl/mem/addr_decoder.v rtl/mem/rw_ctrl.v
rtl/mem/harvard_mem.v rtl/mem/cache.v rtl/mem/main_mem.v rtl/core/regfile.v rtl/core/alu.v
rtl/core/imm_gen.v rtl/core/control.v rtl/core/pc_reg.v rtl/core/cpu_core.v
rtl/common/perf_counters.v rtl/common/event_counters.v rtl/common/arbiter.v rtl/harvard_top.v
rtl/mh_top.v rtl/baseline/shared_mem.v rtl/baseline/cpu_core_vn.v rtl/baseline/vn_top.v
rtl/baseline/vnc_top.v""".split()

BUILD = os.path.join(ROOT, "sim", "build", "sweep")
RES_RE = re.compile(r"RESULT (.*)")


def compile_cfg(cfg):
    L, n, wb, base = cfg
    out = os.path.join(BUILD, f"sys_L{L}_n{n}_wb{wb}_b{base:x}.vvp")
    cmd = ["iverilog", "-g2005", "-I", os.path.join(ROOT, "tb"), "-s", "tb_system",
           f"-Ptb_system.LATENCY={L}", f"-Ptb_system.LINES={n}", f"-Ptb_system.WBUF={wb}",
           f"-Ptb_system.DATA_BASE={base}",
           f"-Ptb_system.LINE_WORDS={LINE_WORDS}", "-o", out,
           os.path.join(ROOT, "tb", "tb_system.v")] + [os.path.join(ROOT, f) for f in RTL]
    subprocess.run(cmd, check=True, capture_output=True, text=True)
    return cfg, out


def run_one(vvp, prog, dump=None):
    args = ["vvp", "-n", vvp, f"+PROG={ROOT}/programs/{prog}.hex",
            f"+DATA={ROOT}/programs/{prog}_data.hex", f"+NAME={prog}"]
    if dump:
        args.append(f"+DUMP={dump}")
    p = subprocess.run(args, capture_output=True, text=True, cwd=os.path.join(ROOT, "sim"))
    rows = []
    for line in p.stdout.splitlines():
        m = RES_RE.match(line)
        if m:
            d = dict(kv.split("=") for kv in m.group(1).split())
            rows.append({k: (v if k in ("prog", "design") else int(v)) for k, v in d.items()})
    ok = "PASS" in p.stdout and "FAIL" not in p.stdout
    fails = [ln for ln in p.stdout.splitlines() if "FAIL" in ln]
    return rows, ok, fails


def read_words(path):
    out = []
    with open(path) as f:
        for line in f:
            line = line.split("//")[0].strip()
            if line and not line.startswith("@"):
                out.append(int(line, 16))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--quick", action="store_true", help="L {1,8}, lines {2,8}: fast smoke test")
    ap.add_argument("--jobs", type=int, default=os.cpu_count() or 4)
    a = ap.parse_args()
    lat, lines = (LATENCIES, LINES) if not a.quick else ([1, 8], [2, 8])
    os.makedirs(BUILD, exist_ok=True)
    os.makedirs(os.path.join(ROOT, "results", "phase2"), exist_ok=True)
    os.makedirs(os.path.join(ROOT, "results", "logs"), exist_ok=True)
    os.makedirs(os.path.join(ROOT, "report", "data"), exist_ok=True)

    # ---------------- golden model ----------------
    gold, gcache = {}, {}
    for base in (BASE, SKEW):
        for p in PROGRAMS:
            g = iss.simulate(f"{ROOT}/programs/{p}.hex", f"{ROOT}/programs/{p}_data.hex",
                             [(LINE_WORDS, n) for n in lines], data_base=base)
            if base == BASE:
                gold[p] = g
            for c in g["caches"]:
                gcache[(p, c["lines"], base)] = c

    # ---------------- RTL runs ----------------
    cfgs = [(L, n, wb, BASE) for L in lat for n in lines for wb in WBUFS]
    cfgs += [(8, n, 1, SKEW) for n in lines]
    print(f"compiling {len(cfgs)} configurations, running {len(cfgs) * len(PROGRAMS)} simulations ...")
    rows, errors, n_runs = [], [], 0
    with cf.ThreadPoolExecutor(a.jobs) as ex:
        vvps = dict(ex.map(compile_cfg, cfgs))
        jobs = {ex.submit(run_one, vvps[c], p): (c, p) for c in cfgs for p in PROGRAMS}
        for fut in cf.as_completed(jobs):
            (L, n, wb, base), p = jobs[fut]
            r, ok, fails = fut.result()
            n_runs += 1
            if not ok or len(r) != len(DESIGNS):
                errors.append(f"tb_system FAIL {p} L={L} lines={n} wbuf={wb} base={base:#x}: {fails[:3]}")
            for x in r:
                x["base"] = base
            rows += r

    # ---------------- reference final state vs ISS ----------------
    dump_dir = os.path.join(BUILD, "dump")
    os.makedirs(dump_dir, exist_ok=True)
    state_checked = 0
    for p in PROGRAMS:
        pre = os.path.join(dump_dir, p)
        _, ok, fails = run_one(vvps[cfgs[0]], p, dump=pre)
        regs, dmem = read_words(pre + "_regs.hex"), read_words(pre + "_dmem.hex")
        g = gold[p]
        if regs != g["regs"]:
            errors.append(f"{p}: reference registers differ from ISS")
        if dmem != g["dmem"]:
            errors.append(f"{p}: reference data memory differs from ISS")
        state_checked += 1

    # ---------------- cross-check every row ----------------
    checks = 0

    def expect(cond, msg):
        nonlocal checks
        checks += 1
        if not cond:
            errors.append(msg)

    for r in rows:
        p, d, L, n, wb, base = r["prog"], r["design"], r["L"], r["lines"], r["wbuf"], r["base"]
        g, c = gold[p], gcache[(p, n, base)]
        tag = f"{p} {d} L={L} lines={n} wbuf={wb} base={base:#x}"
        expect(r["instr"] == g["instr"], f"{tag}: instr {r['instr']} != ISS {g['instr']}")
        expect(r["dacc"] == g["d_access"], f"{tag}: dacc {r['dacc']} != ISS {g['d_access']}")
        if d == "mh":
            expect(r["imiss"] == c["i_miss"], f"{tag}: I-miss {r['imiss']} != ISS {c['i_miss']}")
            expect(r["dmiss"] == c["d_miss"], f"{tag}: D-miss {r['dmiss']} != ISS {c['d_miss']}")
        elif d == "unified":
            expect(r["imiss"] == c["u_imiss"], f"{tag}: fetch miss {r['imiss']} != ISS {c['u_imiss']}")
            expect(r["dmiss"] == c["u_dmiss"], f"{tag}: data miss {r['dmiss']} != ISS {c['u_dmiss']}")
        elif d == "nocache":
            expect(r["imiss"] == g["instr"], f"{tag}: memory fetches {r['imiss']} != instr")
            expect(r["dmiss"] == g["loads_ram"], f"{tag}: memory loads {r['dmiss']} != RAM loads")
        if wb == 0 and d in ("mh", "unified"):
            expect(r["istall"] == L * r["imiss"], f"{tag}: I-stall {r['istall']} != L*I-miss")
            expect(r["dstall"] == L * r["dmiss"] + (L - 1) * g["stores_ram"],
                   f"{tag}: D-stall {r['dstall']} != L*D-miss + (L-1)*stores")
        if wb == 0 and d == "nocache":
            expect(r["istall"] == (L - 1) * g["instr"], f"{tag}: I-stall model")
            expect(r["dstall"] == (L - 1) * (g["loads_ram"] + g["stores_ram"]), f"{tag}: D-stall model")
        r["cpi"] = r["cycles"] / r["instr"]

    # ---------------- outputs ----------------
    fields = ["prog", "design", "base", "L", "lines", "line_words", "wbuf", "cycles", "instr", "cpi",
              "dacc", "imiss", "dmiss", "istall", "dstall", "wbstall", "conflict"]
    rows.sort(key=lambda r: (r["base"], PROGRAMS.index(r["prog"]), DESIGNS.index(r["design"]),
                             r["L"], r["lines"], r["wbuf"]))
    with open(os.path.join(ROOT, "results", "phase2", "sweep.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for r in rows:
            w.writerow({k: (f"{r[k]:.4f}" if k == "cpi" else (f"{r[k]:#x}" if k == "base" else r[k]))
                        for k in fields})

    if not a.quick:
        write_tables(rows, gold)

    log = [f"sweep: {n_runs} tb_system runs ({len(cfgs)} configurations x {len(PROGRAMS)} programs), "
           f"{len(rows)} result rows, {checks} golden-model checks, "
           f"{state_checked} final states compared with the ISS",
           f"errors: {len(errors)}"] + errors[:50]
    log.append("SWEEP PASS" if not errors else "SWEEP FAIL")
    with open(os.path.join(ROOT, "results", "logs", "sweep.log"), "w") as f:
        f.write("\n".join(log) + "\n")
    print("\n".join(log))
    sys.exit(0 if not errors else 1)


# ============================================================================
#  LaTeX table bodies for the report (\input by report/sections/*.tex)
# ============================================================================
def tex_name(p):
    return p.replace("_", "\\_")


def write_tex_tables(get, gold, data):
    head = "% generated by tools/sweep.py -- do not edit\n"
    L0, N0 = 8, 8
    # Phase I table: ideal Harvard vs ideal single-port baseline
    with open(os.path.join(data, "tab_phase1.tex"), "w") as f:
        f.write(head)
        for k, p in enumerate(PROGRAMS):
            h, v = get(p, "ideal", 1, 8, 1), get(p, "vn_ideal", 1, 8, 1)
            if k == 4:
                f.write("\\midrule\n")
            f.write(f"{tex_name(p)} & {h['instr']} & {100 * h['dacc'] / h['instr']:.1f} & "
                    f"{h['cycles']} & {v['cycles']} & {v['cpi']:.2f} & "
                    f"{v['cycles'] / h['cycles']:.2f}$\\times$ \\\\\n")
    # write-buffer ablation
    with open(os.path.join(data, "tab_wbuf.tex"), "w") as f:
        f.write(head)
        for p in PROGRAMS:
            m0, m1 = get(p, "mh", L0, N0, 0), get(p, "mh", L0, N0, 1)
            u0, u1 = get(p, "unified", L0, N0, 0), get(p, "unified", L0, N0, 1)
            f.write(f"{tex_name(p)} & {gold[p]['stores_ram']} & {m0['cycles']} & {m1['cycles']} & "
                    f"{100 * (m0['cycles'] - m1['cycles']) / m0['cycles']:.1f}\\% & "
                    f"{u0['cycles']} & {u1['cycles']} \\\\\n")
    # split vs unified at L = 8, N = 8
    with open(os.path.join(data, "tab_split.tex"), "w") as f:
        f.write(head)
        for p in PROGRAMS:
            m, u = get(p, "mh", L0, N0, 1), get(p, "unified", L0, N0, 1)
            f.write(f"{tex_name(p)} & {m['imiss']} & {m['dmiss']} & {u['imiss']} & {u['dmiss']} & "
                    f"{m['cpi']:.2f} & {u['cpi']:.2f} & {u['cycles'] / m['cycles']:.2f}$\\times$ \\\\\n")


# ============================================================================
#  tables and plot data
# ============================================================================
def write_tables(rows, gold):
    idx = {(r["prog"], r["design"], r["L"], r["lines"], r["wbuf"], r["base"]): r for r in rows}

    def get(p, d, L, n, wb, base=BASE):
        if d in ("ideal", "vn_ideal"):       # independent of the memory parameters
            return idx[(p, d, 1, 8, 1, BASE)]
        return idx[(p, d, L, n, wb, base)]

    def suite_cpi(d, L, n, wb):
        cyc = sum(get(p, d, L, n, wb)["cycles"] for p in PROGRAMS)
        ins = sum(get(p, d, L, n, wb)["instr"] for p in PROGRAMS)
        return cyc / ins

    data = os.path.join(ROOT, "report", "data")
    write_tex_tables(get, gold, data)
    md = ["# Phase II results (generated by tools/sweep.py, do not edit)", "",
          f"Line size {LINE_WORDS} words. Split design: I-cache and D-cache of N lines each. "
          "Unified design: one cache of 2N lines (same total capacity). "
          "Suite CPI = total cycles / total instructions over all eight programs.", ""]

    # 1. CPI vs latency (N = 8, write buffer on), suite and per program
    with open(os.path.join(data, "cpi_latency.dat"), "w") as f:
        f.write("L ideal mh unified nocache vnideal\n")
        for L in LATENCIES:
            f.write(f"{L} {suite_cpi('ideal', L, 8, 1):.4f} {suite_cpi('mh', L, 8, 1):.4f} "
                    f"{suite_cpi('unified', L, 8, 1):.4f} {suite_cpi('nocache', L, 8, 1):.4f} "
                    f"{suite_cpi('vn_ideal', L, 8, 1):.4f}\n")
    md += ["## Suite CPI vs memory latency (N = 8 lines per split cache, write buffer on)", "",
           "| L | Ideal Harvard | Modified Harvard | Unified cache | No cache | Phase I baseline |",
           "|---|---|---|---|---|---|"]
    for L in LATENCIES:
        md.append(f"| {L} | {suite_cpi('ideal', L, 8, 1):.3f} | {suite_cpi('mh', L, 8, 1):.3f} | "
                  f"{suite_cpi('unified', L, 8, 1):.3f} | {suite_cpi('nocache', L, 8, 1):.3f} | "
                  f"{suite_cpi('vn_ideal', L, 8, 1):.3f} |")
    md.append("")

    # 2. per-program split vs unified at L = 8, N = 8, wbuf on
    L0, N0 = 8, 8
    md += [f"## Split vs unified, L = {L0}, N = {N0} (I {N0} + D {N0} lines vs unified {2 * N0} lines), write buffer on", "",
           "| Program | LS% | Split I-miss | Split D-miss | Split total | Unified fetch miss | Unified data miss | Unified total | Split CPI | Unified CPI | No-cache CPI | Speed-up split/unified |",
           "|---|---|---|---|---|---|---|---|---|---|---|---|"]
    with open(os.path.join(data, "split_unified.dat"), "w") as f:
        f.write("prog mhcpi ucpi ncpi mhmiss umiss\n")
        for p in PROGRAMS:
            m, u, nc = get(p, "mh", L0, N0, 1), get(p, "unified", L0, N0, 1), get(p, "nocache", L0, N0, 1)
            ls = 100.0 * m["dacc"] / m["instr"]
            md.append(f"| {p} | {ls:.1f} | {m['imiss']} | {m['dmiss']} | {m['imiss'] + m['dmiss']} | "
                      f"{u['imiss']} | {u['dmiss']} | {u['imiss'] + u['dmiss']} | {m['cpi']:.3f} | "
                      f"{u['cpi']:.3f} | {nc['cpi']:.3f} | {u['cycles'] / m['cycles']:.2f}x |")
            f.write(f"{p.replace('_', '')} {m['cpi']:.4f} {u['cpi']:.4f} {nc['cpi']:.4f} "
                    f"{m['imiss'] + m['dmiss']} {u['imiss'] + u['dmiss']}\n")
    md.append("")

    # 3. cache size: total misses and CPI vs N (L = 8, wbuf on), per program
    md += ["## Misses vs cache size (L = 8, write buffer on): split total / unified total (unified wins marked *)", "",
           "| Program | " + " | ".join(f"N={n}" for n in LINES) + " |",
           "|---|" + "---|" * len(LINES)]
    for p in PROGRAMS:
        cells = []
        with open(os.path.join(data, f"size_{p.replace('_', '')}.dat"), "w") as f:
            f.write("N split unified splitcpi unifiedcpi\n")
            for n in LINES:
                m, u = get(p, "mh", 8, n, 1), get(p, "unified", 8, n, 1)
                sm, um = m["imiss"] + m["dmiss"], u["imiss"] + u["dmiss"]
                cells.append(f"{sm} / {um}{'*' if um < sm else ''}")
                f.write(f"{n} {sm} {um} {m['cpi']:.4f} {u['cpi']:.4f}\n")
        md.append(f"| {p} | " + " | ".join(cells) + " |")
    md.append("")
    with open(os.path.join(data, "size_suite.dat"), "w") as f:
        f.write("N split unified splitcpi unifiedcpi\n")
        for n in LINES:
            sm = sum(get(p, "mh", 8, n, 1)["imiss"] + get(p, "mh", 8, n, 1)["dmiss"] for p in PROGRAMS)
            um = sum(get(p, "unified", 8, n, 1)["imiss"] + get(p, "unified", 8, n, 1)["dmiss"] for p in PROGRAMS)
            f.write(f"{n} {sm} {um} {suite_cpi('mh', 8, n, 1):.4f} {suite_cpi('unified', 8, n, 1):.4f}\n")

    # 4. write-buffer ablation (L = 8, N = 8)
    md += [f"## Write-buffer ablation, L = {L0}, N = {N0}: cycles without / with the buffer", "",
           "| Program | Stores | Split off | Split on | Split gain | WB stalls | Conflicts | Unified off | Unified on | Unified gain | No-cache off | No-cache on |",
           "|---|---|---|---|---|---|---|---|---|---|---|---|"]
    with open(os.path.join(data, "wbuf.dat"), "w") as f:
        f.write("prog mhoff mhon uoff uon noff non\n")
        for p in PROGRAMS:
            m0, m1 = get(p, "mh", L0, N0, 0), get(p, "mh", L0, N0, 1)
            u0, u1 = get(p, "unified", L0, N0, 0), get(p, "unified", L0, N0, 1)
            n0, n1 = get(p, "nocache", L0, N0, 0), get(p, "nocache", L0, N0, 1)
            md.append(f"| {p} | {gold[p]['stores_ram']} | {m0['cycles']} | {m1['cycles']} | "
                      f"{100 * (m0['cycles'] - m1['cycles']) / m0['cycles']:.1f}% | {m1['wbstall']} | "
                      f"{m1['conflict']} | {u0['cycles']} | {u1['cycles']} | "
                      f"{100 * (u0['cycles'] - u1['cycles']) / u0['cycles']:.1f}% | {n0['cycles']} | {n1['cycles']} |")
            f.write(f"{p.replace('_', '')} {m0['cycles']} {m1['cycles']} {u0['cycles']} {u1['cycles']} "
                    f"{n0['cycles']} {n1['cycles']}\n")
    md.append("")

    # 5. per-program cycle table at L = 8 (for the report's main comparison)
    md += [f"## Cycles per program, L = {L0}, N = {N0}, write buffer on", "",
           "| Program | Instr | Ideal Harvard | Modified Harvard | Unified | No cache | I-stall (mod H) | D-stall (mod H) |",
           "|---|---|---|---|---|---|---|---|"]
    for p in PROGRAMS:
        i_, m, u, nc = (get(p, d, L0, N0, 1) for d in ("ideal", "mh", "unified", "nocache"))
        md.append(f"| {p} | {i_['instr']} | {i_['cycles']} | {m['cycles']} | {u['cycles']} | "
                  f"{nc['cycles']} | {m['istall']} | {m['dstall']} |")
    md.append("")

    # 6. placement sensitivity: data at 0x480 instead of 0x400 (L = 8, wbuf on)
    md += ["## Placement sensitivity: data RAM at physical 0x480 instead of 0x400 (L = 8, write buffer on)", "",
           "Total misses split / unified (unified wins marked *); the split numbers must not change.", "",
           "| Program | " + " | ".join(f"N={n}" for n in LINES) + " |",
           "|---|" + "---|" * len(LINES)]
    for p in PROGRAMS:
        cells = []
        for n in LINES:
            m, u = get(p, "mh", 8, n, 1, SKEW), get(p, "unified", 8, n, 1, SKEW)
            m0 = get(p, "mh", 8, n, 1)
            assert m["imiss"] + m["dmiss"] == m0["imiss"] + m0["dmiss"], (p, n)
            sm, um = m["imiss"] + m["dmiss"], u["imiss"] + u["dmiss"]
            cells.append(f"{sm} / {um}{'*' if um < sm else ''}")
        md.append(f"| {p} | " + " | ".join(cells) + " |")
    md.append("")
    with open(os.path.join(data, "size_skew_suite.dat"), "w") as f:
        f.write("N split unified splitcpi unifiedcpi\n")
        for n in LINES:
            sm = sum(get(p, "mh", 8, n, 1, SKEW)["imiss"] + get(p, "mh", 8, n, 1, SKEW)["dmiss"] for p in PROGRAMS)
            um = sum(get(p, "unified", 8, n, 1, SKEW)["imiss"] + get(p, "unified", 8, n, 1, SKEW)["dmiss"]
                     for p in PROGRAMS)
            cs = sum(get(p, "mh", 8, n, 1, SKEW)["cycles"] for p in PROGRAMS) / sum(gold[p]["instr"] for p in PROGRAMS)
            cu = sum(get(p, "unified", 8, n, 1, SKEW)["cycles"] for p in PROGRAMS) / sum(gold[p]["instr"] for p in PROGRAMS)
            f.write(f"{n} {sm} {um} {cs:.4f} {cu:.4f}\n")
    md += ["Suite CPI at N = 8 with data at 0x480: split "
           f"{sum(get(p, 'mh', 8, 8, 1, SKEW)['cycles'] for p in PROGRAMS) / sum(gold[p]['instr'] for p in PROGRAMS):.3f}, unified "
           f"{sum(get(p, 'unified', 8, 8, 1, SKEW)['cycles'] for p in PROGRAMS) / sum(gold[p]['instr'] for p in PROGRAMS):.3f}.", ""]

    with open(os.path.join(ROOT, "results", "phase2", "summary.md"), "w") as f:
        f.write("\n".join(md) + "\n")


if __name__ == "__main__":
    main()
