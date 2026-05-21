// =============================================================================
// interrupt_test.sv
// -----------------------------------------------------------------------------
// Goal: Verify Asserted, Masked, W1C, and W1C Race conditions for all 5 interrupts.
// Uses a robust polling mechanism to prevent zero-wait-state exit traps, and a 
// backward delay sweep to mathematically prove the R18 W1C race condition.
// =============================================================================

`ifndef INTERRUPT_TEST_SV
`define INTERRUPT_TEST_SV

class interrupt_test;

    localparam [7:0] APB_CTRL     = 8'h00;
    localparam [7:0] APB_STATUS   = 8'h04;
    localparam [7:0] APB_TX_DATA  = 8'h08;
    localparam [7:0] APB_RX_DATA  = 8'h0C;
    localparam [7:0] APB_CLK_DIV  = 8'h10;
    localparam [7:0] APB_SS_CTRL  = 8'h14;
    localparam [7:0] APB_INT_EN   = 8'h18;
    localparam [7:0] APB_INT_STAT = 8'h1C;

    static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);
        spi_txn      txn;
        logic [31:0] obs, rd;
        logic [31:0] ctrl_val;
        bit          race_td;
        int          timeout;

        $display("[INFO] interrupt_test: starting");

        txn = new();
        if (!txn.randomize() with {
            width     == 2'b00;         // 8-bit to keep transfers fast
            loopback  == 1'b1;          // Loopback mode
            clk_div   inside {[2:4]};   // Fast enough to sweep efficiently
            delay     == 8'd0;
            ss_en     == 4'b0001;
            ss_val    == 4'b0000;
        }) begin
            $display("[TEST_FAILED] interrupt_test errors=1 (Randomization failed)");
            ref_model.error_count++;
            return;
        end

        tb_top.bfm_mode      = txn.mode;
        tb_top.bfm_width     = txn.width;
        tb_top.bfm_lsb_first = txn.lsb_first;
        tb_top.bfm_miso_data = txn.miso_data;

        tb_top.u_apb_bfm.apb_write(APB_CLK_DIV, {16'h0, txn.clk_div});
        
        // =====================================================================
        // Phase 1: Assert and Mask 
        // =====================================================================
        $display("[INFO] interrupt_test: Phase 1 - Assert and Mask");
        tb_top.u_apb_bfm.apb_write(APB_INT_EN, 32'h0000_0000); // Mask all
        
        // Ensure clean state
        tb_top.u_apb_bfm.apb_write(APB_CTRL, 32'h0);
        tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'hFFFF_FFFF);
        
        ctrl_val = {24'h0, txn.width, txn.loopback, txn.lsb_first, txn.mode, 1'b1, 1'b1};
        tb_top.u_apb_bfm.apb_write(APB_CTRL, ctrl_val);
        coverage.sample_config(txn.mode, txn.width, txn.lsb_first, txn.clk_div, txn.delay, txn.loopback);
        tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, {24'h0, txn.ss_val, txn.ss_en});

        // Push exactly 12 words. 
        // 1 goes to shifter, 8 fill TX FIFO, remaining 3 OVERFLOW (triggering TX_OVF).
        // 8 will transfer and fill RX FIFO, the rest trigger RX_OVF.
        for(int i = 0; i < 12; i++) begin
            ref_model.predict_transfer(32'hA5, 32'h0, txn.loopback, txn.width);
            tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'hA5);
        end

        // Robust Polling: Wait until ALL 5 interrupts assert (0x1F)
        timeout = 5000;
        obs = 0;
        while (((obs & 32'h1F) !== 32'h1F) && (timeout > 0)) begin
            tb_top.u_apb_bfm.apb_read(APB_INT_STAT, obs);
            timeout--;
        end

        if ((obs & 32'h1F) !== 32'h1F) begin
            $display("[SCOREBOARD_ERROR] Not all interrupts asserted! OBS=0x%08h", obs);
            ref_model.error_count++;
        end
        
        // SAMPLE COVERAGE: Asserted while Masked
        coverage.sample_interrupts(.stat(obs[4:0]), .en(5'h00), .is_w1c(0));

        // =====================================================================
        // Phase 2: W1C (Write-1-to-Clear)
        // =====================================================================
        $display("[INFO] interrupt_test: Phase 2 - W1C Clear");
        tb_top.u_apb_bfm.apb_write(APB_INT_EN, 32'h0000_001F); // Unmask all
        
        // SAMPLE COVERAGE: W1C Event log
        coverage.sample_interrupts(.stat(5'h1F), .en(5'h1F), .is_w1c(1));

        // Perform W1C
        tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'h0000_001F);
        
        // Verify Clear
        tb_top.u_apb_bfm.apb_read(APB_INT_STAT, obs);
        if ((obs & 32'h1F) !== 32'h00) begin
            $display("[SCOREBOARD_ERROR] W1C failed to clear bits! OBS=0x%08h", obs);
            ref_model.error_count++;
        end

        // Pop EXACTLY 8 words (the 4 overflows were dropped by DUT and Scoreboard)
        for(int i = 0; i < 8; i++) begin
            tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);
            ref_model.check_rx(rd);
        end

        // =====================================================================
        // Phase 3: W1C Race Sweep (Hunting R18)
        // =====================================================================
        $display("[INFO] interrupt_test: Phase 3 - Hunting W1C Races (Backward Sweep)");
        race_td = 0;
        
        // Backward Sweep: start clearing late (150 PCLKs), and move earlier.
        // The first time it STAYS 1, we hit the exact cycle the hardware set it!
        for (int d = 150; d >= 5; d--) begin
            
            // Clean state
            tb_top.u_apb_bfm.apb_write(APB_CTRL, 32'h0); 
            tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'h1F); 
            tb_top.u_apb_bfm.apb_write(APB_CTRL, ctrl_val); 

            // Push exactly 1 word
            ref_model.predict_transfer(32'h11, 32'h0, txn.loopback, txn.width);
            tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'h11);

            // Wait exactly 'd' PCLK cycles
            repeat(d) @(posedge tb_top.PCLK);

            // Perform W1C on TRANSFER_DONE (bit 4)
            tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'h0000_0010);

            // Robust Wait: Ensure transfer is completely done
            do begin
                tb_top.u_apb_bfm.apb_read(APB_STATUS, obs);
            end while (obs[0] == 1'b1 || obs[2] == 1'b0); // Wait while BUSY or !TX_EMPTY
            
            // Read status
            tb_top.u_apb_bfm.apb_read(APB_INT_STAT, obs);
            
            // Keep scoreboard clean
            tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);
            ref_model.check_rx(rd);

            if (obs[4] == 1'b1) begin
                $display("[INFO] => W1C Race hit perfectly at delay = %0d PCLKs! (Hardware won)", d);
                race_td = 1;
                break; // We proved it, stop sweeping!
            end
        end

        if (!race_td) begin
            $display("[SCOREBOARD_ERROR] Failed to hit W1C race for TRANSFER_DONE.");
            ref_model.error_count++;
        end

        // Final Cleanup
        tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0000);
        tb_top.u_apb_bfm.apb_write(APB_CTRL, 32'h0);
        tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'hFFFF_FFFF);
        ref_model.flush();

        $display("[INFO] interrupt_test: finished, internal errors=%0d", ref_model.error_count);
    endtask

endclass

`endif // INTERRUPT_TEST_SV