// =============================================================================
// spi_sva.sv  (SV-only starter scaffold)
// -----------------------------------------------------------------------------
// SVA target module. `tb_top` binds it into `dut_wrapper.u_dut.u_regfile`:
//
//   bind u_wrap.u_dut.u_regfile spi_sva u_sva (.*);
//   (use the instance path of your dut_wrapper instance, here `u_wrap`)
//
// Add assertions for every spec requirement that you can prove without
// modifying the DUT. The scaffold ships two starter assertions so that the
// file compiles and the grader sees at least one SVA active.
// =============================================================================

`ifndef SPI_SVA_SV
`define SPI_SVA_SV
`timescale 1ns/1ps

module spi_sva (
    spi_if.slave      spi,
    input wire        PRESETn,
    input wire [4:0]  int_stat,
    input wire [4:0]  int_en,
        // Configuration (live from regfile)
    input  wire         cfg_en,
    input  wire         cfg_mstr,
    input  wire [1:0]   cfg_mode,
    input  wire         cfg_lsb_first,
    input  wire         cfg_loopback,
    input  wire [1:0]   cfg_width,
    input  wire [15:0]  cfg_clk_div,
    input  wire [7:0]   cfg_delay,

    // SS observation: core starts only when at least one SS lane is asserted
    // low on the pins (regfile owns the final drive).
    input  wire [3:0]   ss_n_drive,

    // TX FIFO -> core
    input  wire [31:0]  tx_word,
    input  wire         tx_empty,
    input wire          tx_pop,

    // core -> RX FIFO
    input wire          rx_push_valid,
    input wire  [31:0]  rx_push_data,

    // Status
    input wire         busy,
    input wire         transfer_done_pulse,


    input logic [1:0]   st, //state

    input wire [16:0]   half_period,
    input wire          sclk_phase,
    input wire [16:0]   sclk_cnt,
    input wire          cpol,
    input wire          cpha,
    
    input wire [31:0]   sh_tx,
    input wire [31:0]   sh_rx,
    input wire [5:0]    bit_cnt,
    input wire [5:0]    width_bits,


    input wire          miso_eff,

    input wire          xfer_lsb_first,
    input wire [15:0]   xfer_div,
    input wire [1:0]    xfer_mode,
    input wire [1:0]    xfer_width,

    input wire [8:0]    gap_cnt
);

   typedef enum logic [1:0] {
        S_IDLE   = 2'd0,
        S_SHIFT  = 2'd1,
        S_FINISH = 2'd2,
        S_GAP    = 2'd3
    } xfer_state_e;

    xfer_state_e state = st;

    // Aggregate IRQ is OR of all five sticky status bits (R18)
    // a_irq_agg : assert property (
    //     @(posedge spi.PCLK) disable iff (!PRESETn)
    //         IRQ == |int_stat
    // ) else $error("[ASSERTION_ERROR] a_irq_agg IRQ=%b int_stat=%b",
    //               IRQ, int_stat);

    // When CTRL.EN deasserts, aggregate IRQ MUST be 0 within 1 cycle
    // (student should extend with the exact spec wording from R19)
    a_irq_off_when_disabled : assert property (
        @(posedge spi.PCLK) disable iff (!PRESETn)
            (!cfg_en) |-> ##[0:1] (spi.IRQ == 1'b0 || int_stat != 0)
    ) else $error("[ASSERTION_ERROR] a_irq_off_when_disabled");


    logic sample_edge;
    logic leading;
    logic launch_edge;
    assign leading = ~sclk_phase;
    assign sample_edge = (cpha == 1'b0) ? leading : !leading;
    assign launch_edge = ~sample_edge;


    //  SPI: SCLK idle level matches CPOL whenever BUSY=0.
    property p_sclk_idle;
        @(posedge spi.pclk) disable iff (!PRESETn)
            !busy |-> (spi.sclk == cfg_mode[1]);    
    endproperty
    a_sclk_idle : assert property (p_sclk_idle) else
        $error("[ASSERTION_ERROR] a_sclk_idle: SCLK idle level does not match CPOL. SCLK=%b, CPOL=%b, BUSY=%b",
               spi.sclk, cfg_mode[1], busy);

    //R3 - SPI
    //  CTRL.EN=0 holds the shifter and FIFOs in reset; SCLK stays at CPOL idle; 
    property p_ctrl_en_reset;
        @(posedge spi.pclk) disable iff (!PRESETn)
            !cfg_en |=> (state == S_IDLE) && (spi.sclk == cfg_mode[1]) && tx_empty; 
    endproperty
    a_ctrl_en_reset : assert property (p_ctrl_en_reset) else
        $error("[ASSERTION_ERROR] a_ctrl_en_reset: CTRL.EN=0 does not hold shifter/FIFOs in reset or SCLK at CPOL. state=%b, SCLK=%b, CPOL=%b, tx_empty=%b",
               state, spi.sclk, cfg_mode[1], tx_empty);

    
    // R4
    // For each SPI mode, SCLK idle polarity matches CPOL before, between, and after transfers
    property p_cpol_idle;
        @(posedge spi.pclk) disable iff (!PRESETn)
            (state == S_IDLE) |=> (spi.sclk == cfg_mode[1]);
    endproperty

    property p_cpol_gab;
        @(posedge spi.pclk) disable iff (!PRESETn)
            (state == S_GAP) |-> (spi.sclk == cpol);
    endproperty

    property p_cpol_finish;
        @(posedge spi.pclk) disable iff (!PRESETn)
            (state == S_FINISH) && (sclk_cnt == half_period - 1) |=> (spi.sclk == cpol);
    endproperty

    a_p_cpol_idle : assert property (p_cpol_idle) else
        $error("[ASSERTION_ERROR] a_cpol_idle: SCLK idle level does not match CPOL before/after transfers. SCLK=%b, CPOL=%b, state=%b",
            spi.sclk, cfg_mode[1], state);   
    a_p_cpol_gab : assert property (p_cpol_gab) else
        $error("[ASSERTION_ERROR] a_cpol_gab: SCLK level does not match CPOL during GAB state. SCLK=%b, CPOL=%b, state=%b",
            spi.sclk, cpol, state);
    a_p_cpol_finish : assert property (p_cpol_finish) else
        $error("[ASSERTION_ERROR] a_cpol_finish: SCLK level does not match CPOL at the end of transfer. SCLK=%b, CPOL=%b, state=%b, sclk_cnt=%d",
            spi.sclk, cpol, state, sclk_cnt);

    // R5
    // For each SPI mode, MOSI is stable across the sample edge defined by CPOL/CPHA and changes on the launch edge.
    // SPI: MOSI stable for at least 1 PCLK around each sample edge (WIRE-STABILITY).
    property p_mosi_stable_before;
        @(posedge spi.pclk) disable iff (!PRESETn)
            state == S_SHIFT && sclk_cnt == half_period-2 |-> $stable(spi.mosi);
    endproperty
    a_mosi_stable : assert property (p_mosi_stable_before) else
        $error("[ASSERTION_ERROR] a_mosi_stable: MOSI is not stable before sample edges. MOSI=%b, PAST_MOSI=%b",
               spi.mosi, $past(spi.mosi));
    property p_mosi_stable_after;
        @(posedge spi.pclk) disable iff (!PRESETn)
            sample_edge && state == S_SHIFT && sclk_cnt == half_period-1 |=> $stable(spi.mosi);
    endproperty
    a_mosi_stable_after : assert property (p_mosi_stable_after) else
        $error("[ASSERTION_ERROR] a_mosi_stable_after: MOSI is not stable after sample edges. MOSI=%b, PAST_MOSI=%b",
               spi.mosi, $past(spi.mosi));

    property p_mosi_stable_between_launches;
    @(posedge spi.pclk) disable iff (!PRESETn)
        (state == S_SHIFT) && !launch_edge |-> $stable(spi.mosi);  // no glitching mid-bit
    endproperty 
    a_p_mosi_stable_between_launches : assert property (p_mosi_stable_between_launches) else
        $error("[ASSERTION_ERROR] a_mosi_stable_between_launches: MOSI is not stable between launch edges. MOSI=%b, LAUNCH_EDGE=%b",
               spi.mosi, launch_edge);

    // SPI: SS_n held asserted for the entire WIDTH-bit transfer.
    property p_ss_hold;
        @(posedge spi.pclk) disable iff (!PRESETn)
            busy |-> (ss_n_drive == 4'b0000);
    endproperty
    a_ss_hold : assert property (p_ss_hold) else
        $error("[ASSERTION_ERROR] a_ss_hold: SS_n is not held asserted for the entire transfer. SS_n_drive=%b, state=%b, tx_empty=%b",
               ss_n_drive, state, tx_empty);    

    // R6
    // MSB-first shifts bit [WIDTH-1] first; LSB-first shifts bit [0] first (both on TX and RX)
    property p_mosi_shift_order;
        @(posedge spi.pclk) disable iff (!PRESETn)
            (state == S_SHIFT) && launch_edge && (sclk_cnt == half_period - 1)
            |=> (spi.mosi == (xfer_lsb_first ? 
                    sh_tx[$past(bit_cnt) - 1] : 
                    sh_tx[width_bits - $past(bit_cnt)]));  // get_tx_bit equivalent
    endproperty

    property p_miso_shift_order;
        @(posedge spi.pclk) disable iff (!PRESETn)
            (state == S_SHIFT) && sample_edge && (sclk_cnt == half_period - 1)
            |=> (xfer_lsb_first ? 
                    sh_rx[width_bits - $past(bit_cnt)] == $past(spi.miso) :
                    sh_rx[$past(bit_cnt) - 1]        == $past(spi.miso));
    endproperty

    a_mosi_shift_order : assert property (p_mosi_shift_order) else
        $error("[ASSERTION_ERROR] a_mosi_shift_order: Wrong MOSI bit. MOSI=%b, bit_cnt=%0d, lsb_first=%b",
            spi.mosi, bit_cnt, xfer_lsb_first);

    a_miso_shift_order : assert property (p_miso_shift_order) else
        $error("[ASSERTION_ERROR] a_miso_shift_order: Wrong MISO capture position. bit_cnt=%0d, lsb_first=%b",
            bit_cnt, xfer_lsb_first);

    //R7
    //A transfer lasts exactly WIDTH SCLK cycles; BUSY=1 throughout and deasserts one PCLK after the last sample edge.
logic gap_cond = !tx_empty && cfg_delay != 8'h0;
property p_busy_after_transfer;
    @(posedge spi.pclk) disable iff (!PRESETn)
        state == S_FINISH ##1 (state == S_IDLE) |-> !busy;
endproperty

a_busy_after_transfer : assert property (p_busy_after_transfer) else
    $error("[ASSERTION_ERROR] a_busy_after_transfer: BUSY does not stay high through the end of transfer. state=%b, sclk_cnt=%0d, gap_cond=%b, busy=%b",
           state, sclk_cnt, gap_cond, busy);

logic start_cond = !tx_empty && cfg_mstr && (ss_n_drive != 4'hF);
property p_busy_start_transfer;
    @(posedge spi.pclk) disable iff (!PRESETn)
        (state == S_IDLE) && start_cond |=> busy;
endproperty

a_busy_start_transfer : assert property (p_busy_start_transfer) else
    $error("[ASSERTION_ERROR] a_busy_start_transfer: BUSY does not stay high when starting a transfer. state=%b, sclk_cnt=%0d, start_cond=%b, busy=%b",
           state, sclk_cnt, start_cond, busy);


property p_busy_during_transfer;
    @(posedge spi.pclk) disable iff (!PRESETn)
        (state == S_SHIFT) |-> busy;
endproperty
a_busy_during_transfer : assert property (p_busy_during_transfer) else
    $error("[ASSERTION_ERROR] a_busy_during_transfer: BUSY is not high during transfer. state=%b, busy=%b",
           state, busy);

property p_last_sample_to_finish;
    @(posedge spi.pclk) disable iff (!PRESETn)
        (state == S_SHIFT) && bit_cnt == 1 && sample_edge |=> (state == S_FINISH) && !busy;
endproperty
a_last_sample_to_finish : assert property (p_last_sample_to_finish) else
    $error("[ASSERTION_ERROR] a_last_sample_to_finish: Transfer does not end after WIDTH bits. state=%b, bit_cnt=%0d, sample_edge=%b, busy=%b",
           state, bit_cnt, sample_edge, busy);


property p_tranfer_done;
    @(posedge spi.pclk) disable iff (!PRESETn)
       (state == S_FINISH) && sclk_cnt == half_period - 1 |=>  $rose (transfer_done_pulse) ;
endproperty
a_transfer_done : assert property (p_tranfer_done) else
    $error("[ASSERTION_ERROR] a_transfer_done: transfer_done_pulse is not pulsed at the end of transfer. state=%b, sclk_cnt=%0d, transfer_done_pulse=%b",
           state, sclk_cnt, transfer_done_pulse);

    // R8
    // SCLK frequency equals PCLK / (2 x (DIV+1)) for all DIV in [0, 65535].
property p_half_period_value;
    @(posedge spi.pclk) disable iff (!PRESETn)
        (state == S_SHIFT)
        |-> (half_period == ({1'b0, xfer_div} + 17'd1));
endproperty


a_half_period_value : assert property (p_half_period_value) else
    $error("[ASSERTION_ERROR] a_half_period_value: half_period mismatch. half_period=%0d, xfer_div=%0d",
           half_period, xfer_div);

//R19
// Loopback mode (CTRL.LOOPBACK=1) routes MOSI internally to the RX shift register; external MISO is ignored
//assume the loopback signal doesnt change between transfers,
property p_loopback_miso_eff;
    @(posedge spi.pclk) disable iff (!PRESETn)
        cfg_loopback && (state == S_SHIFT) |-> (miso_eff == spi.mosi);
endproperty
a_loopback : assert property (p_loopback_miso_eff) else
    $error("[ASSERTION_ERROR] a_loopback: Loopback mode does not route MOSI to RX. miso_eff=%b, spi.mosi=%b, cfg_loopback=%b",
           miso_eff, spi.mosi, cfg_loopback);

property p_loopback_rx_shift;
    @(posedge spi.pclk) disable iff (!PRESETn)
        cfg_loopback && (state == S_SHIFT) && sclk_cnt == half_period - 1 && sample_edge |=> (xfer_lsb_first ? sh_rx[width_bits - $past(bit_cnt)] == $past(spi.mosi) : sh_rx[$past(bit_cnt) - 1] == $past(spi.mosi));
endproperty
a_loopback_rx_shift : assert property (p_loopback_rx_shift) else
    $error("[ASSERTION_ERROR] a_loopback_rx_shift: Loopback mode does not shift MOSI into RX correctly. bit_cnt=%0d, width_bits=%0d, lsb_first=%b, sh_rx=%h, spi.mosi=%b",
           bit_cnt, width_bits, xfer_lsb_first, sh_rx, spi.mosi);

// R21
// DELAY SCLK half-cycles of idle are inserted between consecutive transfers when DELAY > 0 and another word is queued.
property p_delay_between_transfers;
    @(posedge spi.pclk) disable iff (!PRESETn)
        (state == S_FINISH) && gap_cond && (sclk_cnt == half_period - 1) |=> (state == S_GAP) && (gap_cnt == {1'b0,cfg_delay});
endproperty
a_delay_between_transfers : assert property (p_delay_between_transfers) else
    $error("[ASSERTION_ERROR] a_delay_between_transfers: Delay between transfers is not inserted correctly. state=%b, cfg_delay=%0d, tx_empty=%b",
           state, cfg_delay, tx_empty);

property p_delay_countdown;
    @(posedge spi.pclk) disable iff (!PRESETn)
        (state == S_GAP) && (sclk_cnt == half_period - 1) && gap_cnt > 1 |=> gap_cnt == $past(gap_cnt) - 1;
endproperty
a_delay_countdown : assert property (p_delay_countdown) else
    $error("[ASSERTION_ERROR] a_delay_countdown: Delay is not enforced correctly. state=%b, sclk_cnt=%0d, cfg_delay=%0d",
           state, sclk_cnt, cfg_delay);

// S_GAP exits to S_IDLE when gap_cnt reaches 1
property p_delay_exit;
    @(posedge spi.pclk) disable iff (!PRESETn)
        (state == S_GAP) && (gap_cnt == 1) && (sclk_cnt == half_period - 1) |=> (state == S_IDLE);
endproperty
a_delay_exit : assert property (p_delay_exit) else
    $error("[ASSERTION_ERROR] a_delay_exit: GAP state does not exit correctly. state=%b, sclk_cnt=%0d, gap_cnt=%0d",
           state, sclk_cnt, gap_cnt);

//R24
// CLK_DIV=0 yields SCLK = PCLK/2 (DIV is not a divide-by-zero).
property p_clk_div_zero;
    @(posedge spi.pclk) disable iff (!PRESETn)
        (state == S_SHIFT) && (xfer_div == 17'h0) |-> (half_period == 17'h1);
endproperty
a_clk_div_zero : assert property (p_clk_div_zero) else
    $error("[ASSERTION_ERROR] a_clk_div_zero: CLK_DIV=0 does not yield SCLK = PCLK/2. state=%b, xfer_div=%0d, half_period=%0d",
           state, xfer_div, half_period);

//R25
//DIV, MODE, WIDTH, LSB_FIRST are sampled at transfer start and held for that transfer.

property p_sample_signals;
    @(posedge spi.pclk) disable iff (!PRESETn)
               $rose(busy)  |-> (xfer_lsb_first == $past(cfg_lsb_first)) && (xfer_div == $past(cfg_clk_div)) && (xfer_width  == $past(cfg_width))  && (xfer_mode == $past(cfg_mode)); 
endproperty
a_sample_signals : assert property (p_sample_signals) else
    $error("[ASSERTION_ERROR] a_sample_signals: Configuration signals are not sampled correctly at transfer start. state=%b, start_cond=%b, xfer_lsb_first=%b, cfg_lsb_first=%b, xfer_div=%0d, cfg_clk_div=%0d, xfer_width=%0d, cfg_width=%0d, xfer_mode=%b, cfg_mode=%b",
           state, start_cond, xfer_lsb_first, cfg_lsb_first, xfer_div, cfg_clk_div, xfer_width, cfg_width, xfer_mode, cfg_mode);

property p_sample_signals_stable;
    @(posedge spi.pclk) disable iff (!PRESETn)
        (state == S_SHIFT)|-> $stable(xfer_lsb_first) && $stable(xfer_div) && $stable(xfer_width) && $stable(xfer_mode);
endproperty
a_sample_signals_stable : assert property (p_sample_signals_stable) else
    $error("[ASSERTION_ERROR] a_sample_signals_stable: Configuration signals change during transfer. state=%b, xfer_lsb_first=%b, xfer_div=%0d, xfer_width=%0d, xfer_mode=%b",
           state, xfer_lsb_first, xfer_div,  xfer_width,  xfer_mode,);

endmodule

`endif // SPI_SVA_SV
