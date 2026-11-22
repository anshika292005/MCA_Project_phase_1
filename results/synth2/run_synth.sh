#!/bin/sh
# Phase II synthesis: every design with Yosys synth_xilinx (xc7). Run from the repository root:
#   sh results/synth2/run_synth.sh
# Logs: results/logs/synth2_*.log, cell counts: results/synth2/*_stat.txt,
# summary table: results/synth2/area.md (tools/area_table.py).
set -e
for d in harvard vn mh vnc_unified vnc_nocache cache; do
  echo "synthesizing $d ..."
  yosys -q -l results/logs/synth2_$d.log results/synth2/synth_$d.ys
done
python3 tools/area_table.py > results/synth2/area.md
cat results/synth2/area.md
