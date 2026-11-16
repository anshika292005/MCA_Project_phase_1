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
| **harvard_top total** | **537** | **176** | **713** | **194** | **67** | not measured |
| **vn_top total** | **776** | **304** (shared mem 256, regfile 48) | **1080** | **227** | **66** | not measured |

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
4. **Fmax is not measured.** Yosys has no timing model for 7-series. Getting Fmax needs
   Vivado: synthesize and implement both tops, with a false path on the loop above, then read
   the timing summary.
5. These are Yosys estimates after synthesis, not Vivado utilisation after place and route.

**Result:** the Harvard design needs about 34% fewer LUTs (713 vs 1080) and 33 fewer
flip-flops than the shared-memory baseline, while running every program in fewer cycles. The
split memory costs a separate ROM (128 LUTs), but the baseline pays more for a 512-word memory,
the latched instruction register, the two-state controller and the address muxing in front of
its single port.
