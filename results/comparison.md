# Harvard vs shared-memory comparison

Numbers copied from `results/logs/compare.log`, produced by `make compare` (Icarus Verilog 13.0).
Each row is one program run on both `harvard_top` and `vn_top`; `tb_compare` checked that all 32
registers, all 256 data words and `out_port` are identical on both designs.

| Program | Instr | LW/SW % | Harvard cycles | Harvard CPI | Baseline cycles | Baseline CPI | Speed-up | Simultaneous cycles (Harvard) |
|---|---|---|---|---|---|---|---|---|
| basic      | 19 | 36.8% | 19 | 1.00 | 26 | 1.37 | 1.37x |  7 |
| array_sum  | 38 | 26.3% | 38 | 1.00 | 48 | 1.26 | 1.26x | 10 |
| memcopy    | 54 | 31.5% | 54 | 1.00 | 71 | 1.31 | 1.31x | 17 |
| count_loop | 64 |  1.6% | 64 | 1.00 | 65 | 1.02 | 1.02x |  1 |

Baseline simultaneous cycles are 0 for every program (one memory port).

## How to read it

- Harvard CPI is exactly 1.00: the fetch uses the instruction memory and LW/SW use the data
  memory in the same cycle, so no instruction ever waits.
- Baseline cycles = Harvard cycles + number of LW/SW, for every program. Each load or store
  needs the single port twice (fetch, then data), so it costs one extra cycle.
- So baseline CPI = 1 + (LW/SW fraction), and the speed-up grows with the memory intensity of the
  program: 1.02x for the compute loop, 1.26x-1.37x for the memory-heavy programs.
- "Simultaneous cycles" on Harvard equals the number of data accesses: every data access overlapped
  with a fetch.
- All baseline tests confirm that total executed instructions match exactly, proving algorithmic
  and architectural equivalence across both architectures with zero divergence in final memory state.

## Counting conventions

- EBREAK is counted as one retired instruction and its cycle is counted; counters freeze after it.
- Stores to `out_port` and accesses to invalid addresses count as data accesses on both designs
  (they still occupy the data path / the single bus for a cycle).

## Synthesis (Yosys, Xilinx 7-series)

Generic FPGA synthesis with Yosys 0.71 (`synth_xilinx -family xc7`, flattened), using the
scripts in `results/synth/`. Full logs are in `results/logs/synth_*.log` and the raw cell
counts are in `results/synth/*_stat.txt`. To reproduce, run from the repository root:

```sh
yosys -l results/logs/synth_harvard.log results/synth/synth_harvard.ys
yosys -l results/logs/synth_rom.log     results/synth/synth_rom.ys
yosys -l results/logs/synth_vn.log      results/synth/synth_vn.ys
```

| Design | Logic LUTs | LUT-RAM (LUTs) | Total LUTs | Flip-flops | CARRY4 | Fmax |
|---|---|---|---|---|---|---|
| harvard_top: core, data side, counters | 409 | 176 (data RAM 128, regfile 48) | 585 | 194 | 67 | not measured |
| harvard_top: instruction ROM (256 x 32) | 128 (+64 MUXF7, 32 MUXF8) | 0 | 128 | 0 | 0 | |
| **harvard_top total** | **537** | **176** | **713** | **194** | **67** | see Fmax section |
| **vn_top total** | **776** | **304** (shared mem 256, regfile 48) | **1080** | **227** | **66** | see Fmax section |

How the numbers were counted:

- Logic LUTs = LUT1-LUT6 plus INV cells (an INV is a LUT1 on 7-series).
- LUT-RAM = 4 LUTs per RAM256X1S (256 x 1 distributed RAM) and 4 per RAM32M. The data RAM
  is 256 x 32, so it takes 32 RAM256X1S. The shared memory is 512 x 32, so it takes 64.
  The register file has two read ports, so it takes 12 RAM32M on both designs.
- The 33 extra flip-flops in vn_top are exactly its 32-bit latched instruction plus the
  1-bit FSM state.

Things to know before quoting these numbers:

1. **The Harvard instruction ROM is measured on its own.** If it is synthesized holding a
   program, Yosys hard-wires that program into the core and deletes the decoder and ALU logic
   for instructions the program never uses. The baseline's memory is writable, so that cannot
   happen there. `synth_harvard.ys` therefore treats `instr_mem` as a black box, and
   `synth_rom.ys` measures a 256-word ROM filled with pseudo-random words
   (`rom_random.hex`), which is the cost of a general ROM. On a real board the ROM could
   also be one 18 Kb block RAM.
