#!/bin/sh
# Open-source Fmax measurement (no Vivado needed; works on macOS/Linux).
# Needs yosys and nextpnr-ecp5, e.g. from OSS CAD Suite (https://github.com/YosysHQ/oss-cad-suite-build).
# Target: Lattice ECP5 LFE5U-85F (CABGA381). 100 MHz is only the target to time against;
# --timing-allow-fail keeps nextpnr from treating a miss as an error. The last
# "Max frequency" line of each log is the post-route result.
#
# Run from the repository root:  sh results/fmax/run_fmax.sh            (everything)
#                                sh results/fmax/run_fmax.sh vn_fetch    (one build)
#
# Why the baseline is timed in two builds:
# vn_top has a structural loop  m_addr -> shared_mem -> m_rdata -> instr -> ALU -> m_addr.
# It is never active: instr uses m_rdata only in FETCH_EXEC, m_addr uses the ALU only in MEM.
# nextpnr cannot time a design with loops (with --ignore-loops it cut the loop in the wrong
# place and timed a path through the memory three times: 4.96 MHz, not a real number).
# So we time two copies, each with one leg of the loop removed:
#   vn_fetch : m_addr = pc, m_re = ~halted -> every real FETCH_EXEC path
#              (m_re also forms a loop: m_rdata -> control -> mem_re -> m_re -> m_rdata gate)
#   vn_mem   : instr  = ir        -> contains every real MEM path
# Every real path is in at least one copy; only the impossible path (through both legs)
# is in neither. Baseline Fmax = min(vn_fetch, vn_mem). The RTL in rtl/ is not changed;
# the copies are written to results/fmax/build/ (git-ignored).
set -e
B=results/fmax/build
mkdir -p $B
sed -e 's/assign m_addr    = (state == MEM) ? alu_y : pc;/assign m_addr = pc;  \/\/ TIMING COPY: fetch leg only/' \
    -e 's/assign m_re      = (state == MEM) ? mem_re : ~halted;/assign m_re = ~halted;  \/\/ TIMING COPY: fetch leg only/' \
  rtl/baseline/cpu_core_vn.v > $B/cpu_core_vn_fetch.v
sed 's/wire \[31:0\] instr = (state == MEM) ? ir : m_rdata;/wire [31:0] instr = ir;  \/\/ TIMING COPY: MEM leg only/' \
  rtl/baseline/cpu_core_vn.v > $B/cpu_core_vn_mem.v
[ $(grep -c "TIMING COPY" $B/cpu_core_vn_fetch.v) = 2 ] && grep -q "TIMING COPY" $B/cpu_core_vn_mem.v || {
  echo "cpu_core_vn.v changed: update the sed patterns in run_fmax.sh"; exit 1; }

TOPS=${*:-"harvard vn_fetch vn_mem"}
for top in $TOPS; do
  case $top in
    harvard) ys=results/fmax/fmax_harvard.ys ;;
    vn_*)    sed "s#rtl/baseline/cpu_core_vn.v#$B/cpu_core_vn_${top#vn_}.v#; s#results/fmax/vn_ecp5#$B/${top}_ecp5#g" \
               results/fmax/fmax_vn.ys > $B/fmax_${top}.ys; ys=$B/fmax_${top}.ys ;;
  esac
  yosys -q -l results/logs/fmax_${top}_synth.log $ys
  json=results/fmax/harvard_ecp5.json; [ $top != harvard ] && json=$B/${top}_ecp5.json
  nextpnr-ecp5 --85k --package CABGA381 --json $json \
    --lpf-allow-unconstrained --freq 100 --seed 1 --timing-allow-fail \
    -l results/logs/fmax_${top}_pnr.log
done
for top in harvard vn_fetch vn_mem; do
  [ -f results/logs/fmax_${top}_pnr.log ] && \
    echo "$top: $(grep 'Max frequency' results/logs/fmax_${top}_pnr.log | tail -1 | sed 's/.*: //')"
done
