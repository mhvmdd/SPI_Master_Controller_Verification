// =============================================================================
// randomized_sanity_test.sv  (SV-only starter scaffold)
// -----------------------------------------------------------------------------
// Companion to sanity_test. Same end-to-end checking, but the configuration
// is built from a randomised `spi_txn` (sequences/stim_lib.sv) instead of
// hard-coded literals. Use this as a template for your own constrained-random
// tests.
//
// What this test demonstrates:
//   1. How to instantiate spi_txn:               t = new();
//   2. How to constrain it inline at randomize:  t.randomize() with { ... };
//   3. How to print a transaction for debug:     $display(... t.sprint());
//   4. How to drive the randomised fields onto the DUT through the APB BFM.
//   5. How to keep the predictor in lock-step with the random TX byte.
//   6. How to sample functional coverage from the same fields.
//
// IMPORTANT - constraint scoping:
//
//   The starter scaffold has known limitations that students will lift later:
//     * spi_slave_bfm only supports mode 0 (CPOL=0, CPHA=0).
//     * spi_slave_bfm is hard-wired MSB-first.
//     * spi_ref_model only predicts a single 8-bit transfer.
//
//   For this scaffolded demonstration we therefore PIN the fields the slave
//   BFM cannot follow (mode, lsb_first, width, loopback) and only let the
//   random fields that DON'T affect the predicted RX byte vary (clk_div,
//   delay_cfg, tx_data). That keeps the test deterministic on golden RTL
//   while still showing the randomisation pattern.
//
//   Once you extend spi_slave_bfm to handle modes 1..3 and LSB-first, just
//   relax the corresponding constraint in your own variant of this test.
//
// Public API: randomized_sanity_test::run(ref_model, coverage);
// =============================================================================

`ifndef RANDOMIZED_SANITY_TEST_SV
`define RANDOMIZED_SANITY_TEST_SV

class randomized_sanity_test;

    static task run(ref spi_ref_model     ref_model,
                    ref spi_coverage_col  coverage);

            spi_txn   t;
            bit [31:0] ctrl_word;
            bit [31:0] rd;
            int        seed;

            $display("[INFO] randomized_sanity_test: starting");

            // Step 1 - instantiate the transaction (same pattern as UVM
            // factory create, but plain SV: just `new()`).
            t = new();

            // Optional: re-seed from the +SEED= plusarg so successive seeds
            // explore different points in the constrained space. Without this,
            // every invocation gets the *same* random values (default thread
            // seed). For real coverage closure, also call srandom() on every
            // transaction, not just once.
            if ($value$plusargs("SEED=%d", seed))
                t.srandom(seed);

        // Step 2 - randomise with inline constraints. The `with { ... }`
        // clause is appended to the class's own constraint block (so we
        // still get c_width_legal / c_clk_div_sane / c_delay_sane).
        if (!t.randomize() with {
                mode      == 2'b00;     // pinned: slave BFM only supports mode 0
                width     == 2'b00;     // pinned: predictor only models 8-bit
                lsb_first == 1'b0;      // pinned: slave BFM is MSB-first only
                loopback  == 1'b0;      // pinned: external MISO check
                // Allow random clk_div, delay_cfg, tx_data within the class's
                // own constraints. Keep clk_div bounded so the test runs in a
                // reasonable wall-clock time.
                clk_div   inside {[1:32]};
            }) begin
            $display("[SCOREBOARD_ERROR] spi_txn randomization failed");
            ref_model.error_count++;
            return;
        end

        // Step 3 - print the randomised transaction. Drop this in every
        // test you write; it makes regression triage 10x easier because
        // every failure log shows exactly what was driven.
        $display("[INFO] randomized_sanity_test: %s", t.sprint());

        // Keep the slave BFM's mode in sync with the (pinned) random mode.
        tb_top.bfm_mode    = t.mode;
        tb_top.bfm_pattern = 8'hA5;

        // Step 4 - drive the randomised fields through the APB BFM. CTRL
        // bit layout (from the spec / Register Map):
        //   [0] EN, [1] MSTR, [3:2] MODE, [4] LSB_FIRST, [5] LOOPBACK,
        //   [7:6] WIDTH (00=8b, 01=16b, 10=32b)
        ctrl_word = 32'h0;
        ctrl_word[0]   = 1'b1;          // EN
        ctrl_word[1]   = 1'b1;          // MSTR
        ctrl_word[3:2] = t.mode;
        ctrl_word[4]   = t.lsb_first;
        ctrl_word[5]   = t.loopback;
        ctrl_word[7:6] = t.width;

        tb_top.u_apb_bfm.apb_write(8'h00, ctrl_word);                 // CTRL
        tb_top.u_apb_bfm.apb_write(8'h10, {16'h0, t.clk_div});        // CLK_DIV
        tb_top.u_apb_bfm.apb_write(8'h20, {24'h0, t.delay_cfg});      // DELAY
        tb_top.u_apb_bfm.apb_write(8'h18, 32'h0000_000F);             // INT_EN

        // Step 5 - tell the predictor what to expect BEFORE pushing TX.
        // The scaffold predictor only models the 8 LSBs.
        ref_model.predict_single_byte(.tx_byte(t.tx_data[7:0]),
                                      .miso_pattern(tb_top.bfm_pattern),
                                      .loopback(t.loopback));

        // Step 6 - sample functional coverage with the same fields we just
        // drove. This contributes to the 85% coverage gate. Real tests
        // should also extend the covergroup with bins for clk_div / delay.
        coverage.sample_config(.mode(t.mode),
                               .lsb_first(t.lsb_first),
                               .width(t.width));

            // Step 7 - push TX and assert SS lane 0.
            // SS_CTRL layout (see Register Map): [3:0]=ss_en, [7:4]=ss_val.
            // SS_n[i] = ~ss_en[i] | ss_val[i], so to assert lane 0 LOW we need
            // ss_en[0]=1 AND ss_val[0]=0  ->  SS_CTRL=0x01.
            tb_top.u_apb_bfm.apb_write(8'h08, t.tx_data);                 // TX_DATA
            tb_top.u_apb_bfm.apb_write(8'h14, 32'h0000_0001);             // SS_CTRL: assert ss[0] low

        // Step 8 - busy-poll STATUS.BUSY until the transfer drains.
        // 500 polls is enough headroom for clk_div up to 32 (max above).
        repeat (500) begin
            tb_top.u_apb_bfm.apb_read(8'h04, rd);                     // STATUS
            if (rd[0] == 1'b0) break;
        end

        // Step 9 - read RX_DATA and let the scoreboard check it.
        tb_top.u_apb_bfm.apb_read(8'h0C, rd);                         // RX_DATA
        ref_model.check_rx(rd);

        // Cleanup: deassert SS so the next test starts from a clean state.
        tb_top.u_apb_bfm.apb_write(8'h14, 32'h0000_0000);

        $display("[INFO] randomized_sanity_test: finished, errors=%0d",
                 ref_model.error_count);
    endtask

endclass

`endif // RANDOMIZED_SANITY_TEST_SV
