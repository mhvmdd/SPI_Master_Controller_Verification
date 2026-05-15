// =============================================================================
// ral_hw_reset_test.sv  (SV-only starter scaffold)
// -----------------------------------------------------------------------------
// This is a STUB. The SV-only scaffold does not implement the UVM RAL bonus
// (which requires a uvm_reg_block + uvm_reg_hw_reset_seq). The grader still
// needs `make run_bonus` to terminate cleanly, so we emit the agreed
// "[TEST_SKIPPED] ral_hw_reset_test" line and exit.
//
// If you want the +5% RAL bonus, delete this file, adopt UVM, and follow
// harness/grading_interface.md Section 7.
// =============================================================================

`ifndef RAL_HW_RESET_TEST_SV
`define RAL_HW_RESET_TEST_SV

class ral_hw_reset_test;
    // Intentionally empty. The actual [TEST_SKIPPED] message is printed by
    // tb_top's dispatcher when it recognises this test name, because the
    // dispatcher has no class instance to hand off to. This file exists so
    // the Makefile's TEST_SRCS list compiles cleanly.
endclass

`endif // RAL_HW_RESET_TEST_SV
