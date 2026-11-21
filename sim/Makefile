# Project 9 simulation Makefile (Icarus Verilog + GTKWave). Run from sim/:
#   make asm        assemble programs/*.s -> programs/*.hex (+ assembler self-test)
#   make unit       unit testbenches (decoder, instr_mem, data_mem, harvard_mem)
#   make harvard    every program on harvard_top
#   make vn         every program on vn_top (shared-memory baseline)
#   make compare    every program on both, prints the comparison table
#   make phase1     asm + unit + harvard + vn + compare, logs in ../results/logs/
#   make waves      open the Harvard-vs-baseline waveform (PROG=memcopy) in GTKWave,
#                   or in Surfer if GTKWave is not installed (Homebrew no longer ships GTKWave for macOS)
#   make figure     regenerate the report's waveform figure from the memcopy simulation
#
# Phase II (memory hierarchy):
#   make iss        golden-model self-test (tools/iss.py)
#   make cache      cache unit test (tb_cache)
#   make system     every program on all five systems, L = 1 and L = 8,
#                   write buffer off and on (tb_system), log in ../results/logs/system.log
#   make sweep      full parameter sweep + golden-model cross-check (tools/sweep.py)
#                   -> ../results/phase2/sweep.csv, summary.md, ../report/data/*.dat
#   make figure2    Phase II waveform figure (memcopy, L = 4) from a real VCD
#   make waves2     open that VCD in GTKWave / Surfer
#   make phase2     iss + cache + system + sweep + figure2
#   make all        Phase I flow + Phase II flow
#   make clean

IVERILOG := iverilog -g2005 -Wall -I ../tb
VVP      := vvp -n
PYTHON   := python3
BUILD    := build
LOGS     := ../results/logs

PROGRAMS1 := basic array_sum memcopy count_loop
PROGRAMS2 := bubble_sort subroutine transpose isa_test
PROGRAMS  := $(PROGRAMS1) $(PROGRAMS2)
PROG     ?= memcopy

MEM_RTL  := ../rtl/mem/instr_mem.v ../rtl/mem/data_mem.v ../rtl/mem/addr_decoder.v \
            ../rtl/mem/rw_ctrl.v ../rtl/mem/harvard_mem.v
CORE_RTL := ../rtl/core/regfile.v ../rtl/core/alu.v ../rtl/core/imm_gen.v \
            ../rtl/core/control.v ../rtl/core/pc_reg.v ../rtl/core/cpu_core.v
PERF_RTL := ../rtl/common/perf_counters.v
VN_RTL   := ../rtl/baseline/shared_mem.v ../rtl/baseline/cpu_core_vn.v ../rtl/baseline/vn_top.v \
            ../rtl/mem/addr_decoder.v ../rtl/core/regfile.v ../rtl/core/alu.v \
            ../rtl/core/imm_gen.v ../rtl/core/control.v
H_RTL    := $(MEM_RTL) $(CORE_RTL) $(PERF_RTL) ../rtl/harvard_top.v
ALL_RTL  := $(sort $(H_RTL) $(VN_RTL))
# Phase II
HIER_RTL := ../rtl/mem/cache.v ../rtl/mem/main_mem.v ../rtl/common/event_counters.v \
            ../rtl/common/arbiter.v ../rtl/mh_top.v ../rtl/baseline/vnc_top.v
SYS_RTL  := $(sort $(ALL_RTL) $(HIER_RTL) $(PERF_RTL))
SYS_CFGS := 1:0 1:1 8:0 8:1
FIG2_FIRST  ?= 8
FIG2_CYCLES ?= 17

# -P parameters for a system testbench, used inside a "for p in ..." shell loop:
#   $(call params,tb_name)  ->  -Ptb_name.PROG_NAME="basic" -Ptb_name.PROG_FILE=... etc.
# Escaped quotes so the shell still expands ${p}; braces so ${p}_data is not read as $p_data.
params = -P$(1).PROG_NAME=\"$${p}\" -P$(1).PROG_FILE=\"../programs/$${p}.hex\" \
         -P$(1).DATA_FILE=\"../programs/$${p}_data.hex\"

