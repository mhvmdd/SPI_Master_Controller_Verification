// =============================================================================
// width_coverage_test.sv
// -----------------------------------------------------------------------------
// Goal: Verify data masking and zero-filling for 8-bit, 16-bit, and 32-bit 
// transfers across both Normal and Loopback modes.
// Injects 32-bit wide noise (DEADBEEF / CAFEF00D) to ensure upper bits are ignored.
// =============================================================================

`ifndef WIDTH_COVERAGE_TEST_SV
`define WIDTH_COVERAGE_TEST_SV

class width_coverage_test;

    // Localparams safely inside the class
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

        $display("[INFO] width_coverage_test: starting");

        // Loop through the 3 valid Widths (0=8b, 1=16b, 2=32b)
        for (int w = 0; w < 3; w++) begin
            
            // Test both Normal (0) and Loopback (1) for each width
            for (int lb = 0; lb < 2; lb++) begin
                txn = new();
                
                // Constrain transaction: Force 32-bit garbage data to test truncation
                if (!txn.randomize() with {
                    width     == w;
                    loopback  == lb;
                    tx_data   == 32'hDEAD_BEEF; 
                    miso_data == 32'hCAFE_F00D; 
                    clk_div   inside {[0:4]}; // Keep it fast to prevent timeouts
                    delay     == 0;
                    ss_en     == 4'b0001;       
                    ss_val    == 4'b0000;       
                }) begin
                    $display("[TEST_FAILED] width_coverage_test errors=1 (Randomization failed)");
                    ref_model.error_count++;
                    return;
                end

                $display("[INFO] width_coverage_test: Width=%0d (0=8b,1=16b,2=32b), Loopback=%0d", 
                         txn.width, txn.loopback);

                // 1. Configure BFM
                tb_top.bfm_mode      = txn.mode;
                tb_top.bfm_width     = txn.width;
                tb_top.bfm_lsb_first = txn.lsb_first;
                tb_top.bfm_miso_data = txn.miso_data;

                // 2. APB Configuration
                tb_top.u_apb_bfm.apb_write(APB_CLK_DIV, {16'h0, txn.clk_div});
                tb_top.u_apb_bfm.apb_write(APB_DELAY,   {24'h0, txn.delay});
                
                ctrl_val = {24'h0, txn.width, txn.loopback, txn.lsb_first, txn.mode, 1'b1, 1'b1};
                tb_top.u_apb_bfm.apb_write(APB_CTRL, ctrl_val);

                // Sample Configuration Coverage
                coverage.sample_config(
                    .mode(txn.mode), 
                    .width(txn.width), 
                    .lsb_first(txn.lsb_first), 
                    .clk_div(txn.clk_div), 
                    .delay(txn.delay), 
                    .loopback(txn.loopback)
                );

                // 3. Assert SS_n
                tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, {24'h0, txn.ss_val, txn.ss_en});

                // 4. Predict and Fire 
                ref_model.predict_transfer(txn.tx_data, txn.miso_data, txn.loopback, txn.width);
                tb_top.u_apb_bfm.apb_write(APB_TX_DATA, txn.tx_data);

                // 5. Wait for completion
                tb_top.u_apb_bfm.wait_not_busy();

                // 6. Deassert SS_n
                tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0000);

                // 7. Verify Truncation
                tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);
                ref_model.check_rx(rd);

                if (ref_model.error_count > 0) begin
                    $display("[INFO] width_coverage_test: Aborting due to scoreboard error.");
                    return;
                end
            end
        end

        $display("[INFO] width_coverage_test: finished, internal errors=%0d", ref_model.error_count);
    endtask

endclass

`endif // WIDTH_COVERAGE_TEST_SV