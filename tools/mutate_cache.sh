#!/bin/sh
# Shows that tb_cache can fail: runs it against three deliberately broken copies of the
# cache / memory RTL (rtl/ is not changed) and expects every copy to FAIL.
#   m1 : read miss does not wait for the write buffer (read-after-write hazard)
#   m2 : a store miss writes into the resident line (breaks no-write-allocate)
#   m3 : memory answers one cycle late (miss penalty L+1 instead of L)
# Run from sim/:  sh ../tools/mutate_cache.sh      (or: make mutate)
set -e
B=build/mutants
mkdir -p $B
sed 's/wire rd_mem    = is_rd \& ~hit \& ~wb_valid;/wire rd_mem = is_rd \& ~hit;  \/\/ MUTANT/' ../rtl/mem/cache.v > $B/cache_m1.v
sed 's/wire do_wupd   = (ENABLE != 0) \& is_wr \& ready_wr \& hit;/wire do_wupd = (ENABLE != 0) \& is_wr \& ready_wr;  \/\/ MUTANT/' ../rtl/mem/cache.v > $B/cache_m2.v
sed 's/assign ready = req \&\& (cnt == LATENCY - 1);/assign ready = req \&\& (cnt == LATENCY);  \/\/ MUTANT/' ../rtl/mem/main_mem.v > $B/main_mem_m3.v
for f in $B/cache_m1.v $B/cache_m2.v $B/main_mem_m3.v; do
  grep -q MUTANT $f || { echo "mutation not applied to $f: update the sed pattern"; exit 1; }
done
bad=0
run() {   # name cache.v main_mem.v
  iverilog -g2005 -s tb_cache -o $B/$1.vvp ../tb/tb_cache.v $2 $3
  if vvp -n $B/$1.vvp | grep -q "tb_cache: FAIL"; then echo "$1: caught (tb_cache FAIL)";
  else echo "$1: NOT caught"; bad=1; fi
}
run m1 $B/cache_m1.v ../rtl/mem/main_mem.v
run m2 $B/cache_m2.v ../rtl/mem/main_mem.v
run m3 ../rtl/mem/cache.v $B/main_mem_m3.v
[ $bad = 0 ] && echo "MUTATION PASS (all mutants caught)" || { echo "MUTATION FAIL"; exit 1; }
