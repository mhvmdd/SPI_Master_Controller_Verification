# =============================================================================
# Makefile - SV-only starter scaffold for the SPI Master Verification Project
# -----------------------------------------------------------------------------
# This is a concrete Makefile derived from harness/Makefile.template. It is
# pre-wired for the SV-only scaffold that lives next to it (no UVM) and can
# be consumed directly by the grader without modification.
# =============================================================================

SIMULATOR ?= questa
SEED      ?= 0
TEST      ?= sanity_test
WAVES     ?= 0

# Resolve the project root from this file's location.
# harness/examples/sv_only/Makefile  -> ../../..
PROJ_ROOT  ?= ../../..
HARNESS    ?= $(PROJ_ROOT)/harness
STUDENT_TB ?= .

# DUT sources (three-file golden RTL). The grader overrides DUT_SRCS to
# point at faulty_rtl/*_buggy.sv when it injects a bug.
DUT_SRCS   ?= \
  $(PROJ_ROOT)/golden_rtl/spi_core.sv \
  $(PROJ_ROOT)/golden_rtl/apb_regfile.sv \
  $(PROJ_ROOT)/golden_rtl/spi_master.sv
DUT_SRC    ?=
EFF_DUT_SRCS = $(if $(strip $(DUT_SRC)),$(DUT_SRC),$(DUT_SRCS))

BONUS_TEST ?= ral_hw_reset_test

# ---- student source lists ---------------------------------------------------
TB_SRCS    ?= \
  $(STUDENT_TB)/tb/apb_master_bfm.sv \
  $(STUDENT_TB)/tb/spi_slave_bfm.sv \
  $(STUDENT_TB)/tb/tb_top.sv

ENV_SRCS   ?= \
  $(STUDENT_TB)/env/ref_model.sv \
  $(STUDENT_TB)/env/coverage.sv

SEQ_SRCS   ?= \
  $(STUDENT_TB)/sequences/stim_lib.sv

ASSERT_SRCS?= \
  $(STUDENT_TB)/assertions/spi_sva.sv

# NOTE: test files (tests/*.sv) are NOT listed here on purpose.
#
# The plain-SV scaffold ships test classes that take `ref spi_ref_model` /
# `ref spi_coverage_col` arguments. Those classes live in env/ref_model.sv
# and env/coverage.sv (file scope). QuestaSim treats every file in a vlog
# call as a SEPARATE compilation unit, so file-scope class typenames are
# NOT visible to a separately-compiled tests/foo.sv. The test files MUST
# therefore be brought in via `\`include` from inside the tb_top module
# (where the class names are visible), not as standalone vlog inputs.
# tb/tb_top.sv already \`include`s tests/sanity_test.sv and
# tests/ral_hw_reset_test.sv. If you add a new test class:
#   1) drop it under tests/<your_test>.sv
#   2) add `\`include "tests/<your_test>.sv"` near the top of tb/tb_top.sv
#   3) add a dispatcher arm in tb_top's case() statement
#   4) add the test name to REGRESSION_TESTS below
# Do NOT add it to a TEST_SRCS variable here.

# tb_top.sv uses `\`include "env/ref_model.sv"` (etc.), so $(STUDENT_TB)
# itself MUST be on the +incdir+ path. Keep the leaf dirs as well so any
# helper file that says `\`include "ref_model.sv"` (no leading dir) still
# resolves.
INC_DIRS   ?= +incdir+$(HARNESS) +incdir+$(STUDENT_TB) \
              +incdir+$(STUDENT_TB)/env +incdir+$(STUDENT_TB)/tb \
              +incdir+$(STUDENT_TB)/sequences +incdir+$(STUDENT_TB)/tests

# ---- regression list --------------------------------------------------------
# NOTE: The scaffold only provides sanity_test fleshed out. Students MUST
# add the other nine required tests before submitting. The grader checks
# this list matches Section 3 of the grading contract.
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

REGRESSION_SEEDS ?= 20   # 10 * 20 = 200 runs (well under the 10000 cap)

# ============================================================================
# Questa flow (default)
# ============================================================================
ifeq ($(SIMULATOR),questa)

VLOG_FLAGS  = -sv -timescale=1ns/1ps +acc=rn +define+SIM $(INC_DIRS)
COV_FLAG    = -coverage +cover=bcestf

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
	   $(TB_SRCS)

run: compile
	vsim -c work.tb_top \
	     -do "run -all; coverage save cov_$(TEST)_$(SEED).ucdb; quit -f" \
	     +TESTNAME=$(TEST) +UVM_TESTNAME=$(TEST) +SEED=$(SEED) \
	     $(if $(filter 1,$(WAVES)), -wlf waves_$(TEST)_$(SEED).wlf,)

run_bonus: compile
	vsim -c work.tb_top -do "run -all; quit -f" \
	     +TESTNAME=$(BONUS_TEST) +UVM_TESTNAME=$(BONUS_TEST) +SEED=$(SEED)

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
	-vcover merge -out build/merged.ucdb $(wildcard cov_*.ucdb)

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

.PHONY: compile run run_bonus regress cov clean