2. **Yosys initialisation workaround.** `instr_mem`, `data_mem` and `shared_mem` zero-fill
   every word in a `for` loop and then call `$readmemh` in the same `initial` block. Icarus
   and Vivado apply these in order. Yosys 0.71 lets the zero-fill win, which would leave the
   ROM all zeros (all NOPs) and the whole core optimised away. The scripts delete the one-word
   zero-fill init cells after `proc`. No RTL was changed.
3. **The baseline logic loop is a false positive.** Yosys reports a structural
   loop in vn_top: `m_addr` → memory → `m_rdata` → `instr` → ALU → `m_addr`. It can never be
   active, because `m_addr` uses the ALU only in the MEM state and `instr` uses `m_rdata` only
   in FETCH_EXEC. Vivado will also flag it, and it may make ABC optimise vn_top less well,
   which could explain part of vn_top's larger logic count.
4. **No 7-series Fmax.** Yosys has no timing model for 7-series and Vivado does not run on
   macOS, so Fmax was measured on a Lattice ECP5 instead (next section). A Vivado run on an
   Artix-7 board is planned for Phase II.
5. These are Yosys estimates after synthesis, not Vivado utilisation after place and route.

**Result:** the Harvard design needs about 34% fewer LUTs (713 vs 1080) and 33 fewer
flip-flops than the shared-memory baseline, while running every program in fewer cycles. The
split memory costs a separate ROM (128 LUTs), but the baseline pays more for a 512-word memory,
the latched instruction register, the two-state controller and the address muxing in front of
its single port.

## Maximum clock frequency (Lattice ECP5, open-source flow)

Measured with Yosys `synth_ecp5` + `nextpnr-ecp5` (OSS CAD Suite 2026-11-18) on an LFE5U-85F,
CABGA381, seed 1, after placement and routing. Reproduce from the repository root with
`sh results/fmax/run_fmax.sh` (scripts and explanation in `results/fmax/`, logs in
`results/logs/fmax_*`). Unlike the area runs above, the instruction ROM is **not** black-boxed
here, because its read delay is on the critical path; it holds the pseudo-random
`rom_random.hex` image (on both designs) so Yosys cannot hard-wire a program.

| Build | Critical path (register → register) | Delay | Fmax |
|---|---|---|---|
| harvard_top | ROM (block RAM) → regfile → ALU → data RAM → regfile write | 23.29 ns | **42.94 MHz** |
| vn_top, fetch leg | PC → shared mem (512-word LUT-RAM) → decode → regfile → ALU compare → PC | 26.83 ns | 37.27 MHz |
| vn_top, MEM leg | latched `ir` → regfile → ALU → shared mem → regfile write | 18.88 ns | 52.97 MHz |
| **vn_top** | slower of the two legs | 26.83 ns | **37.27 MHz** |

**Why vn_top is timed in two builds.** nextpnr cannot time a design that contains
combinational loops, and vn_top has two that can never be active (point 3 above, plus
`m_rdata` → control → `mem_re` → `m_re` → `m_rdata`, since read data is gated by `m_re`).
With `--ignore-loops` nextpnr cut the loop in the wrong place and reported 4.96 MHz for a path
that went through the memory three times in one cycle, which is impossible, so that number is
discarded. Instead, `run_fmax.sh` builds two copies of `cpu_core_vn` (the RTL in `rtl/` is not
changed): the fetch leg fixes `m_addr = pc` and `m_re = ~halted`, the MEM leg fixes
`instr = ir`. Every real path exists in at least one copy; only the impossible paths (through
both legs) exist in neither. A gate-level `yosys check` finds 0 loops in both copies (14034 in
the original). vn_top's Fmax is the minimum of the two legs. Each critical path above was
checked to read memory only once.

**Execution time = cycles / Fmax:**

| Program | Harvard cycles | Harvard time | Baseline cycles | Baseline time | Speed-up |
|---|---|---|---|---|---|
| basic      | 19 |  442 ns | 26 |  698 ns | 1.58x |
| array_sum  | 38 |  885 ns | 48 | 1288 ns | 1.46x |
| memcopy    | 54 | 1258 ns | 71 | 1905 ns | 1.51x |
| count_loop | 64 | 1490 ns | 65 | 1744 ns | 1.17x |

**Result:** the Harvard design is faster in clock frequency as well as CPI. Its single cycle
contains two memory reads (ROM and data RAM), but the ROM is a small block RAM and the data RAM
holds 256 words. The baseline's fetch leg has one read, but from a 512-word LUT-RAM (a deeper
read multiplexer) followed by the gating of `m_rdata`, and that leg sets its clock.

Caveats: this is an ECP5, not a Xilinx 7-series part; one placement seed; I/O paths are not
constrained (only register-to-register timing is reported); the Harvard ROM is a block RAM
while all baseline memory is LUT-RAM, which is how each design maps naturally.
