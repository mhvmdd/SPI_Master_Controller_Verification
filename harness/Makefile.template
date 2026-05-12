# =============================================================================
# Makefile.template - SPI Master Verification Project
# -----------------------------------------------------------------------------
# Students MUST keep these target names intact so the grader script can run
# their environment without modification:
#
#   make compile              - compile TB + DUT
#   make run TEST=<name>      - run a single test (SEED defaulted to 0)
#   make regress              - run the full regression list (<=10000 runs)
#   make run_bonus            - run the mandatory RAL bonus test (BONUS_TEST)
#   make cov                  - produce coverage_report.txt
#   make clean                - remove build artifacts
#
# Students MAY add further targets but MUST NOT rename the above.
# -----------------------------------------------------------------------------
# DUT RTL sources
# -----------------------------------------------------------------------------
# The DUT is now a thin top (spi_master.sv) instantiating two visible sub-
# blocks (apb_regfile + spi_core). By default the grader compiles all three
# files as DUT_SRCS. For backwards compatibility the grader can also set
# DUT_SRC to a SINGLE flat path that replaces the whole RTL tree (internal
# fallback only - students SHOULD NOT override DUT_SRC themselves).
# =============================================================================

# ---- toolchain --------------------------------------------------------------
SIMULATOR ?= questa
SEED      ?= 0
TEST      ?= sanity_test
WAVES     ?= 0

# ---- paths ------------------------------------------------------------------
PROJ_ROOT  ?= ..
# DUT_SRCS is the normal, multi-file RTL list. The grader overrides this to
# point at faulty_rtl/*_buggy.sv for bug-injection runs.
DUT_SRCS   ?= \
  $(PROJ_ROOT)/golden_rtl/spi_core.sv \
  $(PROJ_ROOT)/golden_rtl/apb_regfile.sv \
  $(PROJ_ROOT)/golden_rtl/spi_master.sv
# DUT_SRC is kept as a single-file override escape hatch. If set, it replaces
# DUT_SRCS entirely. Students MUST NOT set this; only the grader may.
DUT_SRC    ?=
HARNESS    ?= $(PROJ_ROOT)/harness
STUDENT_TB ?= .

# Bonus test name (used by `make run_bonus`). If students attempt the RAL
# bonus they MUST name the gating test exactly this. The grader will not
# fall back to any other name for the RAL bonus.
BONUS_TEST ?= ral_hw_reset_test

# Student source lists. Students fill these in.
TB_SRCS    ?= \
  $(STUDENT_TB)/tb/tb_top.sv

ENV_SRCS   ?=
TEST_SRCS  ?=
SEQ_SRCS   ?=
ASSERT_SRCS?=

INC_DIRS   ?= +incdir+$(HARNESS) +incdir+$(STUDENT_TB)/env +incdir+$(STUDENT_TB)/tb

# ---- required regression list ----------------------------------------------
# The grader will inspect this list to verify the regression cap. Every test
# named here MUST run when invoked via `make run TEST=<name>`.
REGRESSION_TESTS = \
  sanity_test \
  reg_access_test \
  mode_coverage_test \
  width_coverage_test \
  fifo_stress_test \
  interrupt_test \
  clk_div_corner_test \
  loopback_test \
  delay_transfer_test \
  error_injection_test

REGRESSION_SEEDS ?= 10     # seeds per test. 10 tests * 10 seeds * ~100 transactions = <10k runs

# ============================================================================
# Questa-specific targets (default)
# ============================================================================
ifeq ($(SIMULATOR),questa)

VLOG_FLAGS  = -sv -timescale=1ns/1ps +acc=rn +define+SIM $(INC_DIRS)
VSIM_FLAGS  = -c -do "run -all; coverage save cov.ucdb; quit -f" -voptargs=+acc
COV_FLAG    = -coverage +cover=bcestf

# Pick the DUT source list:
#   - If DUT_SRC is set (non-empty), use ONLY that single file.
#   - Else use DUT_SRCS (the normal multi-file list).
EFF_DUT_SRCS = $(if $(strip $(DUT_SRC)),$(DUT_SRC),$(DUT_SRCS))

compile:
	@mkdir -p build
	vlib work
	vlog $(VLOG_FLAGS) $(COV_FLAG) \
	   $(HARNESS)/apb_if.sv \
	   $(HARNESS)/spi_if.sv \
	   $(EFF_DUT_SRCS) \
	   $(HARNESS)/dut_wrapper.sv \
	   $(ENV_SRCS) \
	   $(SEQ_SRCS) \
	   $(ASSERT_SRCS) \
	   $(TEST_SRCS) \
	   $(TB_SRCS)

run: compile
	vsim -c work.tb_top -do "run -all; coverage save cov_$(TEST)_$(SEED).ucdb; quit -f" \
	     +UVM_TESTNAME=$(TEST) +TEST=$(TEST) +TESTNAME=$(TEST) +SEED=$(SEED) \
	     $(if $(filter 1,$(WAVES)), -wlf waves_$(TEST)_$(SEED).wlf,)

# Mandatory bonus entry point for the grader's RAL check. Students who do
# not implement the RAL bonus are free to leave this as a no-op that emits
# "[TEST_SKIPPED] ral_hw_reset_test"; the grader treats that as a zero-score
# RAL bonus without affecting the base rubric.
run_bonus: compile
	vsim -c work.tb_top -do "run -all; quit -f" \
	     +UVM_TESTNAME=$(BONUS_TEST) +TEST=$(BONUS_TEST) +TESTNAME=$(BONUS_TEST) \
	     +SEED=$(SEED)

# Internal helper target: run one test across all seeds
define REGRESS_ONE
	@echo "=== Running $(1) for $(REGRESSION_SEEDS) seeds ==="
	@for s in `seq 1 $(REGRESSION_SEEDS)` ; do \
	    $(MAKE) -s run TEST=$(1) SEED=$$s WAVES=0 \
	      > build/log_$(1)_$$s.log 2>&1 ; \
	done
endef

regress: compile
	@mkdir -p build
	$(foreach t,$(REGRESSION_TESTS),$(call REGRESS_ONE,$(t)))
	vcover merge -out build/merged.ucdb $(wildcard cov_*.ucdb)

cov:
	@if [ -f build/merged.ucdb ]; then \
	    vcover report -details build/merged.ucdb > coverage_report.txt ; \
	    echo "Coverage report: coverage_report.txt" ; \
	else \
	    echo "No merged.ucdb - run 'make regress' first" ; exit 1 ; \
	fi

clean:
	rm -rf work build *.wlf *.vstf *.ucdb transcript coverage_report.txt

endif

# ============================================================================
# Stub targets for other simulators - students may flesh these out.
# ============================================================================
ifeq ($(SIMULATOR),verilator)
$(error Verilator flow not provided by default - supply your own if needed)
endif

.PHONY: compile run run_bonus regress cov clean
