`timescale 1ns/1ps

`ifndef COVERAGE_SV
`define COVERAGE_SV

class spi_coverage;

  // =========================
  // APB CORE INTERNALS
  // =========================
  bit          tx_full_w;
  bit          tx_empty_w;
  bit          rx_full_w;
  bit          rx_empty_w;
  logic [4:0]  tx_count;
  logic [4:0]  rx_count;
  logic [4:0]  int_stat;
  logic [4:0]  int_en;
  bit          ctrl_en;
  logic [1:0]  ctrl_mode;
  logic [1:0]  ctrl_width;
  bit          ctrl_lsb_first;
  bit          ctrl_loopback;
  bit          irq;
  logic [3:0]  ss_en;
  logic [3:0]  ss_val;
  logic [31:0] ctrl_word;
  logic [31:0] status_word;
  logic [31:0] tx_word;
  logic [31:0] rx_word;
  logic [31:0] clk_div_word;
  logic [31:0] int_en_word;
  logic [31:0] int_stat_word;
  logic [15:0] clk_div;
  logic [31:0] ss_ctrl_word;
  logic [31:0] delay_word;
  logic [7:0]  delay_cfg;
  // =========================
  // SPI CORE INTERNALS
  // =========================
  bit          busy;
  bit          tx_pop;
  bit          rx_push_valid;
  bit   [1:0]  cfg_mode;
  bit   [1:0]  cfg_width;
  bit          cfg_lsb_first;
  bit   [15:0] cfg_div;
  logic [1:0]  core_state;
  logic [1:0]  latched_mode;
  logic [1:0]  latched_width;
  bit          latched_lsb;
  logic [15:0] latched_div;
  logic [5:0]  bit_cnt;
  logic transfer_done_pulse;
  logic cfg_loopback;
  // =========================
  // Inputs from TB / DUT
  // =========================
  virtual apb_if vif;
  virtual spi_if spi_vif;


  localparam integer IRQ_TX_EMPTY      = 0;
  localparam integer IRQ_RX_FULL       = 1;
  localparam integer IRQ_TX_OVF        = 2;
  localparam integer IRQ_RX_OVF        = 3;
  localparam integer IRQ_TRANSFER_DONE = 4;
  localparam integer IRQ_COUNT         = 5;
  localparam [7:0]   OFF_RX_DATA       = 8'h0C;
  localparam [7:0]   OFF_INT_STAT      = 8'h1C;

  // =========================
  // APB COVERAGE
  // =========================
  covergroup cg_apb @(posedge vif.PCLK);

    cp_sel : coverpoint vif.psel;
    cp_en : coverpoint vif.penable;

    cp_reset : coverpoint vif.presetn {
      bins asserted = {0};
      bins released = {1};
    }

    cp_addr: coverpoint vif.paddr {
      bins ctrl     = {8'h00};
      bins status   = {8'h04};
      bins tx       = {8'h08};
      bins rx       = {8'h0C};
      bins clk_div  = {8'h10};
      bins ss       = {8'h14};
      bins int_enn   = {8'h18};
      bins int_stat = {8'h1C};
      bins delay    = {8'h20};
    }

    cp_rw: coverpoint vif.pwrite;
    cp_ready: coverpoint vif.pready {
      bins ready = {1'b1};
      illegal_bins not_ready = {1'b0};
    }

    cp_err: coverpoint vif.pslverr {
      bins no_error = {1'b0};
      illegal_bins error = {1'b1};
    }

    cross_sel_en: cross cp_sel, cp_en;
    cross_addr_rw: cross cp_addr, cp_rw;

  endgroup


  // =========================
  // FIFO COVERAGE
  // =========================
  covergroup cg_fifo @(posedge vif.PCLK);

    cp_tx_full  : coverpoint tx_full_w;
    cp_tx_empty : coverpoint tx_empty_w;
    cp_rx_full  : coverpoint rx_full_w;
    cp_rx_empty : coverpoint rx_empty_w;

    cp_tx_count : coverpoint tx_count {
      bins empty = {0};
      bins one   = {1};
      bins mid   = {4};
      bins mids[] = {[2:3], [5:7]};
      bins full  = {8};
      illegal_bins overflow = {[9:15]};
    }

    cp_rx_count : coverpoint rx_count {
      bins empty = {0};
      bins one   = {1};
      bins mid   = {4};
      bins mids[] = {[2:3], [5:7]};
      bins full  = {8};
      illegal_bins overflow = {[9:15]};
    }

    cp_tx_ovf : coverpoint int_stat[IRQ_TX_OVF] {
        bins clear = {1'b0};
        bins set = {1'b1};
    }
    cp_rx_ovf : coverpoint int_stat[IRQ_RX_OVF] {
        bins clear = {1'b0};
        bins set = {1'b1};
    }

    cross_tx_ovf : cross cp_tx_ovf, cp_tx_count {
        bins clear_empty = binsof(cp_tx_ovf.clear) && binsof(cp_tx_count.empty);
        bins clear_one = binsof(cp_tx_ovf.clear) && binsof(cp_tx_count.one);
        bins clear_mids = binsof(cp_tx_ovf.clear) && binsof(cp_tx_count.mids);
        bins clear_mid = binsof(cp_tx_ovf.clear) && binsof(cp_tx_count.mid);
        bins clear_nov = binsof(cp_tx_ovf.clear) && binsof(cp_tx_count.full);
        bins set_ov = binsof(cp_tx_ovf.set)   && binsof(cp_tx_count.full);
        illegal_bins set_ill_empty = binsof(cp_tx_ovf.set) && binsof(cp_tx_count.empty);
        illegal_bins set_ill_one = binsof(cp_tx_ovf.set) && binsof(cp_tx_count.one);
        illegal_bins set_ill_mid = binsof(cp_tx_ovf.set) && binsof(cp_tx_count.mid);
        illegal_bins set_ill_mids = binsof(cp_tx_ovf.set) && binsof(cp_tx_count.mids);
    }

    cross_rx_ovf : cross cp_rx_ovf, cp_rx_count {
        bins clear_empty = binsof(cp_rx_ovf.clear) && binsof(cp_rx_count.empty);
        bins clear_one = binsof(cp_rx_ovf.clear) && binsof(cp_rx_count.one);
        bins clear_mid = binsof(cp_rx_ovf.clear) && binsof(cp_rx_count.mid);
        bins clear_mids = binsof(cp_rx_ovf.clear) && binsof(cp_rx_count.mids);
        bins clear_nov = binsof(cp_rx_ovf.clear) && binsof(cp_rx_count.full);
        bins set_ov = binsof(cp_rx_ovf.set)   && binsof(cp_rx_count.full);
        illegal_bins set_ill_empty = binsof(cp_rx_ovf.set) && binsof(cp_rx_count.empty);
        illegal_bins set_ill_one = binsof(cp_rx_ovf.set) && binsof(cp_rx_count.one);
        illegal_bins set_ill_mid = binsof(cp_rx_ovf.set) && binsof(cp_rx_count.mid);
        illegal_bins set_ill_mids = binsof(cp_rx_ovf.set) && binsof(cp_rx_count.mids);
    }

  endgroup


  // =========================
  // SPI CONFIG COVERAGE
  // =========================
  covergroup cg_spi_cfg @(posedge vif.PCLK);

    cp_enable : coverpoint ctrl_en;
    cp_mode   : coverpoint ctrl_mode;

    cp_width : coverpoint ctrl_width {
      bins b8  = {0};
      bins b16 = {1};
      bins b32 = {2};
      bins reserved = {3};
    }

    cp_lsb : coverpoint ctrl_lsb_first {
            bins lsb = {1};
            bins msb = {0};
    }

    cp_loopback : coverpoint ctrl_loopback;

    cross_transfer_matrix : cross cp_mode, cp_width, cp_lsb;
    cross_loopback_width : cross cp_loopback, cp_width;

  endgroup

  // =========================================================================
  // CLOCK DIVIDER COVERAGE
  // =========================================================================
  covergroup cg_clk_div @(posedge vif.PCLK);

    cp_div : coverpoint clk_div {
      bins div0 = {16'h0000};   
      bins div1 = {16'h0001};
      bins div2 = {16'h0002};
      bins div3 = {16'h0003};
      bins div255 = {16'h00FF};
      bins div1024 = {16'h0400};
      bins div_max = {16'hFFFF};     
      bins div_rand = {[16'h0004 : 16'hFE], [16'h101 : 16'h3FF], [16'h401 : 16'hFFFE]};
    }

  endgroup

  // =========================================================================
  // DELAY COVERAGE
  // =========================================================================
  covergroup cg_delay @(posedge vif.PCLK);

    cp_delay : coverpoint delay_cfg {
      bins zero = {8'h00};
      bins one  = {8'h01};
      bins high[] = {[8'h02 : 8'hFF]};
    }

  endgroup

  // =========================
  // INTERRUPT COVERAGE
  // =========================
  covergroup cg_irq @(posedge vif.PCLK);

    cp_irq_en : coverpoint int_en{
        bins disabled = {5'b00000};
        bins enabled[]  = {[5'b00001 : 5'b11111]};
    }

    cp_irq_st : coverpoint int_stat{
        bins disabled = {5'b00000};
        bins set[]  = {[5'b00001 : 5'b11111]};
    }
    cp_irq_out : coverpoint irq {
        bins irq_low = {0};
        bins irq_high = {1};
    }

    `define MASKED_CP(NAME, STAT_BIT, EN_BIT) \
    NAME : coverpoint (int_stat[STAT_BIT] & ~int_en[EN_BIT]) { \
        bins set_while_masked = {1'b1}; \
        bins not_masked       = {1'b0}; \
    }

    `MASKED_CP(cp_tx_empty_masked, IRQ_TX_EMPTY, IRQ_TX_EMPTY)
    `MASKED_CP(cp_rx_full_masked, IRQ_RX_FULL, IRQ_RX_FULL)
    `MASKED_CP(cp_tx_ovf_masked, IRQ_TX_OVF, IRQ_TX_OVF)
    `MASKED_CP(cp_rx_ovf_masked, IRQ_RX_OVF, IRQ_RX_OVF)
    `MASKED_CP(cp_done_masked, IRQ_TRANSFER_DONE, IRQ_TRANSFER_DONE)

     `undef MASKED_CP

    cross_irq : cross cp_irq_en, cp_irq_st, cp_irq_out {
      illegal_bins irq_high_all_masked =  binsof(cp_irq_out.irq_high) && binsof(cp_irq_en.disabled);
      illegal_bins irq_high_stat_clear = binsof(cp_irq_out.irq_high) && binsof(cp_irq_st.disabled);
    }

  endgroup


  // =========================================================================
  // W1C RACE CONDITION
  // =========================================================================
  covergroup cg_w1c_race @(posedge vif.PCLK);

    cp_w1c_while_pending : coverpoint
        (vif.psel & vif.penable & vif.pwrite & (vif.paddr == 8'h1C) & (int_stat != 5'b0)) {
      bins race_possible = {1'b1};
      bins no_race       = {1'b0};
    }

    cp_tx_ovf_w1c : coverpoint int_stat[2] iff
        (vif.psel & vif.penable & vif.pwrite & (vif.paddr == 8'h1C)  & vif.PWDATA[2]) {
      bins sticky_after_w1c = {1'b1};
      bins cleared = {1'b0};
    }

    cp_rx_ovf_w1c : coverpoint int_stat[3] iff
        (vif.psel & vif.penable & vif.pwrite & (vif.paddr == 8'h1C) & vif.PWDATA[3]) {
      bins sticky_after_w1c = {1'b1};
      bins cleared  = {1'b0};
    }

  endgroup

  // =========================
  // SS COVERAGE
  // =========================
  covergroup cg_ss @(posedge vif.PCLK);

    cp_ss_en : coverpoint ss_en;
    cp_ss_val : coverpoint ss_val;

    cross_ss_en_val : cross cp_ss_en, cp_ss_val;

  endgroup


  // =========================
  // REGISTER COVERAGE
  // =========================
  covergroup cg_regs @(posedge vif.PCLK);

    cp_ctrl_reset :  coverpoint ctrl_word iff (vif.presetn == 0) { 
      bins reset_val = {32'h0000_0000}; 
    }

    cp_status_reset : coverpoint status_word   iff (vif.presetn == 0) { 
      bins reset_val = {32'h0000_0014}; 
    }

        cp_tx_word_reset :  coverpoint tx_word iff (vif.presetn == 0) { 
      bins reset_val = {32'h0000_0000}; 
    }

    cp_rx_word_reset : coverpoint rx_word iff (vif.presetn == 0) { 
      bins reset_val = {32'h0000_0000}; 
    }

    cp_clk_div_word_reset : coverpoint clk_div_word iff (vif.presetn == 0) { 
      bins reset_val = {32'h0000_0000};
    }

    cp_ss_ctrl_word_reset : coverpoint ss_ctrl_word iff (vif.presetn == 0) { 
      bins reset_val = {32'h0000_0000}; 
    }

    cp_int_en_word_reset : coverpoint int_en_word iff (vif.presetn == 0) { 
      bins reset_val = {32'h0000_0000};
    }

    cp_int_stat_word_reset : coverpoint int_stat_word iff (vif.presetn == 0) { 
      bins reset_val = {32'h0000_0000}; 
    }

    cp_delay_word_reset : coverpoint delay_word iff (vif.presetn == 0) { 
      bins reset_val = {32'h0000_0000}; 
    }

  endgroup



  // =========================================================================
  // SPI CORE COVERAGE
  // =========================================================================
  covergroup cg_spi_core @(posedge vif.PCLK);

    cp_mosi : coverpoint spi_vif.mosi;
    cp_miso : coverpoint spi_vif.miso;
    cp_ss_n : coverpoint spi_vif.ss_n;

    cp_state : coverpoint core_state {
      bins idle   = {0};
      bins shift  = {1};
      bins finish = {2};
      bins gap    = {3};
    }

    cp_state_transitions : coverpoint core_state {
      bins t_idle_to_shift   = (0 => 1);
      bins t_shift_to_finish = (1 => 2);
      bins t_finish_to_idle  = (2 => 0);
      bins t_finish_to_gap   = (2 => 3);
      bins t_gap_to_idle     = (3 => 0);
  }

    cp_busy : coverpoint busy{
      bins idle = {0};
      bins busy = {1};
      bins idle_to_busy = (0 => 1);
      bins busy_to_idle = (1 => 0);
    }

    cp_mode : coverpoint cfg_mode {
      bins mode0 = {2'b00};
      bins mode1 = {2'b01};
      bins mode2 = {2'b10};
      bins mode3 = {2'b11};
    }

    cp_width : coverpoint cfg_width {
      bins w8  = {2'b00};
      bins w16 = {2'b01};
      bins w32 = {2'b10};
    }

    cp_lsb : coverpoint cfg_lsb_first {
      bins msb = {0};
      bins lsb = {1};
    }

    // R8, R24
    cp_div : coverpoint cfg_div iff(busy) {
      bins div0 = {16'h0000};   
      bins div1 = {16'h0001};
      bins div2 = {16'h0002};
      bins div3 = {16'h0003};
      bins div255 = {16'h00FF};
      bins div1024 = {16'h0400};
      bins div_max = {16'hFFFF};     
      bins div_rand = {[16'h0004 : 16'hFE], [16'h101 : 16'h3FF], [16'h401 : 16'hFFFE]};
    }

    cp_sclk : coverpoint spi_vif.sclk {
      bins low  = {0};
      bins high = {1};
    }

    cross_transfer_matrix : cross cp_mode, cp_width, cp_lsb;

    // R4
    cp_sclk_idle : cross cp_sclk, cp_mode iff (!busy) {
      bins mode0_idle = binsof(cp_mode.mode0) && binsof(cp_sclk.low);
      bins mode1_idle = binsof(cp_mode.mode1) && binsof(cp_sclk.low);
      bins mode2_idle = binsof(cp_mode.mode2) && binsof(cp_sclk.high);
      bins mode3_idle = binsof(cp_mode.mode3) && binsof(cp_sclk.high);
    }

    cross_mode_idle : cross cp_mode, cp_sclk_idle;
    cp_tx_pop : coverpoint tx_pop;
    cp_rx_push : coverpoint rx_push_valid;

    // R19
    cp_miso_diff: coverpoint {spi_vif.miso ^ spi_vif.mosi} iff (cfg_loopback) {
      bins diff = {1};
    }

    cp_loopback_transfer : coverpoint (ctrl_loopback && rx_push_valid);

    cross_loopback_width : cross cp_loopback_transfer, cp_width;
  
    // R25
    cp_mode_change_while_busy : coverpoint (busy && (latched_mode != cfg_mode)){
      bins mode_changed = {1};
    }

    cp_width_change_while_busy : coverpoint (busy && (latched_width != cfg_width)){
      bins width_changed = {1};
    }

    cp_div_change_while_busy : coverpoint (busy && (latched_div != cfg_div)){
      bins div_changed = {1};
    }

    cp_lsb_change_while_busy : coverpoint (busy && (latched_lsb != cfg_lsb_first)){
      bins lsb_changed = {1};
    }

    // R7
    cp_bit_cnt : coverpoint bit_cnt {
      bins start8  = {8};
      bins start16 = {16};
      bins start32 = {32};
      bins lastbit = {1};
      bins midbit[] = {[2:7], [9:15], [17:31]};
      illegal_bins overrun = {[33:63]};
    }

    cp_transfer_done_pulse : coverpoint transfer_done_pulse {
      bins pulse = {1};
      bins no_pulse = {0};
    }

    cross_width_bitcnt : cross cp_width, cp_bit_cnt {
      bins width8_start = binsof(cp_width.w8) && binsof(cp_bit_cnt.start8);
      bins width16_start = binsof(cp_width.w16) && binsof(cp_bit_cnt.start16);
      bins width32_start = binsof(cp_width.w32) && binsof(cp_bit_cnt.start32);
      illegal_bins wrong8 = binsof(cp_width.w8) && (binsof(cp_bit_cnt.start16) || binsof(cp_bit_cnt.start32));
      illegal_bins wrong16 = binsof(cp_width.w16) && (binsof(cp_bit_cnt.start8) || binsof(cp_bit_cnt.start32));
      illegal_bins wrong32 = binsof(cp_width.w32) && (binsof(cp_bit_cnt.start8) || binsof(cp_bit_cnt.start16));
    }

  endgroup


  // =========================
  // Constructor
  // =========================
  function new(virtual apb_if vif, virtual spi_if spi_vif);
    this.vif = vif;
    this.spi_vif = spi_vif;

    cg_apb = new();
    cg_fifo = new();
    cg_spi_cfg = new();
    cg_clk_div = new();
    cg_delay = new();
    cg_irq = new();
    cg_ss = new();
    cg_regs = new();
    cg_w1c_race = new();
    cg_spi_core = new();
  endfunction


  // =========================
  // Sample task
  // =========================
  task sample();
    cg_apb.sample();
    cg_fifo.sample();
    cg_spi_cfg.sample();
    cg_clk_div.sample();
    cg_delay.sample();
    cg_irq.sample();
    cg_ss.sample();
    cg_regs.sample();
    cg_w1c_race.sample();
    cg_spi_core.sample();
  endtask
endclass

`endif
