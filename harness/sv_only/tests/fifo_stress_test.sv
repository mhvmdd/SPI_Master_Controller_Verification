// =============================================================================
// fifo_stress_test.sv
// -----------------------------------------------------------------------------
// Goal: Verify the 8-deep TX and RX FIFOs and their occupancy bins (1, 4, 7, 8).
// Bursts 9 words to hit TX_FULL and trigger an RX_OVF, then pops them out.
// =============================================================================

`ifndef FIFO_STRESS_TEST_SV
`define FIFO_STRESS_TEST_SV

class fifo_stress_test;

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
        logic [31:0] status_val;
        logic [31:0] int_stat_val;

        $display("[INFO] fifo_stress_test: starting");

        txn = new();
        if (!txn.randomize() with {
            width     == 2'b10;         // 32-bit
            loopback  == 1'b1;          // Loopback mode so we don't need BFM data
            clk_div   == 16'd10;        // Slow enough to burst 9 words before 1 shifts out
            delay     == 8'd0;
            ss_en     == 4'b0001;       
        }) begin
            $display("[TEST_FAILED] Randomization failed");
            ref_model.error_count++;
            return;
        end

        // 1. APB Configuration
        tb_top.u_apb_bfm.apb_write(APB_CLK_DIV, {16'h0, txn.clk_div});
        tb_top.u_apb_bfm.apb_write(APB_INT_EN,  32'h0000_001F); // Enable all interrupts
        
        ctrl_val = {24'h0, txn.width, txn.loopback, txn.lsb_first, txn.mode, 1'b1, 1'b1};
        tb_top.u_apb_bfm.apb_write(APB_CTRL, ctrl_val);
        tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, {24'h0, txn.ss_val, txn.ss_en});

        $display("[INFO] fifo_stress_test: Bursting 9 words to fill shifter (1) and TX FIFO (8)");

        // We push expected values to scoreboard. (Scoreboard automatically drops the 9th)
        for (int i = 0; i < 9; i++) begin
            ref_model.predict_transfer(32'hAAAA_0000 + i, 32'h0, txn.loopback, txn.width);
        end

        // 1. Sample initial state of FIFOs (TX=0, RX=0)
        coverage.sample_fifo(tb_top.u_wrap.u_dut.u_regfile.tx_count, tb_top.u_wrap.u_dut.u_regfile.rx_count);

        // 2. Burst 2 words (1 goes to shifter, 1 stays in FIFO). Sample TX = 1
        tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'hAAAA_0000);
        tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'hAAAA_0001);
        coverage.sample_fifo(tb_top.u_wrap.u_dut.u_regfile.tx_count, tb_top.u_wrap.u_dut.u_regfile.rx_count);

        // 3. Burst 3 words. Sample TX = 4
        tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'hAAAA_0002);
        tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'hAAAA_0003);
        tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'hAAAA_0004);
        coverage.sample_fifo(tb_top.u_wrap.u_dut.u_regfile.tx_count, tb_top.u_wrap.u_dut.u_regfile.rx_count);

        // 4. Burst 3 words. Sample TX = 7
        tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'hAAAA_0005);
        tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'hAAAA_0006);
        tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'hAAAA_0007);
        coverage.sample_fifo(tb_top.u_wrap.u_dut.u_regfile.tx_count, tb_top.u_wrap.u_dut.u_regfile.rx_count);

        // 5. Burst 1 word. Sample TX = 8 (FULL)
        tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'hAAAA_0008);
        coverage.sample_fifo(tb_top.u_wrap.u_dut.u_regfile.tx_count, tb_top.u_wrap.u_dut.u_regfile.rx_count);

        // Verify TX_FULL in STATUS (Bit 1)
        tb_top.u_apb_bfm.apb_read(APB_STATUS, status_val);
        if ((status_val & 32'h0000_0002) == 0) begin
            $display("[SCOREBOARD_ERROR] TX_FULL (bit 1) not asserted! STATUS=0x%08h", status_val);
            ref_model.error_count++;
        end

        $display("[INFO] fifo_stress_test: Waiting for all 9 transfers to process...");
        tb_top.u_apb_bfm.wait_not_busy();
        tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0000);

        // 6. Verify RX_FULL (Bit 3) and RX_OVF (Bit 3 in INT_STAT)
        tb_top.u_apb_bfm.apb_read(APB_STATUS, status_val);
        tb_top.u_apb_bfm.apb_read(APB_INT_STAT, int_stat_val);
        
        if ((status_val & 32'h0000_0008) == 0) begin
            $display("[SCOREBOARD_ERROR] RX_FULL (bit 3) not asserted! STATUS=0x%08h", status_val);
            ref_model.error_count++;
        end
        if ((int_stat_val & 32'h0000_0008) == 0) begin
            $display("[SCOREBOARD_ERROR] RX_OVF interrupt (bit 3) not asserted after 9th word! INT_STAT=0x%08h", int_stat_val);
            ref_model.error_count++;
        end

        $display("[INFO] fifo_stress_test: Popping words from RX FIFO to hit occupancy bins...");

        // Sample RX = 8 (FULL) , TX = 0 (EMPTY)
        coverage.sample_fifo(tb_top.u_wrap.u_dut.u_regfile.tx_count, tb_top.u_wrap.u_dut.u_regfile.rx_count);

        // 7. Pop 1 word. Sample RX = 7
        tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);
        ref_model.check_rx(rd);
        coverage.sample_fifo(tb_top.u_wrap.u_dut.u_regfile.tx_count, tb_top.u_wrap.u_dut.u_regfile.rx_count);

        // 8. Pop 3 words. Sample RX = 4
        for (int i=0; i<3; i++) begin tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd); ref_model.check_rx(rd); end
        coverage.sample_fifo(tb_top.u_wrap.u_dut.u_regfile.tx_count, tb_top.u_wrap.u_dut.u_regfile.rx_count);

        // 9. Pop 3 words. Sample RX = 1
        for (int i=0; i<3; i++) begin tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd); ref_model.check_rx(rd); end
        coverage.sample_fifo(tb_top.u_wrap.u_dut.u_regfile.tx_count, tb_top.u_wrap.u_dut.u_regfile.rx_count);

        // 10. Pop final word. Sample RX = 0 (EMPTY)
        tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);
        ref_model.check_rx(rd);
        coverage.sample_fifo(tb_top.u_wrap.u_dut.u_regfile.tx_count, tb_top.u_wrap.u_dut.u_regfile.rx_count);

        // Clear all sticky interrupts (W1C)
        tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'hFFFF_FFFF);

        $display("[INFO] fifo_stress_test: finished, internal errors=%0d", ref_model.error_count);
    endtask

endclass

`endif // FIFO_STRESS_TEST_SV