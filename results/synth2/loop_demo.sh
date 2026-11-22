#!/bin/sh
# Demonstrates the two Phase II timing rules on copies of the RTL (rtl/ is not changed).
# Run from the repository root:  sh results/synth2/loop_demo.sh
#   fwd  : the caches forward refill data straight to the core (miss completes in the
#          L-th cycle instead of the next one)
#   halt : the I-cache request is ~halt (decoded from the fetched instruction)
#          instead of ~halted (a register)
# Each copy of mh_top is synthesized with the same script as the real design and the
# number of "found logic loop" warnings is printed. The real design has 0.
set -e
B=results/synth2/build
mkdir -p $B
sed -e 's/wire ready_rd = (ENABLE != 0) ? hit : (rd_mem \& mem_ready);/wire ready_rd = (ENABLE != 0) ? (hit | (rd_mem \& mem_ready)) : (rd_mem \& mem_ready);  \/\/ LOOP DEMO/' \
    -e 's/assign rdata = (ENABLE != 0) ? hit_word : mem_word;/assign rdata = (ENABLE != 0) ? (hit ? hit_word : mem_word) : mem_word;  \/\/ LOOP DEMO/' \
    rtl/mem/cache.v > $B/cache_fwd.v
sed 's/assign i_req  = ~halted;/assign i_req  = ~halt;  \/\/ LOOP DEMO/' rtl/core/cpu_core.v > $B/cpu_core_halt.v
[ $(grep -c "LOOP DEMO" $B/cache_fwd.v) = 2 ] && grep -q "LOOP DEMO" $B/cpu_core_halt.v || {
  echo "RTL changed: update the sed patterns in loop_demo.sh"; exit 1; }
sed "s#rtl/mem/cache.v#$B/cache_fwd.v#; s#results/synth2/mh_stat.txt#$B/mh_fwd_stat.txt#" \
    results/synth2/synth_mh.ys > $B/synth_mh_fwd.ys
sed "s#rtl/core/cpu_core.v#$B/cpu_core_halt.v#; s#results/synth2/mh_stat.txt#$B/mh_halt_stat.txt#" \
    results/synth2/synth_mh.ys > $B/synth_mh_halt.ys
for v in fwd halt; do
  yosys -q -l results/logs/synth2_loopdemo_$v.log $B/synth_mh_$v.ys >/dev/null 2>&1 || true
done
echo "logic-loop warnings: real mh_top $(grep -c 'found logic loop' results/logs/synth2_mh.log || true)," \
     "forwarding copy $(grep -c 'found logic loop' results/logs/synth2_loopdemo_fwd.log || true)," \
     "i_req = ~halt copy $(grep -c 'found logic loop' results/logs/synth2_loopdemo_halt.log || true)"
