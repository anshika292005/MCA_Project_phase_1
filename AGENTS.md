# Project context (read this before doing anything)

You are helping one member of a 5-person B.Tech team build **Project 9: Instruction and Data Memory Hierarchy** for a Modern Computer Architecture course. The team is implementing a simplified Harvard-style memory organisation in Verilog (separate instruction and data memories), driving it with a tiny single-cycle RV32I-subset processor, and comparing it against a shared-memory (Von Neumann) baseline. Phase I is graded on an IEEE-format report, a 5-minute prototype video, and a GitHub repository whose commit history shows each member's contribution.

Five people are working in parallel in separate branches, each with their own AI-assisted IDE session. Their code only integrates if everyone follows the same contract, so **the interfaces, names, and memory map below are fixed**. If something in this spec looks wrong or blocks you, stop and tell the user so they can raise it with the team; do not quietly change a port name, width, or address. Inside your own modules you are free to choose the implementation.

The person you are working with has to explain this code in a live demo and will be assessed on it. Keep the code small and readable, comment the non-obvious parts, and when you finish a piece, explain in plain words how it works.

## What the project must show

1. Independent instruction and data paths (Harvard): an instruction fetch and a data access happen in the same clock cycle.
2. Address decoding and read/write control on the data side.
3. Programs running that mix instruction fetches with data accesses.
4. A measured comparison against a shared-memory organisation where fetch and data access compete for one memory port.

Headline metric: **cycles and CPI for the same program on both designs**, plus the number of cycles in which Harvard performs a fetch and a data access simultaneously.

## Coding rules

- Verilog-2001 only (no SystemVerilog), synthesizable RTL in `rtl/`, testbench-only constructs in `tb/`.
- Every file starts with `` `default_nettype none `` and ends with `` `default_nettype wire ``.
- One module per file, file name = module name.
- Single clock `clk`, rising edge. Reset `rst` is synchronous and active high.
- Non-blocking assignments in clocked blocks, blocking in combinational blocks, no latches.
- 32-bit data and addresses. Addresses are byte addresses; memories are word-addressed internally using `addr[N:2]`. Only aligned word accesses are supported.
- Simulator: Icarus Verilog (`iverilog -g2005`) with GTKWave. Keep code portable so it also runs in Vivado or ModelSim.

## Repository layout

```
README.md
AGENTS.md                 this file
docs/                     workflow doc, diagrams
rtl/mem/                  instr_mem.v data_mem.v addr_decoder.v rw_ctrl.v harvard_mem.v      (Member 1)
rtl/core/                 pc_reg.v regfile.v alu.v imm_gen.v control.v cpu_core.v           (Member 2)
rtl/harvard_top.v                                                                           (Member 2)
rtl/common/perf_counters.v                                                                  (Member 3)
rtl/baseline/             shared_mem.v cpu_core_vn.v vn_top.v                               (Member 3)
tb/                       all testbenches                                                   (Member 4)
programs/                 *.s assembly, *.hex machine code, *_data.hex data images          (Member 4)
tools/asm.py              tiny assembler for the subset                                     (Member 4)
sim/Makefile              build and run targets                                             (Member 4)
results/                  logs, waveform screenshots, comparison table                      (Members 3, 4)
report/                   IEEEtran LaTeX source, figures, PDF                               (Member 5)
video/                    script.md and the video link                                      (Member 5)
```

Only edit files in the folders owned by the member you are helping. If a change is needed elsewhere, describe it so the user can ask the owner.

## Instruction subset (RV32I encodings)

