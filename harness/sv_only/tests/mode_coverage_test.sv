// =============================================================================
// mode_coverage_test.sv
// -----------------------------------------------------------------------------
// Goal: Verify all 24 combinations of SPI Modes, Widths, and Bit Orderings.
// Combinations: 4 modes * 3 widths (8/16/32) * 2 orderings (MSB/LSB)
// =============================================================================

`ifndef MODE_COVERAGE_TEST_SV
`define MODE_COVERAGE_TEST_SV

class mode_coverage_test;

    localparam [7:0] APB_CTRL     = 8'h00;
    localparam [7:0] APB_STATUS   = 8'h04;
    localparam [7:0] APB_TX_DATA  = 8'h08;
    localparam [7:0] APB_RX_DATA  = 8'h0C;
    localparam [7:0] APB_CLK_DIV  = 8'h10;
    localparam [7:0] APB_SS_CTRL  = 8'h14;
    localparam [7:0] APB_INT_EN   = 8'h18;
    localparam [7:0] APB_INT_STAT = 8'h1C;
    localparam [7:0] APB_DELAY    = 8'h20;

    // Standard signature with active coverage collector
    static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);
        spi_txn      txn;
        logic [31:0] rd;
        logic [31:0] ctrl_val;
        int          transfer_count;

        $display("[INFO] mode_coverage_test: starting");
        
        transfer_count = 0;

        // Loop through all 4 Modes (CPOL, CPHA)
        for (int m = 0; m < 4; m++) begin
            // Loop through all 3 valid Widths (00=8b, 01=16b, 10=32b)
            for (int w = 0; w < 3; w++) begin
                // Loop through MSB-first (0) and LSB-first (1)
                for (int l = 0; l < 2; l++) begin
                    
                    txn = new();
                    
                    // 1. Constrain transaction for this specific loop iteration
                    if (!txn.randomize() with {
                        mode      == m;
                        width     == w;
                        lsb_first == l;
                        loopback  == 1'b0;          // Normal mode
                        ss_en     == 4'b0001;       // Enable SS_n[0]
                        ss_val    == 4'b0000;       // Drive active-low
                        // Constrain timing to prevent 10ms simulation timeout
                        clk_div   inside {[0:4]};   // Keep the SPI clock extremely fast
                        delay     inside {[0:2]};   // Keep inter-transfer delays tiny
                    }) begin
                        $display("[TEST_FAILED] mode_coverage_test errors=1 (Randomization failed)");
                        ref_model.error_count++;
                        return;
                    end

                    $display("[INFO] mode_coverage_test: Testing Mode=%0d Width=%0d LSB_FIRST=%0d", 
                             txn.mode, txn.width, txn.lsb_first);

                    // 2. Configure Slave BFM via tb_top cross-module references
                    tb_top.bfm_mode      = txn.mode;
                    tb_top.bfm_width     = txn.width;
                    tb_top.bfm_lsb_first = txn.lsb_first;
                    tb_top.bfm_miso_data = txn.miso_data;

                    // 3. APB Configuration Sequence
                    tb_top.u_apb_bfm.apb_write(APB_CLK_DIV, {16'h0, txn.clk_div});
                    tb_top.u_apb_bfm.apb_write(APB_DELAY,   {24'h0, txn.delay});
                    tb_top.u_apb_bfm.apb_write(APB_INT_EN,  32'h0000_000F); 
                    
                    // CTRL: EN=1, MSTR=1, MODE, LSB, LOOPBACK, WIDTH
                    ctrl_val = {24'h0, txn.width, txn.loopback, txn.lsb_first, txn.mode, 1'b1, 1'b1};
                    tb_top.u_apb_bfm.apb_write(APB_CTRL, ctrl_val);

                    // SAMPLE CONFIGURATION COVERAGE HERE!
                    coverage.sample_config(
                        .mode(txn.mode), 
                        .width(txn.width), 
                        .lsb_first(txn.lsb_first), 
                        .clk_div(txn.clk_div), 
                        .delay(txn.delay), 
                        .loopback(txn.loopback)
                    );

                    // 4. Assert Slave Select
                    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, {24'h0, txn.ss_val, txn.ss_en});

                    // 5. Predict and Fire Transfer
                    ref_model.predict_transfer(txn.tx_data, txn.miso_data, txn.loopback, txn.width);
                    tb_top.u_apb_bfm.apb_write(APB_TX_DATA, txn.tx_data);

                    // 6. Wait for completion 
                    tb_top.u_apb_bfm.wait_not_busy();

                    // 7. Deassert Slave Select
                    tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0000);

                    // 8. Pop RX_DATA and verify
                    tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);
                    ref_model.check_rx(rd);

                    // Stop the test early if the scoreboard catches a mismatch to make debugging easier
                    if (ref_model.error_count > 0) begin
                        $display("[INFO] mode_coverage_test: Aborting loop due to scoreboard error.");
                        return;
                    end

                    transfer_count++;
                end
            end
        end

        $display("[INFO] mode_coverage_test: finished %0d combinations, errors=%0d", 
                 transfer_count, ref_model.error_count);
    endtask

endclass

`endif // MODE_COVERAGE_TEST_SV