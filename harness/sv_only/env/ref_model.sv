// =============================================================================
// ref_model.sv
// -----------------------------------------------------------------------------
// Extended plain-SV reference model + scoreboard.
// Accurately models the 8-deep RX FIFO, 8/16/32-bit transfer masking, and 
// internal loopback routing per the SPI Master Specification.
// =============================================================================

`ifndef SPI_REF_MODEL_SV
`define SPI_REF_MODEL_SV

class spi_ref_model;

    // Running error count. tb_top reads this to emit the final PASS/FAIL line.
    int error_count = 0;

    // Predictor queue modeling the 8-deep RX FIFO
    bit [31:0] pred_q[$];

    function new();
        error_count = 0;
        pred_q.delete();
    endfunction

    // -------------------------------------------------------------------------
    // Predictor Logic
    // -------------------------------------------------------------------------
    // Call this task right before (or just as) a transfer begins to queue 
    // the expected result into the scoreboard.
    task predict_transfer(input bit [31:0] tx_data,
                          input bit [31:0] miso_data,
                          input bit        loopback,
                          input bit [1:0]  width);
        bit [31:0] expected_word;
        bit [31:0] mask;

        // 1. Determine valid bits mask based on CTRL.WIDTH
        case (width)
            2'b00: mask = 32'h0000_00FF; // 8-bit
            2'b01: mask = 32'h0000_FFFF; // 16-bit
            2'b10: mask = 32'hFFFF_FFFF; // 32-bit
            default: mask = 32'h0000_00FF;
        endcase

        // 2. Resolve data source (Spec R19: Loopback ignores MISO)
        if (loopback) begin
            expected_word = tx_data & mask;
        end else begin
            expected_word = miso_data & mask;
        end

        // 3. Push to queue (Spec R12: RX FIFO is 8 deep)
        if (pred_q.size() < 8) begin
            pred_q.push_back(expected_word);
        end else begin
            // In reality, the DUT sets RX_OVF and discards. The predictor 
            // drops it too to stay in lock-step with the DUT's FIFO.
            $display("[INFO] Predictor RX FIFO full, dropping word 0x%08h", expected_word);
        end
    endtask

    // -------------------------------------------------------------------------
    // Scoreboard Checks
    // -------------------------------------------------------------------------
    // Call this task with the value returned from an APB read to RX_DATA
    task check_rx(input bit [31:0] observed);
        bit [31:0] expected;

        if (pred_q.size() == 0) begin
            // Spec R15: RX read when empty returns 0. 
            if (observed !== 32'h0) begin
                $display("[SCOREBOARD_ERROR] Empty RX read returned 0x%08h instead of 0x00000000", observed);
                error_count++;
            end
            return;
        end

        expected = pred_q.pop_front();

        if (observed !== expected) begin
            $display("[SCOREBOARD_ERROR] RX data mismatch: expected=0x%08h observed=0x%08h",
                     expected, observed);
            error_count++;
        end
    endtask

    // Utility check for register values (used heavily in reg_access_test)
    task check_reg(input string name,
                   input bit [31:0] expected,
                   input bit [31:0] observed);
        if (observed !== expected) begin
            $display("[SCOREBOARD_ERROR] %s mismatch: expected=0x%08h observed=0x%08h",
                     name, expected, observed);
            error_count++;
        end
    endtask

    // -------------------------------------------------------------------------
    // Utilities
    // -------------------------------------------------------------------------
    // Call this if CTRL.EN transitions 1->0 to mimic DUT FIFO flush
    task flush();
        pred_q.delete();
    endtask

endclass

`endif // SPI_REF_MODEL_SV