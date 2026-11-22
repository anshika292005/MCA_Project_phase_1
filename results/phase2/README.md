# Phase II results: memory hierarchy

Everything in this folder is generated. Do not edit the numbers by hand; re-run the scripts.

| File | Produced by | Contents |
|---|---|---|
| `sweep.csv` | `tools/sweep.py` (`make sweep` in `sim/`) | one row per program × design × latency × lines × write buffer × data placement (2640 rows) |
| `summary.md` | `tools/sweep.py` | the tables used in the report (CPI vs latency, split vs unified, cache size, write buffer, placement) |
| `../synth2/area.md` | `tools/area_table.py` (`sh results/synth2/run_synth.sh`) | Yosys area of every Phase II design |
| `../logs/sweep.log` | `tools/sweep.py` | number of runs and golden-model checks, and every mismatch (none) |
| `../logs/system.log`, `cache.log`, `mutate.log`, `iss_selftest.log` | `make system`, `make cache`, `make mutate`, `make iss` | regression logs |
| `../logs/synth2_*.log` | `results/synth2/*.ys` | Yosys logs, including the loop-demonstration copies |

## Designs

| Name in the CSV | RTL | Description |
|---|---|---|
| `ideal` | `harvard_top` | Phase I Harvard system, ideal memories (reference) |
| `vn_ideal` | `vn_top` | Phase I single-port baseline, ideal memory |
| `mh` | `mh_top` | modified Harvard: I-cache N lines + D-cache N lines + arbiter + `main_mem` |
| `unified` | `vnc_top`, `CACHE_EN=1` | single bus + unified cache of 2N lines (same total capacity) |
| `nocache` | `vnc_top`, `CACHE_EN=0` | single bus, every access to `main_mem` |

All caches have 4-word lines and are direct-mapped, write-through and no-write-allocate. `base` is
the physical address of data word 0: 0x400 normally, 0x480 in the placement experiment.

## Headline numbers (N = 8, L = 8, write buffer on, all eight programs)

| | Suite CPI |
|---|---|
| ideal Harvard | 1.000 |
| Phase I baseline (ideal single port) | 1.238 |
| modified Harvard | 1.685 |
| unified cache | 2.717 (1.874 with data at 0x480) |
| no cache | 9.875 |

* The split design wins on 7 of 8 programs. The two causes are the single port (CPI ≥ 1 + f_LS)
  and code/data conflict misses: with code at 0x000 and data at 0x400, every unified size up to
  1 KB maps code word k and data word k to the same line.
* The unified cache wins on `subroutine` (59-word code, larger than an 8-line I-cache) and, over
  the whole suite, when each split cache has only one line.
* The write buffer removes 15.1% of the split design's cycles and 10.1% of the unified design's.
  It cannot help without a cache.
* With L = 1 the no-cache system equals the Phase I baseline cycle for cycle (`tb_system`
  checks every cycle).

## Synthesis notes (Yosys 0.71, `synth_xilinx -family xc7`)

* `main_mem` is a black box in all cached designs: it stands for block RAM or off-chip memory
  and is identical in every design. The ideal Harvard number adds the separately synthesised
  256-word ROM (`results/synth/rom_stat.txt`), as in Phase I.
* **Logic loops.** `mh_top`: none. `vnc_top` (both modes) and `vn_top`: the Phase I false loop
  `m_addr → cache/memory → m_rdata / m_ready → instruction mux → ALU → m_addr`. It can never be
  active, because in FETCH_EXEC the bus address is the PC, and in MEM the instruction is the
  latched `ir`.
* `results/synth2/loop_demo.sh` synthesises two broken copies of `mh_top` (the RTL is not
  changed). Forwarding refill data to the core gives 92 loop warnings, through the arbiter's
  address multiplexer. Driving the I-cache request from `~halt` instead of `~halted` gives 1,
  through the EBREAK decoder and the cache's ready output.
* Not measured: Fmax (nextpnr was not available for Phase II, and Yosys has no 7-series timing
  model) and post-route utilisation.