.PHONY: all phase1 phase2 asm unit harvard vn compare waves figure clean dirs \
        iss cache system sweep figure2 waves2 mutate

all: phase1 phase2

phase1: asm unit harvard vn compare

phase2: iss cache mutate system sweep figure2

dirs:
	@mkdir -p $(BUILD) $(LOGS)

asm: dirs
	$(PYTHON) ../tools/asm.py --selftest | tee $(LOGS)/asm_selftest.log
	@for p in $(PROGRAMS); do \
	  $(PYTHON) ../tools/asm.py ../programs/$$p.s -o ../programs/$$p.hex || exit 1; \
	  echo "assembled $$p.s -> $$p.hex"; done

unit: dirs
	@rm -f $(LOGS)/unit.log
	@for t in tb_addr_decoder:../rtl/mem/addr_decoder.v \
	          tb_instr_mem:../rtl/mem/instr_mem.v \
	          tb_data_mem:../rtl/mem/data_mem.v \
	          tb_harvard_mem:"$(MEM_RTL)"; do \
	  tb=$${t%%:*}; src=$${t#*:}; \
	  $(IVERILOG) -s $$tb -o $(BUILD)/$$tb.vvp ../tb/$$tb.v $$src || exit 1; \
	  $(VVP) $(BUILD)/$$tb.vvp | grep -v "VCD info" | tee -a $(LOGS)/unit.log; \
	done
	@! grep -q FAIL $(LOGS)/unit.log

harvard: dirs
	@rm -f $(LOGS)/harvard.log
	@for p in $(PROGRAMS); do \
	  $(IVERILOG) -s tb_harvard_top $(call params,tb_harvard_top) \
	    -o $(BUILD)/tb_harvard_top_$$p.vvp ../tb/tb_harvard_top.v $(H_RTL) || exit 1; \
	  $(VVP) $(BUILD)/tb_harvard_top_$$p.vvp | grep -v "VCD info" | tee -a $(LOGS)/harvard.log; \
	done
	@! grep -q FAIL $(LOGS)/harvard.log

vn: dirs
	@rm -f $(LOGS)/vn.log
	@for p in $(PROGRAMS); do \
	  $(IVERILOG) -s tb_vn_top $(call params,tb_vn_top) \
	    -o $(BUILD)/tb_vn_top_$$p.vvp ../tb/tb_vn_top.v $(VN_RTL) $(PERF_RTL) || exit 1; \
	  $(VVP) $(BUILD)/tb_vn_top_$$p.vvp | grep -v "VCD info" | tee -a $(LOGS)/vn.log; \
	done
	@! grep -q FAIL $(LOGS)/vn.log

compare: dirs
	@rm -f $(LOGS)/compare.log
	@echo "| Program    | Instr | LW/SW % | Harvard cycles | Harvard CPI | Baseline cycles | Baseline CPI | Speed-up | Simultaneous cycles |" | tee -a $(LOGS)/compare.log
	@echo "|---|---|---|---|---|---|---|---|---|" | tee -a $(LOGS)/compare.log
	@for p in $(PROGRAMS); do \
	  $(IVERILOG) -s tb_compare $(call params,tb_compare) \
	    -o $(BUILD)/tb_compare_$$p.vvp ../tb/tb_compare.v $(ALL_RTL) || exit 1; \
	  $(VVP) $(BUILD)/tb_compare_$$p.vvp | grep -v "VCD info" | tee -a $(LOGS)/compare.log; \
	done
	@! grep -q FAIL $(LOGS)/compare.log

waves: dirs
	@test -f $(BUILD)/tb_compare_$(PROG).vcd || $(MAKE) compare
	@if command -v gtkwave >/dev/null; then \
	  gtkwave $(BUILD)/tb_compare_$(PROG).vcd waves.gtkw & \
	elif command -v surfer >/dev/null; then \
	  surfer $(BUILD)/tb_compare_$(PROG).vcd -c waves.sucl & \
	else echo "install GTKWave or Surfer (brew install surfer) to view waveforms"; fi

figure: dirs
	@test -f $(BUILD)/tb_compare_memcopy.vcd || $(MAKE) compare
	$(PYTHON) ../tools/vcd2tikz.py $(BUILD)/tb_compare_memcopy.vcd -o ../report/figures/wave.tex --cycles 12

# ---------------------------------------------------------------- Phase II
iss: dirs
	$(PYTHON) ../tools/iss.py --selftest | tee $(LOGS)/iss_selftest.log
	@! grep -q FAIL $(LOGS)/iss_selftest.log

cache: dirs
	$(IVERILOG) -s tb_cache -o $(BUILD)/tb_cache.vvp ../tb/tb_cache.v ../rtl/mem/cache.v ../rtl/mem/main_mem.v
	$(VVP) $(BUILD)/tb_cache.vvp | grep -v "VCD info" | tee $(LOGS)/cache.log
	@! grep -q FAIL $(LOGS)/cache.log

# every program on every system for a few (latency : write buffer) settings, 8 lines per cache
system: dirs
	@rm -f $(LOGS)/system.log
	@for c in $(SYS_CFGS); do L=$${c%%:*}; W=$${c#*:}; \
	  $(IVERILOG) -s tb_system -Ptb_system.LATENCY=$$L -Ptb_system.WBUF=$$W \
	    -o $(BUILD)/tb_system_L$${L}_wb$${W}.vvp ../tb/tb_system.v $(SYS_RTL) || exit 1; \
	  for p in $(PROGRAMS); do \
	    $(VVP) $(BUILD)/tb_system_L$${L}_wb$${W}.vvp +PROG=../programs/$$p.hex \
	      +DATA=../programs/$${p}_data.hex +NAME=$$p | grep -E "PASS|FAIL" | tee -a $(LOGS)/system.log; \
	  done; done
	@! grep -q FAIL $(LOGS)/system.log

sweep: dirs
	cd .. && $(PYTHON) tools/sweep.py

# Phase II waveform: memcopy on the modified Harvard system, L = 4, write buffer on
$(BUILD)/tb_system_memcopy.vcd: | dirs
	$(IVERILOG) -s tb_system -Ptb_system.LATENCY=4 -Ptb_system.WBUF=1 \
	  -o $(BUILD)/tb_system_wave.vvp ../tb/tb_system.v $(SYS_RTL)
	$(VVP) $(BUILD)/tb_system_wave.vvp +PROG=../programs/memcopy.hex \
	  +DATA=../programs/memcopy_data.hex +NAME=memcopy +VCD=$(BUILD)/tb_system_memcopy.vcd | grep -E "PASS|FAIL"

figure2: $(BUILD)/tb_system_memcopy.vcd
	$(PYTHON) ../tools/vcd2tikz.py $(BUILD)/tb_system_memcopy.vcd -o ../report/figures/wave2.tex \
	  --set phase2 --first $(FIG2_FIRST) --cycles $(FIG2_CYCLES)

waves2: $(BUILD)/tb_system_memcopy.vcd
	@if command -v gtkwave >/dev/null; then gtkwave $(BUILD)/tb_system_memcopy.vcd & \
	elif command -v surfer >/dev/null; then surfer $(BUILD)/tb_system_memcopy.vcd & \
	else echo "install GTKWave or Surfer (brew install surfer) to view waveforms"; fi

clean:
	rm -rf $(BUILD)

# tb_cache must fail on deliberately broken RTL copies (see tools/mutate_cache.sh)
mutate: dirs
	sh ../tools/mutate_cache.sh | tee $(LOGS)/mutate.log
