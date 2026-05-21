// =============================================================================
// sanity_test.sv 
// -----------------------------------------------------------------------------
// Directed test: mode-0, MSB-first, 8-bit transfer, single byte, loopback off.
// Dispatched from tb_top via +TESTNAME=sanity_test.
// =============================================================================

`ifndef SANITY_TEST_SV
`define SANITY_TEST_SV


class sanity_test;

    // Localparam aliases for APB addresses
    localparam [7:0] APB_CTRL     = 8'h00;
    localparam [7:0] APB_STATUS   = 8'h04;
    localparam [7:0] APB_TX_DATA  = 8'h08;
    localparam [7:0] APB_RX_DATA  = 8'h0C;
    localparam [7:0] APB_CLK_DIV  = 8'h10;
    localparam [7:0] APB_SS_CTRL  = 8'h14;
    localparam [7:0] APB_INT_EN   = 8'h18;
    localparam [7:0] APB_INT_STAT = 8'h1C;
    localparam [7:0] APB_DELAY    = 8'h20;

    static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);
        spi_txn      txn;
        logic [31:0] rd;
        logic [31:0] ctrl_val;

        $display("[INFO] sanity_test: starting");

        txn = new();
        
        // 1. Constrain transaction exactly for Sanity Test requirements
        if (!txn.randomize() with {
            mode      == 2'b00;         // Mode 0
            width     == 2'b00;         // 8-bit transfer
            lsb_first == 1'b0;          // MSB-first
            loopback  == 1'b0;          // Normal mode (No loopback)
            ss_en     == 4'b0001;       // Enable SS_n[0]
            ss_val    == 4'b0000;       // Drive active-low
            tx_data   == 32'h0000_005A; // Payload
            miso_data == 32'h0000_00A5; // Expected BFM response
        }) begin
            $display("[TEST_FAILED] sanity_test errors=1 (Randomization failed)");
            ref_model.error_count++;
            return;
        end

        // 2. Configure Slave BFM via tb_top cross-module references
        tb_top.bfm_mode      = txn.mode;
        tb_top.bfm_width     = txn.width;
        tb_top.bfm_lsb_first = txn.lsb_first;
        tb_top.bfm_miso_data = txn.miso_data;

        // 3. APB Configuration Sequence
        tb_top.u_apb_bfm.apb_write(APB_CLK_DIV, {16'h0, txn.clk_div});
        tb_top.u_apb_bfm.apb_write(APB_INT_EN,  32'h0000_000F); // Enable basic interrupts
        
        // CTRL: EN=1, MSTR=1, MODE, LSB, LOOPBACK, WIDTH
        ctrl_val = {24'h0, txn.width, txn.loopback, txn.lsb_first, txn.mode, 1'b1, 1'b1};
        tb_top.u_apb_bfm.apb_write(APB_CTRL, ctrl_val);

        // Sample coverage
        coverage.sample_config(txn.mode, txn.width, txn.lsb_first, txn.clk_div, txn.delay, txn.loopback);

        // 4. Assert Slave Select
        tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, {24'h0, txn.ss_val, txn.ss_en});

        // 5. Predict and Fire Transfer
        ref_model.predict_transfer(.tx_data(txn.tx_data), .miso_data(txn.miso_data), .loopback(txn.loopback), .width(txn.width));
        tb_top.u_apb_bfm.apb_write(APB_TX_DATA, txn.tx_data);

        // 6. Wait for completion STATUS.BUSY bit (Bit 0)
        tb_top.u_apb_bfm.wait_not_busy();

        // 7. Deassert Slave Select
        tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0000);

        // 8. Pop RX_DATA and verify
        tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);
        ref_model.check_rx(.observed(rd));

        $display("[INFO] sanity_test: finished, errors=%0d", ref_model.error_count);
    endtask

endclass

`endif // SANITY_TEST_SV