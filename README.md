# Project 9: Instruction and Data Memory Hierarchy

**Modern Computer Architecture, Phase I.** A Harvard-style memory organisation in Verilog (separate
instruction and data memories), driven by a small single-cycle RV32I-subset processor and compared
against a shared-memory (Von Neumann) baseline.

With separate memories, the processor fetches the next instruction and performs a load or store in
the **same clock cycle**, so every instruction takes one cycle (CPI = 1.00). In the baseline, code
and data share one memory port, so each load or store costs an extra cycle
(CPI = 1 + load/store fraction). We run the same programs on both and measure the difference.

## Team

| Member | Name / GitHub | Role | Owns |
|---|---|---|---|
| Member 1 | Yashpal (`@Yashpal-2004`) | Harvard memory core | `rtl/mem/` |
| Member 2 | Anshika (`@anshika292005`) | Processor and top-level integration | `rtl/core/`, `rtl/harvard_top.v` |
| Member 3 | Ankit (`@Ankit35027`) | Shared-memory baseline and metrics | `rtl/common/`, `rtl/baseline/`, `results/comparison.md` |
| Member 4 | Samriddhi (`@samriddhi-techy`) | Verification and programs | `tb/`, `programs/`, `tools/`, `sim/` |
| Member 5 | Ayush | Report, video, repository lead | `report/`, `video/`, `README.md` |

## Block diagram

```
                Harvard (harvard_top)                          Baseline (vn_top)

             +-----------+   i_addr   +-----------+         +-------------+  m_addr  +------------+
             |           |----------->| instr_mem |         |             |--------->|            |
             |           |<-----------|  (ROM)    |         | cpu_core_vn |<---------| shared_mem |
             | cpu_core  |   i_rdata  +-----------+         | FETCH_EXEC/ | m_rdata  | code 0-255 |
             | (single   |                                  |    MEM FSM  |--------->| data 256-  |
             |  cycle)   |   d_addr   +-----------+         +-------------+  m_we    |       511  |
             |           |----------->| decoder + |                ^                 +------------+
             |           |<-----------| rw_ctrl + |--> out_port    |  one port: fetch OR data
             +-----------+   d_rdata  | data_mem  |                   access, never both
                   |                  +-----------+
                   v
             perf_counters (cycles, instructions, data accesses, simultaneous cycles)
```

Detailed figures (block diagram, datapath, FSM, waveform) are in the report, `report/main.pdf`.

## Memory map (data side, identical on both designs)

| Byte address | Region |
|---|---|
| `0x000`-`0x3FF` | Data RAM, 256 words |
| `0x400` | `out_port` register (write-only, reads 0) |
| anything else | invalid: write ignored, read returns 0, `d_fault` = 1 |

Instructions live in a separate 256-word ROM (Harvard) or in words 0-255 of the shared memory
(baseline, where data occupies words 256-511).

## Running the simulation

Requirements: Icarus Verilog (`iverilog`, `vvp`), Python 3, and a waveform viewer: GTKWave, or
[Surfer](https://surfer-project.org/) on macOS (`brew install surfer`; Homebrew no longer ships GTKWave).

```sh
cd sim
make asm       # assemble programs/*.s -> *.hex (and run the assembler self-test)
make unit      # unit tests: addr_decoder, instr_mem, data_mem, harvard_mem
make harvard   # every program on the Harvard system
make vn        # every program on the shared-memory baseline
make compare   # both designs side by side, prints the comparison table
make waves PROG=memcopy   # open the comparison waveform (GTKWave, or Surfer if no GTKWave)
make figure    # regenerate the report's waveform figure from the simulation
```

The report compiles with pdfLaTeX + BibTeX (Overleaf, TeX Live, MiKTeX), or locally with
`cd report && tectonic main.tex`. Both produce Times text, as IEEE requires. All figures are TikZ sources in `report/figures/`.

Every testbench is self-checking and ends with `PASS` or `FAIL (n errors)`. Logs are written to
`results/logs/`.

## Repository layout

```
rtl/mem/        instr_mem, data_mem, addr_decoder, rw_ctrl, harvard_mem
rtl/core/       pc_reg, regfile, alu, imm_gen, control, cpu_core
rtl/harvard_top.v
rtl/common/     perf_counters
rtl/baseline/   shared_mem, cpu_core_vn, vn_top
tb/             unit, system and comparison testbenches
programs/       basic, array_sum, memcopy, count_loop (.s, .hex, _data.hex)
tools/asm.py    assembler for the instruction subset
sim/Makefile    build and run targets
results/        comparison table, simulation and synthesis logs, GTKWave screenshots (results/waves/)
results/fmax/   ECP5 place-and-route Fmax scripts (run_fmax.sh)
report/         IEEE-format report (LaTeX source, TikZ figures, PDF)
video/          video script and link
```

## Results

Measured by `make compare`; full table and discussion in [results/comparison.md](results/comparison.md).

| Program | LW/SW % | Harvard CPI | Baseline CPI | Speed-up |
|---|---|---|---|---|
| basic      | 36.8% | 1.00 | 1.37 | 1.37x |
| array_sum  | 26.3% | 1.00 | 1.26 | 1.26x |
| memcopy    | 31.5% | 1.00 | 1.31 | 1.31x |
| count_loop |  1.6% | 1.00 | 1.02 | 1.02x |

Maximum clock frequency after place and route (Lattice ECP5, Yosys + nextpnr, `sh results/fmax/run_fmax.sh`):
**Harvard 43.62 MHz, baseline 37.36 MHz**, so in execution time (cycles / Fmax) the Harvard
design is 1.19x-1.60x faster. Details and method in [results/comparison.md](results/comparison.md).

### Waveforms (GTKWave)

Run `make waves PROG=memcopy` in `sim/` for an interactive view.

- `memcopy` on both designs, 0-190 ns (`gtkwave build/tb_compare_memcopy.vcd waves.gtkw` in `sim/`):
  Harvard raises `d_re`/`d_we` in the same cycle as the fetch; the baseline spends an extra cycle
  with `state`/`m_is_data` = 1 for every LW/SW.

  ![GTKWave: memcopy, Harvard vs baseline](results/waves/gtkwave_memcopy_first_load.png)

- Data-side memory control on Harvard, `basic`, 65-185 ns (`gtkwave build/tb_harvard_top_basic.vcd memctrl.gtkw`):
  SW/LW to RAM (`sel_ram`, `ram_we`); SW and LW to the invalid address `0x808` raise
  `addr_fault` and `d_fault` while `ram_we` stays 0 and the load returns 0; SW to `0x400`
  selects `out_port` (`sel_io`, `io_we`).

  ![GTKWave: address decoding and fault detection](results/waves/gtkwave_basic_memctrl.png)

## Report and video

- Report PDF: [report/main.pdf](report/main.pdf)
- Prototype Video: [Google Drive Folder](https://drive.google.com/drive/folders/1gFUfU14wTAQAbcvC8pDPiQS0-IFScr1h?usp=drive_link)