| Instr | Opcode | funct3 | funct7 | Operation |
|---|---|---|---|---|
| ADD | 0110011 | 000 | 0000000 | rd = rs1 + rs2 |
| SUB | 0110011 | 000 | 0100000 | rd = rs1 - rs2 |
| AND | 0110011 | 111 | 0000000 | rd = rs1 & rs2 |
| OR | 0110011 | 110 | 0000000 | rd = rs1 \| rs2 |
| ADDI | 0010011 | 000 | - | rd = rs1 + imm |
| LW | 0000011 | 010 | - | rd = MEM[rs1 + imm] |
| SW | 0100011 | 010 | - | MEM[rs1 + imm] = rs2 |
| BEQ | 1100011 | 000 | - | if rs1 == rs2, PC += imm |
| BNE | 1100011 | 001 | - | if rs1 != rs2, PC += imm |
| EBREAK | `32'h00100073` | | | halt: PC stops, `halt` goes high and stays high |

Register x0 always reads zero. PC resets to 0. Any other encoding is treated as a NOP.

## Memory map

Instruction address space (Harvard): 256 words, byte addresses `0x000`–`0x3FF`, read-only, loaded from a hex file.

Data address space (what programs see, identical on both designs):

| Byte address | Region |
|---|---|
| `0x0000_0000`–`0x0000_03FF` | Data RAM, 256 words |
| `0x0000_0400` | `out_port` register, write-only, reads as 0 |
| anything else | invalid: write ignored, read returns 0, `d_fault` = 1 |

Shared-memory baseline: one 512-word memory. Code occupies physical words 0–255, data occupies physical words 256–511. `vn_top` adds `0x400` to data-space RAM addresses, so **the same program and data hex files run unmodified on both designs**. `out_port` decoding happens before that translation.

## Module interfaces (fixed)

```verilog
// ---------- Member 1: rtl/mem ----------
module instr_mem #(parameter DEPTH_WORDS = 256, parameter INIT_FILE = "")
  (input  wire [31:0] addr, output wire [31:0] rdata);          // combinational read, array name: mem

module data_mem #(parameter DEPTH_WORDS = 256, parameter INIT_FILE = "")
  (input  wire clk, input wire we,
   input  wire [31:0] addr, input wire [31:0] wdata,
   output wire [31:0] rdata);                                    // sync write, combinational read, array name: mem

module addr_decoder
  (input  wire [31:0] addr,
   output wire sel_ram, output wire sel_io, output wire addr_fault);

module rw_ctrl
  (input  wire d_we, input wire d_re, input wire sel_ram, input wire sel_io,
   input  wire [31:0] ram_rdata,
   output wire ram_we, output wire io_we, output wire [31:0] d_rdata);

module harvard_mem #(parameter PROG_FILE = "", parameter DATA_FILE = "")
  (input  wire clk, input wire rst,
   input  wire [31:0] i_addr,  output wire [31:0] i_rdata,       // instruction port
   input  wire [31:0] d_addr,  input  wire [31:0] d_wdata,       // data port
   input  wire d_we, input wire d_re,
   output wire [31:0] d_rdata, output wire d_fault,
   output reg  [31:0] out_port);
   // instances: u_imem (instr_mem), u_dmem (data_mem), u_dec (addr_decoder), u_rw (rw_ctrl)

// ---------- Member 2: rtl/core ----------
module regfile (input wire clk, input wire we,
   input wire [4:0] ra1, input wire [4:0] ra2, input wire [4:0] wa, input wire [31:0] wd,
   output wire [31:0] rd1, output wire [31:0] rd2);              // array name: regs, x0 reads 0

module alu (input wire [31:0] a, input wire [31:0] b, input wire [2:0] op,
   output reg [31:0] y, output wire zero);                       // op: 000 ADD, 001 SUB, 010 AND, 011 OR

module imm_gen (input wire [31:0] instr, output reg [31:0] imm);

module control (input wire [31:0] instr,
   output reg reg_we, output reg alu_src, output reg [2:0] alu_op,
   output reg mem_re, output reg mem_we, output reg mem_to_reg,
   output reg is_beq, output reg is_bne, output reg is_halt);

module cpu_core
  (input  wire clk, input wire rst,
   output wire [31:0] i_addr, input  wire [31:0] i_rdata,
   output wire [31:0] d_addr, output wire [31:0] d_wdata,
   output wire d_we, output wire d_re, input wire [31:0] d_rdata,
   output wire halt, output wire instr_done);
   // single cycle; instr_done = 1 in every cycle an instruction retires; instance: u_regfile

module harvard_top #(parameter PROG_FILE = "", parameter DATA_FILE = "")
  (input  wire clk, input wire rst,
   output wire halt, output wire [31:0] out_port,
   output wire [31:0] cycle_count, output wire [31:0] instr_count,
   output wire [31:0] d_access_count, output wire [31:0] simul_count);
   // instances: u_core (cpu_core), u_mem (harvard_mem), u_perf (perf_counters)

// ---------- Member 3: rtl/common, rtl/baseline ----------
module perf_counters
  (input  wire clk, input wire rst, input wire halt,
   input  wire instr_done, input wire i_access, input wire d_access,
   output reg [31:0] cycle_count, output reg [31:0] instr_count,
   output reg [31:0] d_access_count, output reg [31:0] simul_count);
   // all counters freeze once halt is high; simul_count counts cycles with i_access && d_access

module shared_mem #(parameter DEPTH_WORDS = 512, parameter PROG_FILE = "", parameter DATA_FILE = "")
  (input  wire clk, input wire we,
   input  wire [31:0] addr, input wire [31:0] wdata,
   output wire [31:0] rdata);                                    // ONE port; program at word 0, data at word 256

module cpu_core_vn
  (input  wire clk, input wire rst,
   output wire [31:0] m_addr, output wire [31:0] m_wdata,
   output wire m_we, output wire m_re, output wire m_is_data,    // m_is_data = 1 when the access is a data access
   input  wire [31:0] m_rdata,
   output wire halt, output wire instr_done);
   // reuses regfile, alu, imm_gen, control; instance: u_regfile

module vn_top #(parameter PROG_FILE = "", parameter DATA_FILE = "")
  ( /* exactly the same port list as harvard_top */ );
   // instances: u_core (cpu_core_vn), u_mem (shared_mem), u_perf (perf_counters)
```

