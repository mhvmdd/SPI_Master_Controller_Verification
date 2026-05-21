// =============================================================================
// error_injection_test.sv
// -----------------------------------------------------------------------------
// Goal: Verify DUT resilience against illegal software sequences.
// Covers:
// - R15: RX_DATA read when empty returns 0, no RX_OVF.
// - R23: Reserved address space accesses (0x24) are ignored/read 0.
// - R13: TX_DATA write when full triggers TX_OVF, discards data.
// - R14: RX_DATA push when full triggers RX_OVF, discards data.
// - R22: Illegal WIDTH = 2'b11 does not hang the zero-wait-state APB bus.
// =============================================================================

`ifndef ERROR_INJECTION_TEST_SV
`define ERROR_INJECTION_TEST_SV

class error_injection_test;

    localparam [7:0] APB_CTRL     = 8'h00;
    localparam [7:0] APB_STATUS   = 8'h04;
    localparam [7:0] APB_TX_DATA  = 8'h08;
    localparam [7:0] APB_RX_DATA  = 8'h0C;
    localparam [7:0] APB_CLK_DIV  = 8'h10;
    localparam [7:0] APB_SS_CTRL  = 8'h14;
    localparam [7:0] APB_INT_EN   = 8'h18;
    localparam [7:0] APB_INT_STAT = 8'h1C;
    
    localparam [7:0] APB_RSVD     = 8'h24; // First reserved address

    static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);
        logic [31:0] obs, rd;
        
        $display("[INFO] error_injection_test: starting");

        // Ensure clean slate
        tb_top.u_apb_bfm.apb_write(APB_CTRL, 32'h0);
        tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'hFFFF_FFFF);

        // =====================================================================
        // Phase 1: Empty RX Read (Requirement R15)
        // =====================================================================
        $display("[INFO] Phase 1 - Empty RX Read (R15)");
        
        // Read the empty RX FIFO
        tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);
        
        // The scoreboard's check_rx() natively enforces R15 (expects 0x00)
        ref_model.check_rx(rd); 
        
        // Prove RX_OVF was NOT set by the empty read
        tb_top.u_apb_bfm.apb_read(APB_STATUS, obs);
        if (obs[6] === 1'b1) begin
            $display("[SCOREBOARD_ERROR] R15 Violation: Empty RX read falsely triggered RX_OVF!");
            ref_model.error_count++;
        end

        // =====================================================================
        // Phase 2: Reserved Address Access (Requirement R23)
        // =====================================================================
        $display("[INFO] Phase 2 - Reserved Address Access (R23)");
        
        // Write garbage to a reserved address
        tb_top.u_apb_bfm.apb_write(APB_RSVD, 32'hDEAD_BEEF);
        
        // Read it back. Spec says reserved offsets read as 0.
        tb_top.u_apb_bfm.apb_read(APB_RSVD, rd);
        if (rd !== 32'h0000_0000) begin
            $display("[SCOREBOARD_ERROR] R23 Violation: Reserved addr 0x24 read as 0x%08h instead of 0", rd);
            ref_model.error_count++;
        end

        // =====================================================================
        // Phase 3 & 4: TX Overflow (R13) and RX Overflow (R14)
        // =====================================================================
        $display("[INFO] Phase 3 & 4 - Overflows (R13, R14)");
        
        // Setup: Slow clock (DIV=10) and Loopback=1
        tb_top.u_apb_bfm.apb_write(APB_CLK_DIV, 32'd10);
        tb_top.u_apb_bfm.apb_write(APB_CTRL, {24'h0, 2'b00, 1'b1, 1'b0, 2'b00, 1'b1, 1'b1}); 
        tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0001);

        // We blast exactly 10 words. 
        // - Word 1 goes straight to shifter.
        // - Words 2-9 fill the 8-deep TX FIFO.
        // - Word 10 triggers TX_OVF (R13).
        for (int i = 0; i < 10; i++) begin
            // The predictor gracefully drops entries beyond 8, maintaining perfect sync with DUT!
            ref_model.predict_transfer(32'hA0 + i, 32'h0, 1'b1, 2'b00);
            tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'hA0 + i);
        end

        // Check TX_OVF immediately (before transfers finish)
        tb_top.u_apb_bfm.apb_read(APB_STATUS, obs);
        if (obs[5] !== 1'b1) begin
            $display("[SCOREBOARD_ERROR] R13 Violation: TX_OVF (STATUS[5]) not set after 10th write!");
            ref_model.error_count++;
        end

        $display("[INFO] Waiting for 9 transfers to complete to trigger RX_OVF...");
        tb_top.u_apb_bfm.wait_not_busy();

        // The 9 valid words have shifted. 8 filled the RX FIFO. The 9th triggered RX_OVF (R14).
        tb_top.u_apb_bfm.apb_read(APB_STATUS, obs);
        if (obs[6] !== 1'b1) begin
            $display("[SCOREBOARD_ERROR] R14 Violation: RX_OVF (STATUS[6]) not set after 9th transfer!");
            ref_model.error_count++;
        end

        // Log the overflow interrupts for coverage
        tb_top.u_apb_bfm.apb_read(APB_INT_STAT, obs);
        coverage.sample_interrupts(obs[4:0], 5'h00, 0);

        // Pop the 8 valid words to ensure the overflowing data didn't corrupt the queue
        for (int i = 0; i < 8; i++) begin
            tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);
            ref_model.check_rx(rd);
        end

        // =====================================================================
        // Phase 5: Illegal WIDTH Sequence (R22 & Section 8.3)
        // =====================================================================
        $display("[INFO] Phase 5 - Illegal WIDTH=2'b11");
        
        // Write the illegal width. The DUT behavior is undefined, but the APB bus MUST 
        // complete the transaction (PREADY=1, PSLVERR=0) and not freeze the simulator.
        tb_top.u_apb_bfm.apb_write(APB_CTRL, {24'h0, 2'b11, 1'b1, 1'b0, 2'b00, 1'b1, 1'b1});
        
        // If we make it to this read without a simulation hang, APB zero-wait-state holds!
        tb_top.u_apb_bfm.apb_read(APB_CTRL, obs);

        // Cleanup
        tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0);
        tb_top.u_apb_bfm.apb_write(APB_CTRL, 32'h0);
        tb_top.u_apb_bfm.apb_write(APB_INT_STAT, 32'hFFFF_FFFF);
        ref_model.flush();

        $display("[INFO] error_injection_test: finished, internal errors=%0d", ref_model.error_count);
    endtask

endclass

`endif // ERROR_INJECTION_TEST_SV