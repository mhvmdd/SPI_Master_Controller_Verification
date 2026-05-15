// =============================================================================
// tb_top.sv  (SV-only starter scaffold)
// -----------------------------------------------------------------------------
// Plain-SV top-level module. Instantiates the DUT wrapper, the APB master BFM,
// the SPI slave BFM, the scoreboard/coverage collectors, and selects the test
// via +TESTNAME=<name> (or +UVM_TESTNAME=<name> as a fallback so the same
// Makefile works for SV-only and UVM flows).
//
// Contract with the grader:
//   * Every test MUST end with exactly one "[TEST_PASSED] <name>" or
//     "[TEST_FAILED] <name> errors=<n>" line. The stub below satisfies that
//     for the sanity_test example.
// =============================================================================

`timescale 1ns/1ps
`include "env/ref_model.sv"
`include "env/coverage.sv"
`include "sequences/stim_lib.sv"
`include "tests/sanity_test.sv"
`include "tests/randomized_sanity_test.sv"
`include "tests/ral_hw_reset_test.sv"

module tb_top;

    // ----------------- Clock and reset --------------------------------------
    bit PCLK = 0;
    always #5 PCLK = ~PCLK;   // 100 MHz

    bit PRESETn;

    // ----------------- Interfaces -------------------------------------------
    apb_if apb (.pclk(PCLK), .presetn(PRESETn));
    spi_if spi (.pclk(PCLK));

    // Local signals used only by the slave BFM
    logic [1:0] bfm_mode    = 2'b00;
    logic [7:0] bfm_pattern = 8'hA5;

    // ----------------- DUT wrapper -----------------------------------------
    dut_wrapper u_wrap (.apb(apb), .spi(spi));

    // ----------------- BFMs -------------------------------------------------
    apb_master_bfm u_apb_bfm (.apb(apb.master));
    spi_slave_bfm  u_spi_bfm (.spi(spi.slave), .mode(bfm_mode),
                              .miso_byte(bfm_pattern));

    // ----------------- Predictor / Scoreboard / Coverage --------------------
    spi_ref_model    u_ref   = new();
    spi_coverage_col u_cov   = new();

    // ----------------- SVA bind ---------------------------------------------
    // Bind by *instance path* relative to tb_top: u_wrap is the dut_wrapper
    // instance, u_dut is the spi_master instance inside it, u_regfile is the
    // apb_regfile instance inside spi_master. The bind injects spi_sva into
    // the u_regfile instance with port hookups read from the same scope.
    bind u_wrap.u_dut.u_regfile spi_sva u_sva (
        .PCLK   (PCLK),
        .PRESETn(PRESETn),
        .ctrl_en(u_wrap.u_dut.u_regfile.ctrl_en),
        .int_stat(u_wrap.u_dut.u_regfile.int_stat),
        .IRQ     (u_wrap.u_dut.u_regfile.IRQ)
    );

    // ----------------- Test dispatch ----------------------------------------
    string testname;

    initial begin
        PRESETn = 0;
        #50;
        PRESETn = 1;

        if (!$value$plusargs("TESTNAME=%s", testname) &&
            !$value$plusargs("UVM_TESTNAME=%s", testname))
            testname = "sanity_test";

        $display("[INFO] Starting test: %s", testname);

        case (testname)
            "sanity_test"             : sanity_test::run(u_ref, u_cov);
            "randomized_sanity_test"  : randomized_sanity_test::run(u_ref, u_cov);
            "ral_hw_reset_test"    : begin
                // SV-only scaffold does not implement the RAL bonus.
                // Emit the TEST_SKIPPED line so the grader can award 0 for
                // the RAL bonus without penalising the rest of the rubric.
                $display("[TEST_SKIPPED] ral_hw_reset_test");
                $finish;
            end
            // TODO: add one case arm per required test you implement.
            // The grader expects every test name listed in
            // harness/grading_interface.md Section 3 to print
            // [TEST_PASSED]/[TEST_FAILED] exactly once. Tests should
            // follow the sanity_test signature (predictor + coverage by
            // ref; BFMs reached via tb_top.u_apb_bfm / tb_top.u_spi_bfm).
            // Example:
            //   "reg_access_test"     : reg_access_test::run(u_ref, u_cov);
            //   "mode_coverage_test"  : mode_coverage_test::run(u_ref, u_cov);
            default : begin
                $display("[TEST_FAILED] %s errors=1  (unknown test name)", testname);
                $finish;
            end
        endcase

        // Single PASS line for the dispatcher. Each test::run task is
        // expected to have printed [SCOREBOARD_ERROR] on mismatches and
        // incremented u_ref.error_count; convert that into the final
        // PASS/FAIL line here.
        if (u_ref.error_count == 0)
            $display("[TEST_PASSED] %s", testname);
        else
            $display("[TEST_FAILED] %s errors=%0d", testname, u_ref.error_count);
        $finish;
    end

    // ----------------- Safety timeout ---------------------------------------
    initial begin
        #10_000_000;  // 10 ms worth of sim time
        $display("[TEST_FAILED] %s errors=1  (timeout)", testname);
        $finish;
    end

endmodule
