// =============================================================================
// reg_access_test.sv
// -----------------------------------------------------------------------------
// Goal: Verify reset values and R/W capabilities for all 9 registers, plus 
// reserved offsets, per Spec Requirements R1, R2, and R23.
// =============================================================================

`ifndef REG_ACCESS_TEST_SV
`define REG_ACCESS_TEST_SV


class reg_access_test;

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
        logic [31:0]  obs_val;

        $display("[INFO] reg_access_test: starting");

        // ---------------------------------------------------------------------
        // Phase 1: Check Reset Values (Spec R2)
        // ---------------------------------------------------------------------
        tb_top.u_apb_bfm.apb_read(APB_CTRL, obs_val);
        ref_model.check_reg("CTRL_RESET", 32'h0000_0000, obs_val);
        coverage.sample_reg_access(.addr(APB_CTRL), .is_write(0), .is_reset_check(1));

        tb_top.u_apb_bfm.apb_read(APB_STATUS, obs_val);
        // Spec 3.2: TX_EMPTY(bit 2) and RX_EMPTY(bit 4) = 1. Hex: 0x14
        ref_model.check_reg("STATUS_RESET", 32'h0000_0014, obs_val);
        coverage.sample_reg_access(.addr(APB_STATUS), .is_write(0), .is_reset_check(1));

        tb_top.u_apb_bfm.apb_read(APB_TX_DATA, obs_val);
        ref_model.check_reg("TX_DATA_RESET", 32'h0000_0000, obs_val); // WO reads 0
        coverage.sample_reg_access(.addr(APB_TX_DATA), .is_write(0), .is_reset_check(1));

        tb_top.u_apb_bfm.apb_read(APB_RX_DATA, obs_val);
        ref_model.check_reg("RX_DATA_RESET", 32'h0000_0000, obs_val); // Empty FIFO returns 0
        coverage.sample_reg_access(.addr(APB_RX_DATA), .is_write(0), .is_reset_check(1));

        tb_top.u_apb_bfm.apb_read(APB_CLK_DIV, obs_val);
        ref_model.check_reg("CLK_DIV_RESET", 32'h0000_0000, obs_val);
        coverage.sample_reg_access(.addr(APB_CLK_DIV), .is_write(0), .is_reset_check(1));

        tb_top.u_apb_bfm.apb_read(APB_SS_CTRL, obs_val);
        ref_model.check_reg("SS_CTRL_RESET", 32'h0000_0000, obs_val);
        coverage.sample_reg_access(.addr(APB_SS_CTRL), .is_write(0), .is_reset_check(1));

        tb_top.u_apb_bfm.apb_read(APB_INT_EN, obs_val);
        ref_model.check_reg("INT_EN_RESET", 32'h0000_0000, obs_val);
        coverage.sample_reg_access(.addr(APB_INT_EN), .is_write(0), .is_reset_check(1));

        tb_top.u_apb_bfm.apb_read(APB_INT_STAT, obs_val);
        ref_model.check_reg("INT_STAT_RESET", 32'h0000_0000, obs_val);
        coverage.sample_reg_access(.addr(APB_INT_STAT), .is_write(0), .is_reset_check(1));

        tb_top.u_apb_bfm.apb_read(APB_DELAY, obs_val);
        ref_model.check_reg("DELAY_RESET", 32'h0000_0000, obs_val);
        coverage.sample_reg_access(.addr(APB_DELAY), .is_write(0), .is_reset_check(1));

        // ---------------------------------------------------------------------
        // Phase 2: Write/Read verification (Spec R1 & R23)
        // ---------------------------------------------------------------------
        // Write all 1s (0xFFFFFFFF) to check which bits are actually writable.
        // Unused upper bits MUST read back as 0.

        // CTRL (8 bits active)
        tb_top.u_apb_bfm.apb_write(APB_CTRL, 32'hFFFF_FFFF);
        coverage.sample_reg_access(.addr(APB_CTRL), .is_write(1), .is_reset_check(0));
        tb_top.u_apb_bfm.apb_read(APB_CTRL, obs_val);
        coverage.sample_reg_access(.addr(APB_CTRL), .is_write(0), .is_reset_check(0));
        ref_model.check_reg("CTRL_RW", 32'h0000_00FF, obs_val);
        tb_top.u_apb_bfm.apb_write(APB_CTRL, 32'h0000_0000); // Clear EN to stop FIFO flushes

        // CLK_DIV (16 bits active)
        tb_top.u_apb_bfm.apb_write(APB_CLK_DIV, 32'hFFFF_FFFF);
        coverage.sample_reg_access(.addr(APB_CLK_DIV), .is_write(1), .is_reset_check(0));
        tb_top.u_apb_bfm.apb_read(APB_CLK_DIV, obs_val);
        coverage.sample_reg_access(.addr(APB_CLK_DIV), .is_write(0), .is_reset_check(0));
        ref_model.check_reg("CLK_DIV_RW", 32'h0000_FFFF, obs_val);

        // SS_CTRL (8 bits active)
        tb_top.u_apb_bfm.apb_write(APB_SS_CTRL, 32'hFFFF_FFFF);
        coverage.sample_reg_access(.addr(APB_SS_CTRL), .is_write(1), .is_reset_check(0));
        tb_top.u_apb_bfm.apb_read(APB_SS_CTRL, obs_val);
        coverage.sample_reg_access(.addr(APB_SS_CTRL), .is_write(0), .is_reset_check(0));
        ref_model.check_reg("SS_CTRL_RW", 32'h0000_00FF, obs_val);

        // INT_EN (5 bits active)
        tb_top.u_apb_bfm.apb_write(APB_INT_EN, 32'hFFFF_FFFF);
        coverage.sample_reg_access(.addr(APB_INT_EN), .is_write(1), .is_reset_check(0));
        tb_top.u_apb_bfm.apb_read(APB_INT_EN, obs_val);
        coverage.sample_reg_access(.addr(APB_INT_EN), .is_write(0), .is_reset_check(0));
        ref_model.check_reg("INT_EN_RW", 32'h0000_001F, obs_val);

        // DELAY (8 bits active)
        tb_top.u_apb_bfm.apb_write(APB_DELAY, 32'hFFFF_FFFF);
        coverage.sample_reg_access(.addr(APB_DELAY), .is_write(1), .is_reset_check(0));
        tb_top.u_apb_bfm.apb_read(APB_DELAY, obs_val);
        coverage.sample_reg_access(.addr(APB_DELAY), .is_write(0), .is_reset_check(0));
        ref_model.check_reg("DELAY_RW", 32'h0000_00FF, obs_val);

        $display("[INFO] reg_access_test: finished, internal errors=%0d", ref_model.error_count);
    endtask

endclass

`endif // REG_ACCESS_TEST_SV