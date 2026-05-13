// =============================================================================
// spi_sva_enhanced.sv
// -----------------------------------------------------------------------------
// Enhanced SPI-side SVA assertions covering R3–R8, R19, R21, R24, R25.
// All bugs from the original spi_sva.sv are fixed.
// Structure: properties grouped by requirement, asserts and covers separated.
// =============================================================================

`ifndef SPI_SVA_ENHANCED_SV
`define SPI_SVA_ENHANCED_SV
`timescale 1ns/1ps

module spi_sva_enhanced (
    spi_if.slave        spi,
    input wire          PRESETn,
    input wire [4:0]    int_stat,
    input wire [4:0]    int_en,

    // Configuration (live from regfile)
    input wire          cfg_en,
    input wire          cfg_mstr,
    input wire [1:0]    cfg_mode,
    input wire          cfg_lsb_first,
    input wire          cfg_loopback,
    input wire [1:0]    cfg_width,
    input wire [15:0]   cfg_clk_div,
    input wire [7:0]    cfg_delay,

    // SS observation
    input wire [3:0]    ss_n_drive,

    // TX FIFO -> core
    input wire [31:0]   tx_word,
    input wire          tx_empty,
    input wire          tx_pop,

    // core -> RX FIFO
    input wire          rx_push_valid,
    input wire [31:0]   rx_push_data,

    // Status
    input wire          busy,
    input wire          transfer_done_pulse,

    // FSM state (2-bit raw from spi_core)
    input logic [1:0]   st,

    // Internal timing signals
    input wire [16:0]   half_period,
    input wire          sclk_phase,
    input wire [16:0]   sclk_cnt,
    input wire          cpol,
    input wire          cpha,

    // Shift registers and bit counter
    input wire [31:0]   sh_tx,
    input wire [31:0]   sh_rx,
    input wire [5:0]    bit_cnt,
    input wire [5:0]    width_bits,

    // Effective MISO (loopback-aware)
    input wire          miso_eff,

    // Latched per-transfer configuration
    input wire          xfer_lsb_first,
    input wire [15:0]   xfer_div,
    input wire [1:0]    xfer_mode,
    input wire [1:0]    xfer_width,   // Fixed: RTL is [1:0], not [5:0]

    // Gap counter (was missing from original)
    input wire [8:0]    gap_cnt
);

    // =========================================================================
    // FSM state enum
    // =========================================================================
    typedef enum logic [1:0] {
        S_IDLE   = 2'd0,
        S_SHIFT  = 2'd1,
        S_FINISH = 2'd2,
        S_GAP    = 2'd3
    } xfer_state_e;

    xfer_state_e state;
    assign state = xfer_state_e'(st);

    // =========================================================================
    // Derived helper signals (fixed typo: scllk_phase -> sclk_phase)
    // =========================================================================
    logic leading;
    logic sample_edge;
    logic launch_edge;
    assign leading     = ~sclk_phase;
    assign sample_edge = (cpha == 1'b0) ? leading : ~leading;
    assign launch_edge = ~sample_edge;

    // Start condition for new transfer
    logic start_cond;
    assign start_cond = !tx_empty && cfg_mstr && (ss_n_drive != 4'hF);

    // Gap condition (delay > 0 and more data queued)
    logic gap_cond;
    assign gap_cond = !tx_empty && cfg_delay != 8'h0;

    // =========================================================================
    // GROUP: R3 — CTRL.EN=0 holds shifter in reset
    // =========================================================================

    // --- R3a: When EN=0, state must be IDLE ---
    property p_en0_state_idle;
        @(posedge spi.pclk) disable iff (!PRESETn)
            !cfg_en |-> (state == S_IDLE);
    endproperty

    a_en0_state_idle : assert property (p_en0_state_idle)
        else $error("[ASSERTION_ERROR] a_en0_state_idle: state not IDLE when EN=0. state=%0d", state);
    c_en0_state_idle : cover property (p_en0_state_idle);

    // --- R3b: When EN=0, SCLK at CPOL idle ---
    property p_en0_sclk_idle;
        @(posedge spi.pclk) disable iff (!PRESETn)
            !cfg_en |-> (spi.sclk == cfg_mode[1]);
    endproperty

    a_en0_sclk_idle : assert property (p_en0_sclk_idle)
        else $error("[ASSERTION_ERROR] a_en0_sclk_idle: SCLK not at CPOL when EN=0. SCLK=%b CPOL=%b",
                    spi.sclk, cfg_mode[1]);
    c_en0_sclk_idle : cover property (p_en0_sclk_idle);

    // =========================================================================
    // GROUP: R4 — SCLK idle polarity matches CPOL (Mandatory §10.2)
    // =========================================================================

    // --- R4a: SCLK idle in S_IDLE ---
    property p_cpol_idle;
        @(posedge spi.pclk) disable iff (!PRESETn)
            (state == S_IDLE) |-> (spi.sclk == cfg_mode[1]);
    endproperty

    a_cpol_idle : assert property (p_cpol_idle)
        else $error("[ASSERTION_ERROR] a_cpol_idle: SCLK!= CPOL in IDLE. SCLK=%b CPOL=%b",
                    spi.sclk, cfg_mode[1]);
    c_cpol_idle : cover property (p_cpol_idle);

    // --- R4b: SCLK idle in S_GAP ---
    property p_cpol_gap;
        @(posedge spi.pclk) disable iff (!PRESETn)
            (state == S_GAP) |-> (spi.sclk == cpol);
    endproperty

    a_cpol_gap : assert property (p_cpol_gap)
        else $error("[ASSERTION_ERROR] a_cpol_gap: SCLK!=CPOL in GAP. SCLK=%b CPOL=%b",
                    spi.sclk, cpol);
    c_cpol_gap : cover property (p_cpol_gap);

    // --- R4c: SCLK returns to CPOL at end of S_FINISH ---
    property p_cpol_finish;
        @(posedge spi.pclk) disable iff (!PRESETn)
            (state == S_FINISH) && (sclk_cnt == half_period - 1)
            |=> (spi.sclk == cpol);
    endproperty

    a_cpol_finish : assert property (p_cpol_finish)
        else $error("[ASSERTION_ERROR] a_cpol_finish: SCLK!=CPOL after FINISH. SCLK=%b CPOL=%b",
                    spi.sclk, cpol);
    c_cpol_finish : cover property (p_cpol_finish);

    // --- R4d: SCLK idle when BUSY=0 (Mandatory assertion wording) ---
    property p_sclk_idle_not_busy;
        @(posedge spi.pclk) disable iff (!PRESETn)
            !busy |-> (spi.sclk == cfg_mode[1]);
    endproperty

    a_sclk_idle_not_busy : assert property (p_sclk_idle_not_busy)
        else $error("[ASSERTION_ERROR] a_sclk_idle_not_busy: SCLK!=CPOL when BUSY=0. SCLK=%b CPOL=%b",
                    spi.sclk, cfg_mode[1]);
    c_sclk_idle_not_busy : cover property (p_sclk_idle_not_busy);

    // =========================================================================
    // GROUP: R5 — MOSI stable around sample edge (Mandatory §10.2)
    // =========================================================================

    // --- R5a: MOSI stable 1 PCLK before sample edge ---
    property p_mosi_stable_before;
        @(posedge spi.pclk) disable iff (!PRESETn)
            (state == S_SHIFT) && sample_edge && (sclk_cnt == half_period - 2)
            |-> $stable(spi.mosi);
    endproperty

    a_mosi_stable_before : assert property (p_mosi_stable_before)
        else $error("[ASSERTION_ERROR] a_mosi_stable_before: MOSI changed before sample edge. MOSI=%b",
                    spi.mosi);
    c_mosi_stable_before : cover property (p_mosi_stable_before);

    // --- R5b: MOSI stable 1 PCLK after sample edge ---
    property p_mosi_stable_after;
        @(posedge spi.pclk) disable iff (!PRESETn)
            sample_edge && (state == S_SHIFT) && (sclk_cnt == half_period - 1)
            |=> $stable(spi.mosi);
    endproperty

    a_mosi_stable_after : assert property (p_mosi_stable_after)
        else $error("[ASSERTION_ERROR] a_mosi_stable_after: MOSI changed after sample edge. MOSI=%b",
                    spi.mosi);
    c_mosi_stable_after : cover property (p_mosi_stable_after);

    // --- R5c: MOSI stable between launch edges (no mid-bit glitch) ---
    property p_mosi_stable_between_launches;
        @(posedge spi.pclk) disable iff (!PRESETn)
            (state == S_SHIFT) && !(launch_edge && sclk_cnt == half_period - 1)
            |-> $stable(spi.mosi);
    endproperty

    a_mosi_stable_between : assert property (p_mosi_stable_between_launches)
        else $error("[ASSERTION_ERROR] a_mosi_stable_between: MOSI glitched mid-bit. MOSI=%b",
                    spi.mosi);
    c_mosi_stable_between : cover property (p_mosi_stable_between_launches);

    // =========================================================================
    // GROUP: R6 — MSB/LSB-first shift order
    // =========================================================================

    // --- R6a: MOSI outputs correct bit ---
    // Fixed: LSB-first and MSB-first now have DIFFERENT index expressions
    property p_mosi_shift_order;
        @(posedge spi.pclk) disable iff (!PRESETn)
            (state == S_SHIFT) && launch_edge && (sclk_cnt == half_period - 1)
            |=> (spi.mosi == (xfer_lsb_first ?
                    sh_tx[width_bits - $past(bit_cnt)] :
                    sh_tx[$past(bit_cnt) - 1]));
    endproperty

    a_mosi_shift_order : assert property (p_mosi_shift_order)
        else $error("[ASSERTION_ERROR] a_mosi_shift_order: Wrong MOSI bit. MOSI=%b bit_cnt=%0d lsb=%b",
                    spi.mosi, bit_cnt, xfer_lsb_first);
    c_mosi_shift_order : cover property (p_mosi_shift_order);

    // --- R6b: MISO captured into correct sh_rx position ---
    property p_miso_shift_order;
        @(posedge spi.pclk) disable iff (!PRESETn)
            (state == S_SHIFT) && sample_edge && (sclk_cnt == half_period - 1)
            |=> (xfer_lsb_first ?
                    sh_rx[width_bits - $past(bit_cnt)] == $past(miso_eff) :
                    sh_rx[$past(bit_cnt) - 1]          == $past(miso_eff));
    endproperty

    a_miso_shift_order : assert property (p_miso_shift_order)
        else $error("[ASSERTION_ERROR] a_miso_shift_order: Wrong MISO position. bit_cnt=%0d lsb=%b",
                    bit_cnt, xfer_lsb_first);
    c_miso_shift_order : cover property (p_miso_shift_order);

    // =========================================================================
    // GROUP: R7 — Transfer = WIDTH SCLK cycles, BUSY semantics
    // =========================================================================

    // --- R7a: BUSY=1 during S_SHIFT ---
    property p_busy_during_shift;
        @(posedge spi.pclk) disable iff (!PRESETn)
            (state == S_SHIFT) |-> busy;
    endproperty

    a_busy_during_shift : assert property (p_busy_during_shift)
        else $error("[ASSERTION_ERROR] a_busy_during_shift: BUSY=0 during SHIFT. state=%0d", state);
    c_busy_during_shift : cover property (p_busy_during_shift);

    // --- R7b: BUSY=1 during S_FINISH ---
    // Fixed: original had !busy which was WRONG (busy = state != S_IDLE)
    property p_busy_during_finish;
        @(posedge spi.pclk) disable iff (!PRESETn)
            (state == S_FINISH) |-> busy;
    endproperty

    a_busy_during_finish : assert property (p_busy_during_finish)
        else $error("[ASSERTION_ERROR] a_busy_during_finish: BUSY=0 during FINISH. state=%0d", state);
    c_busy_during_finish : cover property (p_busy_during_finish);

    // --- R7c: BUSY=1 during S_GAP ---
    property p_busy_during_gap;
        @(posedge spi.pclk) disable iff (!PRESETn)
            (state == S_GAP) |-> busy;
    endproperty

    a_busy_during_gap : assert property (p_busy_during_gap)
        else $error("[ASSERTION_ERROR] a_busy_during_gap: BUSY=0 during GAP. state=%0d", state);
    c_busy_during_gap : cover property (p_busy_during_gap);

    // --- R7d: BUSY=0 in S_IDLE ---
    property p_idle_not_busy;
        @(posedge spi.pclk) disable iff (!PRESETn)
            (state == S_IDLE) |-> !busy;
    endproperty

    a_idle_not_busy : assert property (p_idle_not_busy)
        else $error("[ASSERTION_ERROR] a_idle_not_busy: BUSY=1 in IDLE. state=%0d", state);
    c_idle_not_busy : cover property (p_idle_not_busy);

    // --- R7e: Transfer starts from IDLE when start_cond ---
    property p_busy_start;
        @(posedge spi.pclk) disable iff (!PRESETn)
            (state == S_IDLE) && start_cond && cfg_en |=> busy;
    endproperty

    a_busy_start : assert property (p_busy_start)
        else $error("[ASSERTION_ERROR] a_busy_start: BUSY not set after start. start_cond=%b", start_cond);
    c_busy_start : cover property (p_busy_start);

    // --- R7f: Last sample edge transitions to S_FINISH ---
    // Fixed: bits_cnt -> bit_cnt
    property p_last_sample_to_finish;
        @(posedge spi.pclk) disable iff (!PRESETn)
            (state == S_SHIFT) && (bit_cnt == 6'd1) && sample_edge && (sclk_cnt == half_period - 1)
            |=> (state == S_FINISH);
    endproperty

    a_last_sample_to_finish : assert property (p_last_sample_to_finish)
        else $error("[ASSERTION_ERROR] a_last_sample_to_finish: No FINISH after last sample. state=%0d bit_cnt=%0d",
                    state, bit_cnt);
    c_last_sample_to_finish : cover property (p_last_sample_to_finish);

    // --- R7g: transfer_done_pulse fires at end of S_FINISH ---
    // Fixed: ransfer_done_pulse -> transfer_done_pulse
    property p_transfer_done;
        @(posedge spi.pclk) disable iff (!PRESETn)
            (state == S_FINISH) && (sclk_cnt == half_period - 1)
            |=> $past(transfer_done_pulse) || transfer_done_pulse;
    endproperty

    a_transfer_done : assert property (p_transfer_done)
        else $error("[ASSERTION_ERROR] a_transfer_done: transfer_done_pulse missing. state=%0d",
                    state);
    c_transfer_done : cover property (p_transfer_done);

    // =========================================================================
    // GROUP: R8 — SCLK frequency = PCLK / (2*(DIV+1))
    // =========================================================================

    property p_half_period_value;
        @(posedge spi.pclk) disable iff (!PRESETn)
            (state == S_SHIFT)
            |-> (half_period == ({1'b0, xfer_div} + 17'd1));
    endproperty

    a_half_period_value : assert property (p_half_period_value)
        else $error("[ASSERTION_ERROR] a_half_period_value: half_period=%0d expected=%0d",
                    half_period, {1'b0, xfer_div} + 17'd1);
    c_half_period_value : cover property (p_half_period_value);

    // =========================================================================
    // GROUP: SPI SS_n held during transfer (Mandatory §10.2)
    // =========================================================================

    property p_ss_hold;
        @(posedge spi.pclk) disable iff (!PRESETn)
            busy |-> (ss_n_drive != 4'hF);
    endproperty

    a_ss_hold : assert property (p_ss_hold)
        else $error("[ASSERTION_ERROR] a_ss_hold: SS_n deasserted during transfer. SS_n=%b busy=%b",
                    ss_n_drive, busy);
    c_ss_hold : cover property (p_ss_hold);

    // =========================================================================
    // GROUP: R19 — Loopback mode
    // =========================================================================

    // --- R19a: In loopback, miso_eff == MOSI (Fixed: was != which is WRONG) ---
    property p_loopback_miso_eff;
        @(posedge spi.pclk) disable iff (!PRESETn)
            cfg_loopback && (state == S_SHIFT) |-> (miso_eff == spi.mosi);
    endproperty

    a_loopback : assert property (p_loopback_miso_eff)
        else $error("[ASSERTION_ERROR] a_loopback: miso_eff!=MOSI in loopback. miso_eff=%b mosi=%b",
                    miso_eff, spi.mosi);
    c_loopback : cover property (p_loopback_miso_eff);

    // --- R19b: Loopback RX shift captures MOSI ---
    property p_loopback_rx_shift;
        @(posedge spi.pclk) disable iff (!PRESETn)
            cfg_loopback && (state == S_SHIFT)
                && (sclk_cnt == half_period - 1) && sample_edge
            |=> (xfer_lsb_first ?
                    sh_rx[width_bits - $past(bit_cnt)] == $past(spi.mosi) :
                    sh_rx[$past(bit_cnt) - 1]          == $past(spi.mosi));
    endproperty

    a_loopback_rx_shift : assert property (p_loopback_rx_shift)
        else $error("[ASSERTION_ERROR] a_loopback_rx_shift: Loopback RX mismatch. bit_cnt=%0d lsb=%b",
                    bit_cnt, xfer_lsb_first);
    c_loopback_rx_shift : cover property (p_loopback_rx_shift);

    // =========================================================================
    // GROUP: R21 — Inter-transfer DELAY
    // =========================================================================

    // --- R21a: FINISH→GAP when delay>0 and more data queued ---
    property p_delay_enter_gap;
        @(posedge spi.pclk) disable iff (!PRESETn)
            (state == S_FINISH) && gap_cond && (sclk_cnt == half_period - 1)
            |=> (state == S_GAP);
    endproperty

    a_delay_enter_gap : assert property (p_delay_enter_gap)
        else $error("[ASSERTION_ERROR] a_delay_enter_gap: Did not enter GAP. state=%0d delay=%0d",
                    state, cfg_delay);
    c_delay_enter_gap : cover property (p_delay_enter_gap);

    // --- R21b: Gap counter counts down ---
    property p_delay_countdown;
        @(posedge spi.pclk) disable iff (!PRESETn)
            (state == S_GAP) && (sclk_cnt == half_period - 1) && (gap_cnt > 9'd1)
            |=> (gap_cnt == $past(gap_cnt) - 9'd1);
    endproperty

    a_delay_countdown : assert property (p_delay_countdown)
        else $error("[ASSERTION_ERROR] a_delay_countdown: gap_cnt not decrementing. gap_cnt=%0d",
                    gap_cnt);
    c_delay_countdown : cover property (p_delay_countdown);

    // --- R21c: GAP exits to IDLE when gap_cnt reaches 1 ---
    property p_delay_exit;
        @(posedge spi.pclk) disable iff (!PRESETn)
            (state == S_GAP) && (gap_cnt == 9'd1) && (sclk_cnt == half_period - 1)
            |=> (state == S_IDLE);
    endproperty

    a_delay_exit : assert property (p_delay_exit)
        else $error("[ASSERTION_ERROR] a_delay_exit: GAP did not exit to IDLE. state=%0d gap_cnt=%0d",
                    state, gap_cnt);
    c_delay_exit : cover property (p_delay_exit);

    // =========================================================================
    // GROUP: R24 — CLK_DIV=0 yields SCLK = PCLK/2
    // =========================================================================

    // Fixed: removed duplicate @(posedge ...) clocking
    property p_clk_div_zero;
        @(posedge spi.pclk) disable iff (!PRESETn)
            (state == S_SHIFT) && (xfer_div == 16'h0)
            |-> (half_period == 17'h1);
    endproperty

    a_clk_div_zero : assert property (p_clk_div_zero)
        else $error("[ASSERTION_ERROR] a_clk_div_zero: DIV=0 but half_period!= 1. half_period=%0d",
                    half_period);
    c_clk_div_zero : cover property (p_clk_div_zero);

    // =========================================================================
    // GROUP: R25 — Config sampled at transfer start, held during transfer
    // =========================================================================

    // --- R25a: Config latched on transfer start ---
    property p_config_sampled;
        @(posedge spi.pclk) disable iff (!PRESETn)
            $rose(busy)
            |-> (xfer_lsb_first == $past(cfg_lsb_first))
             && (xfer_div       == $past(cfg_clk_div))
             && (xfer_width     == $past(cfg_width))
             && (xfer_mode      == $past(cfg_mode));
    endproperty

    a_config_sampled : assert property (p_config_sampled)
        else $error("[ASSERTION_ERROR] a_config_sampled: Config not latched at start. xfer_mode=%b cfg_mode=%b",
                    xfer_mode, cfg_mode);
    c_config_sampled : cover property (p_config_sampled);

    // --- R25b: Latched config stable throughout transfer ---
    // Fixed: removed duplicate @(posedge ...) and trailing comma
    property p_config_stable;
        @(posedge spi.pclk) disable iff (!PRESETn)
            (state == S_SHIFT)
            |-> $stable(xfer_lsb_first)
             && $stable(xfer_div)
             && $stable(xfer_width)
             && $stable(xfer_mode);
    endproperty

    a_config_stable : assert property (p_config_stable)
        else $error("[ASSERTION_ERROR] a_config_stable: Config changed mid-transfer. state=%0d", state);
    c_config_stable : cover property (p_config_stable);

endmodule

`endif // SPI_SVA_ENHANCED_SV
