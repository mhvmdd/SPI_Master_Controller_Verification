// =============================================================================
// clk_div_corner_test.sv
// -----------------------------------------------------------------------------
// Goal: Verify SPI clock generation logic across extreme divider boundaries.
// Checks R8 and R24 by measuring SCLK period in simulation time.
// Checks R25 by altering CLK_DIV mid-transfer to ensure the current transfer
// is unaffected, but the subsequent transfer adopts the new frequency.
// =============================================================================

`ifndef CLK_DIV_CORNER_TEST_SV
`define CLK_DIV_CORNER_TEST_SV

class clk_div_corner_test;

    localparam [7:0] APB_CTRL     = 8'h00;
    localparam [7:0] APB_STATUS   = 8'h04;
    localparam [7:0] APB_TX_DATA  = 8'h08;
    localparam [7:0] APB_RX_DATA  = 8'h0C;
    localparam [7:0] APB_CLK_DIV  = 8'h10;
    localparam [7:0] APB_SS_CTRL  = 8'h14;
    localparam [7:0] APB_INT_EN   = 8'h18;

    // Helper task to measure SCLK period. 
    // tb_top.sv defines PCLK as `always #5 PCLK = ~PCLK;`, so 1 PCLK = 10ns.
    static task measure_sclk_period(input int expected_div, ref spi_ref_model ref_model);
        time t1, t2;
        time expected_time = 10 * 2 * (expected_div + 1); // PCLK_PERIOD * 2 * (DIV + 1)

        @(posedge tb_top.spi.sclk);
        t1 = $time;
        @(posedge tb_top.spi.sclk);
        t2 = $time;

        if ((t2 - t1) !== expected_time) begin
            $display("[SCOREBOARD_ERROR] SCLK period mismatch! DIV=%0d, Expected=%0dt, Observed=%0dt", 
                     expected_div, expected_time, (t2-t1));
            ref_model.error_count++;
        end
    endtask

    static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);
        spi_txn      txn;
        logic [31:0] rd;
        logic [31:0] ctrl_val;
        
        // Bins required by Coverage Spec 10.1
        int div_targets[] = '{0, 1, 2, 3, 255, 1024, 65535, 42};

        $display("[INFO] clk_div_corner_test: starting");

        // =====================================================================
        // Phase 1: Frequency Measurement across corner cases (R8 & R24)
        // =====================================================================
        $display("[INFO] clk_div_corner_test: Phase 1 - Sweeping Frequencies");
        
        foreach (div_targets[i]) begin
            txn = new();
            // Turn off the safety constraint from stim_lib.sv so we can hit 65535!
            txn.c_clk_div_sane.constraint_mode(0);
            if (!txn.randomize() with {
                clk_div   == div_targets[i];
                width     == 2'b00;         // 8-bit
                loopback  == 1'b1;          
                ss_en     == 4'b0001;       
                ss_val    == 4'b0000;       
            }) begin
                $display("[TEST_FAILED] Randomization failed");
                return;
            end

            tb_top.u_apb_bfm.apb_write(APB_CLK_DIV, {16'h0, txn.clk_div});
            tb_top.u_apb_bfm.apb_write(APB_INT_EN,  32'h0000_0000); 
            
            ctrl_val = {24'h0, txn.width, txn.loopback, txn.lsb_first, txn.mode, 1'b1, 1'b1};
            tb_top.u_apb_bfm.apb_write(APB_CTRL, ctrl_val);

            // Sample Coverage
            coverage.sample_config(txn.mode, txn.width, txn.lsb_first, txn.clk_div, txn.delay, txn.loopback);

            tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, {24'h0, txn.ss_val, txn.ss_en});

            // Fire Transfer
            ref_model.predict_transfer(.tx_data(txn.tx_data), .miso_data(32'h0), .loopback(txn.loopback), .width(txn.width));
            tb_top.u_apb_bfm.apb_write(APB_TX_DATA, txn.tx_data);

            // Fork a thread to measure the SCLK timing while the APB waits
            fork
                measure_sclk_period(txn.clk_div, ref_model);
                tb_top.u_apb_bfm.wait_not_busy();
            join

            tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0000);
            tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);
            ref_model.check_rx(rd);
            tb_top.u_apb_bfm.apb_write(APB_CTRL, 32'h0000_0000); // Clean state
        end

        // =====================================================================
        // Phase 2: Mid-Transfer CLK_DIV Change (Spec R25)
        // =====================================================================
        $display("[INFO] clk_div_corner_test: Phase 2 - Testing R25 Mid-Transfer Lock");

        // Set initial DIV to 10
        tb_top.u_apb_bfm.apb_write(APB_CLK_DIV, 32'd10);
        ctrl_val = {24'h0, 2'b10, 1'b1, 1'b0, 2'b00, 1'b1, 1'b1}; // 32-bit transfer for plenty of time
        tb_top.u_apb_bfm.apb_write(APB_CTRL, ctrl_val);
        tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0001);

        ref_model.predict_transfer(.tx_data(32'hAAAA_BBBB), .miso_data(32'h0), .loopback(1'b1), .width(2'b10));
        tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'hAAAA_BBBB);

        // Wait a few PCLKs so the transfer is actively shifting
        repeat(10) @(posedge tb_top.PCLK);

        // SABOTAGE: Change DIV to 2 right in the middle of the transfer!
        tb_top.u_apb_bfm.apb_write(APB_CLK_DIV, 32'd2);

        // Measure SCLK. It MUST still be running at DIV=10 speed!
        fork
            measure_sclk_period(10, ref_model);
            tb_top.u_apb_bfm.wait_not_busy();
        join
        
        // Pop the first word
        tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);
        ref_model.check_rx(rd);

        // Now fire a SECOND transfer. It should automatically adopt the new DIV=2.
        ref_model.predict_transfer(.tx_data(32'h1111_2222), .miso_data(32'h0), .loopback(1'b1), .width(2'b10));
        tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'h1111_2222);

        fork
            measure_sclk_period(2, ref_model);
            tb_top.u_apb_bfm.wait_not_busy();
        join

        tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);
        ref_model.check_rx(rd);

        // Cleanup
        tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0);
        tb_top.u_apb_bfm.apb_write(APB_CTRL, 32'h0);

        $display("[INFO] clk_div_corner_test: finished, internal errors=%0d", ref_model.error_count);
    endtask

endclass

`endif // CLK_DIV_CORNER_TEST_SV