Testbenches read state through these hierarchical names, so keep them: `dut.u_core.u_regfile.regs[n]`, `dut.u_mem.u_dmem.mem[n]` (Harvard), `dut.u_mem.mem[256 + n]` (baseline).

## Expected timing behaviour

- **Harvard:** every instruction takes 1 cycle, including LW and SW, because fetch and data access use different memories. CPI = 1.0.
- **Baseline:** one memory port, so a fetch and a data access cannot share a cycle. Non-memory instructions take 1 cycle (fetch and execute), LW and SW take 2 (fetch, then data access). CPI = 1 + (fraction of LW/SW instructions).
- Cross-check used by the testbench: baseline cycles should equal Harvard cycles plus Harvard `d_access_count`, and final register and data-memory contents must be identical on both designs.

## Git rules

Graders read the commit history to judge individual contribution.

- Work on your own branch (`m1-memory`, `m2-core`, `m3-baseline`, `m4-verification`, `m5-report`) and merge to `main` through pull requests.
- Commit from your own GitHub account, in small steps, one logical change per commit, with messages like `mem: add addr_decoder with fault flag`.
- Never commit simulator output (`*.vcd`, `*.vvp`, `sim/build/`). Do commit logs and screenshots placed in `results/`.
- Do not write commit messages for the user that claim work they did not do, and do not commit on behalf of another member.

## How to work with the user

- Before writing code, restate in 3–4 lines what you are about to build and which files you will create.
- Build one module at a time, compile it with `iverilog` straight away, and fix warnings before moving on.
- After each module, give a short plain-language explanation the user could repeat in a viva, and suggest the commit message.
- When you report results, report what the simulation actually printed. If something fails or is not yet tested, say so.
