// =============================================================================
// loopback_test.sv
// -----------------------------------------------------------------------------
// Goal: Verify Requirement R19 (Internal Loopback).
// Drives distinct payload data on TX while forcing the BFM to drive garbage 
// (0xBAD_C0DE) on the external MISO line. Validates that the RX FIFO exactly 
// matches the TX payload across 8, 16, and 32-bit widths, completely ignoring MISO.
// =============================================================================

`ifndef LOOPBACK_TEST_SV
`define LOOPBACK_TEST_SV

class loopback_test;

    localparam [7:0] APB_CTRL     = 8'h00;
    localparam [7:0] APB_STATUS   = 8'h04;
    localparam [7:0] APB_TX_DATA  = 8'h08;
    localparam [7:0] APB_RX_DATA  = 8'h0C;
    localparam [7:0] APB_CLK_DIV  = 8'h10;
    localparam [7:0] APB_SS_CTRL  = 8'h14;
    localparam [7:0] APB_INT_EN   = 8'h18;

    static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);
        spi_txn      txn;
        logic [31:0] rd;
        logic [31:0] ctrl_val;

        $display("[INFO] loopback_test: starting");

        // Loop across all 3 widths (0=8-bit, 1=16-bit, 2=32-bit)
        for (int w = 0; w < 3; w++) begin
            txn = new();
            
            // 1. Constrain transaction: Force Loopback=1, varying widths, and garbage MISO
            if (!txn.randomize() with {
                width     == w;
                loopback  == 1'b1;              // Force loopback mode
                tx_data   == 32'h1234_5678;     // Distinct recognizable TX pattern
                miso_data == 32'hBAD_C0DE;      // Garbage data on external MISO line!
                clk_div   inside {[2:4]};
                delay     == 8'd0;
                ss_en     == 4'b0001;
                ss_val    == 4'b0000;
            }) begin
                $display("[TEST_FAILED] loopback_test errors=1 (Randomization failed)");
                ref_model.error_count++;
                return;
            end

            $display("[INFO] loopback_test: Testing Width=%0d (0=8b, 1=16b, 2=32b) with LOOPBACK=1", txn.width);

            // 2. Configure BFM to drive the garbage MISO data
            tb_top.bfm_mode      = txn.mode;
            tb_top.bfm_width     = txn.width;
            tb_top.bfm_lsb_first = txn.lsb_first;
            tb_top.bfm_miso_data = txn.miso_data;

            // 3. APB Configuration
            tb_top.u_apb_bfm.apb_write(APB_CLK_DIV, {16'h0, txn.clk_div});
            tb_top.u_apb_bfm.apb_write(APB_INT_EN,  32'h0000_0000); // Mute interrupts
            
            ctrl_val = {24'h0, txn.width, txn.loopback, txn.lsb_first, txn.mode, 1'b1, 1'b1};
            tb_top.u_apb_bfm.apb_write(APB_CTRL, ctrl_val);

            // Sample Coverage
            coverage.sample_config(txn.mode, txn.width, txn.lsb_first, txn.clk_div, txn.delay, txn.loopback);

            // 4. Assert Slave Select
            tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, {24'h0, txn.ss_val, txn.ss_en});

            // 5. Predict and Fire Transfer
            // Notice: We pass both tx_data and miso_data to the predictor. 
            // The ref_model will use 'loopback' to decide which one to keep!
            ref_model.predict_transfer(txn.tx_data, txn.miso_data, txn.loopback, txn.width);
            tb_top.u_apb_bfm.apb_write(APB_TX_DATA, txn.tx_data);

            // 6. Wait for completion
            tb_top.u_apb_bfm.wait_not_busy();

            // 7. Deassert Slave Select
            tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0000);

            // 8. Pop RX_DATA and verify
            tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);
            ref_model.check_rx(rd);

            // Stop the test early if the scoreboard catches a mismatch
            if (ref_model.error_count > 0) begin
                $display("[INFO] loopback_test: Aborting loop due to scoreboard error.");
                return;
            end
            
            // Clean up state before the next width iteration
            tb_top.u_apb_bfm.apb_write(APB_CTRL, 32'h0000_0000);
        end

        $display("[INFO] loopback_test: finished, internal errors=%0d", ref_model.error_count);
    endtask

endclass

`endif // LOOPBACK_TEST_SV