// =============================================================================
// delay_transfer_test.sv
// -----------------------------------------------------------------------------
// Goal: Verify Requirement R21 (Inter-transfer Delay).
// Measures the exact nanosecond gap between SCLK pulses of consecutive words.
// Uses a baseline-delta approach to mathematically prove exactly N half-cycles
// of SCLK were inserted. Implicitly verifies BUSY remains 1 throughout.
// =============================================================================

`ifndef DELAY_TRANSFER_TEST_SV
`define DELAY_TRANSFER_TEST_SV

class delay_transfer_test;

    localparam [7:0] APB_CTRL     = 8'h00;
    localparam [7:0] APB_STATUS   = 8'h04;
    localparam [7:0] APB_TX_DATA  = 8'h08;
    localparam [7:0] APB_RX_DATA  = 8'h0C;
    localparam [7:0] APB_CLK_DIV  = 8'h10;
    localparam [7:0] APB_SS_CTRL  = 8'h14;
    localparam [7:0] APB_INT_EN   = 8'h18;
    localparam [7:0] APB_DELAY    = 8'h20;

    // Measures the exact nanosecond gap between the last edge of word 1 and first edge of word 2
    static task measure_gap(input int width_bits, output time gap);
        time t1, t2;
        int edges_per_word = width_bits * 2;

        // Wait for all SCLK edges of the FIRST word to complete
        for(int i = 0; i < edges_per_word; i++) @(tb_top.spi.sclk);
        t1 = $time; // Record time of the very last edge of word 1

        // Wait for the FIRST SCLK edge of the SECOND word
        @(tb_top.spi.sclk);
        t2 = $time; // Record time of the very first edge of word 2
        
        gap = t2 - t1;

        // Consume the remaining edges of the SECOND word so the task finishes cleanly
        for(int i = 1; i < edges_per_word; i++) @(tb_top.spi.sclk);
    endtask

    static task run(ref spi_ref_model ref_model, ref spi_coverage_col coverage);
        spi_txn      txn;
        logic [31:0] rd;
        logic [31:0] ctrl_val;
        
        // Exact bins required by Coverage Spec 10.1: 0, 1, large (>= 128)
        int test_delays[] = '{0, 1, 5, 128, 255};
        time base_gap = 0;
        time current_gap = 0;
        time half_sclk_ns;

        $display("[INFO] delay_transfer_test: starting");

        foreach (test_delays[i]) begin
            txn = new();
            if (!txn.randomize() with {
                width     == 2'b00;         // 8-bit to keep edges predictable
                loopback  == 1'b1;          // Loopback to isolate the test
                clk_div   == 16'd4;         // DIV=4. PCLK=10ns -> half SCLK = 50ns
                delay     == test_delays[i];
                ss_en     == 4'b0001;       
                ss_val    == 4'b0000;       
            }) begin
                $display("[TEST_FAILED] delay_transfer_test errors=1 (Randomization failed)");
                ref_model.error_count++;
                return;
            end

            // Calculate the exact mathematical length of one SCLK half-cycle
            half_sclk_ns = (txn.clk_div + 1) * 10; 

            $display("[INFO] delay_transfer_test: Testing DELAY = %0d", txn.delay);

            tb_top.bfm_mode      = txn.mode;
            tb_top.bfm_width     = txn.width;
            tb_top.bfm_lsb_first = txn.lsb_first;
            
            tb_top.u_apb_bfm.apb_write(APB_CLK_DIV, {16'h0, txn.clk_div});
            tb_top.u_apb_bfm.apb_write(APB_DELAY,   {24'h0, txn.delay});
            tb_top.u_apb_bfm.apb_write(APB_INT_EN,  32'h0000_0000); 
            
            ctrl_val = {24'h0, txn.width, txn.loopback, txn.lsb_first, txn.mode, 1'b1, 1'b1};
            tb_top.u_apb_bfm.apb_write(APB_CTRL, ctrl_val);

            // Sample DELAY coverage bins
            coverage.sample_config(txn.mode, txn.width, txn.lsb_first, txn.clk_div, txn.delay, txn.loopback);
            tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, {24'h0, txn.ss_val, txn.ss_en});

            // Fork two parallel threads: one to push data, one to measure SCLK
            fork
                begin
                    // Delay push by 1 cycle to ensure measure_gap is fully armed and waiting
                    @(posedge tb_top.PCLK); 
                    ref_model.predict_transfer(32'h11, 32'h0, txn.loopback, txn.width);
                    ref_model.predict_transfer(32'h22, 32'h0, txn.loopback, txn.width);
                    
                    tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'h11);
                    tb_top.u_apb_bfm.apb_write(APB_TX_DATA, 32'h22);
                    
                    // If BUSY drops incorrectly during the delay, this exits too early!
                    tb_top.u_apb_bfm.wait_not_busy();
                end
                begin
                    // Listen to the SCLK wire and measure the gap
                    measure_gap(8, current_gap);
                end
            join

            tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'h0000_0000);

            // Pop both words out. If BUSY dropped early, the 2nd word won't be here, causing a failure!
            tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);
            ref_model.check_rx(rd);
            tb_top.u_apb_bfm.apb_read(APB_RX_DATA, rd);
            ref_model.check_rx(rd);

            // Mathematics Check
            if (test_delays[i] == 0) begin
                base_gap = current_gap;
            end else begin
                time expected_diff = test_delays[i] * half_sclk_ns;
                
                if ((current_gap - base_gap) !== expected_diff) begin
                    $display("[SCOREBOARD_ERROR] Delay mismatch! DELAY=%0d. BaseGap=%0dt, CurrGap=%0dt, Diff=%0dt, ExpectedDiff=%0dt", 
                             test_delays[i], base_gap, current_gap, (current_gap - base_gap), expected_diff);
                    ref_model.error_count++;
                end else begin
                    $display("       -> Gap perfectly matched: +%0dt added to base gap.", expected_diff);
                end
            end
            
            if (ref_model.error_count > 0) return;
            tb_top.u_apb_bfm.apb_write(APB_CTRL, 32'h0000_0000); // Flush state before next run
        end

        $display("[INFO] delay_transfer_test: finished, internal errors=%0d", ref_model.error_count);
    endtask

endclass

`endif // DELAY_TRANSFER_TEST_SV