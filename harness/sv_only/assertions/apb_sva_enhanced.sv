`ifndef APB_SVA_ENHANCED_SV
`define APB_SVA_ENHANCED_SV

module apb_sva_enhanced(
    apb_if apbif,

    // Control signals
    input wire                  ctrl_en,
    input wire                  ctrl_mstr,
    input wire [1:0]            ctrl_mode,
    input wire                  ctrl_lsb_first,
    input wire                  ctrl_loopback,
    input wire [1:0]            ctrl_width,

    // Clock divider configuration
    input wire [15:0]           clk_div,

    // Slave select control signals
    input wire [3:0]            ss_en,
    input wire [3:0]            ss_val,
    input wire [3:0]            ss_n,

    // Interrupt signals
    input wire [4:0]            int_en,
    input wire [4:0]            int_stat,
    input wire                  IRQ,

    // Delay configuration
    input wire [7:0]            delay_cfg,

    // APB transaction signals
    input wire                  apb_write,
    input wire                  apb_read,

    // TX FIFO interface signals
    input wire [3:0]            tx_count,
    input wire                  tx_push_accepted,
    input wire                  tx_push_dropped,
    input wire                  tx_full_w,
    input wire                  tx_empty_w,
    input wire                  tx_pop,

    // RX FIFO interface signals
    input wire [3:0]            rx_count,
    input wire                  rx_push_valid,
    input wire                  rx_pop_this_cycle,
    input wire                  rx_full_w,
    input wire                  rx_empty_w,

    // Core status -> regfile
    input wire                  busy_in,
    input wire                  transfer_done_pulse
);

    // =========================================================================
    // Local parameters
    // =========================================================================
    localparam [7:0] OFF_CTRL     = 8'h00;
    localparam [7:0] OFF_STATUS   = 8'h04;
    localparam [7:0] OFF_TX_DATA  = 8'h08;
    localparam [7:0] OFF_RX_DATA  = 8'h0C;
    localparam [7:0] OFF_CLK_DIV  = 8'h10;
    localparam [7:0] OFF_SS_CTRL  = 8'h14;
    localparam [7:0] OFF_INT_EN   = 8'h18;
    localparam [7:0] OFF_INT_STAT = 8'h1C;
    localparam [7:0] OFF_DELAY    = 8'h20;

    localparam integer IRQ_TX_EMPTY      = 0;
    localparam integer IRQ_RX_FULL       = 1;
    localparam integer IRQ_TX_OVF        = 2;
    localparam integer IRQ_RX_OVF        = 3;
    localparam integer IRQ_TRANSFER_DONE = 4;
    localparam integer IRQ_COUNT         = 5;

    localparam integer FIFO_DEPTH = 8;

    // =========================================================================
    // Composite register words (mirror RTL for checking)
    // =========================================================================
    wire [31:0] status_word = {
        25'b0,
        int_stat[IRQ_RX_OVF],     // [6]
        int_stat[IRQ_TX_OVF],     // [5]
        rx_empty_w,               // [4]
        rx_full_w,                // [3]
        tx_empty_w,               // [2]
        tx_full_w,                // [1]
        busy_in                   // [0]
    };

    wire [31:0] ctrl_word = {
        24'b0,
        ctrl_width,
        ctrl_loopback,
        ctrl_lsb_first,
        ctrl_mode,
        ctrl_mstr,
        ctrl_en
    };

    wire [31:0] ss_ctrl_word  = {24'b0, ss_val,    ss_en};
    wire [31:0] int_en_word   = {{(32-IRQ_COUNT){1'b0}}, int_en};
    wire [31:0] int_stat_word = {{(32-IRQ_COUNT){1'b0}}, int_stat};
    wire [31:0] clk_div_word  = {16'b0, clk_div};
    wire [31:0] delay_word    = {24'b0, delay_cfg};

    // =========================================================================
    // Helper signals
    // =========================================================================
    logic setup;
    assign setup = apbif.psel && !apbif.penable;

    logic access;
    assign access = apbif.psel && apbif.penable;

    logic rx_push_accepted;
    assign rx_push_accepted = rx_push_valid && !rx_full_w && ctrl_en;

    logic rx_push_dropped;
    assign rx_push_dropped = rx_push_valid && rx_full_w && ctrl_en;

    // =========================================================================
    // GROUP: APB Protocol — Mandatory Assertions (Spec §10.2)
    // =========================================================================

    // --- APB_1: PSEL held for 2 PCLK (setup + access) ---
    property p_apb_sel_stable;
        @(posedge apbif.pclk) disable iff (!apbif.presetn)
            $rose(apbif.psel) |-> $stable(apbif.psel) && !apbif.penable
                                  ##1 $stable(apbif.psel) && apbif.penable;
    endproperty

    a_apb_sel_stable : assert property (p_apb_sel_stable)
        else $error("[ASSERTION_ERROR] a_apb_sel_stable: PSEL not held for setup+access. PSel=%b PEnable=%b",
                    apbif.psel, apbif.penable);
    c_apb_sel_stable : cover property (p_apb_sel_stable);

    // --- APB_2: PENABLE only asserts while PSEL=1 ---
    property p_apb_enable;
        @(posedge apbif.pclk) disable iff (!apbif.presetn)
            $rose(apbif.penable) |-> apbif.psel;
    endproperty

    a_apb_enable : assert property (p_apb_enable)
        else $error("[ASSERTION_ERROR] a_apb_enable: PENABLE rose without PSEL. PSel=%b PEnable=%b",
                    apbif.psel, apbif.penable);
    c_apb_enable : cover property (p_apb_enable);

    // --- APB_3: PADDR/PWRITE/PWDATA stable setup→access ---
    property p_apb_transition_stable;
        @(posedge apbif.pclk) disable iff (!apbif.presetn)
            (setup) ##1 (access)
            |-> ($stable(apbif.paddr) && $stable(apbif.pwrite) && $stable(apbif.pwdata));
    endproperty

    a_apb_transition_stable : assert property (p_apb_transition_stable)
        else $error("[ASSERTION_ERROR] a_apb_transition_stable: APB signals not stable setup->access. Addr=%h Write=%b WData=%h",
                    apbif.paddr, apbif.pwrite, apbif.pwdata);
    c_apb_transition_stable : cover property (p_apb_transition_stable);

    // =========================================================================
    // GROUP: R1 — APB Register Read/Write
    // =========================================================================

    // --- R1: CTRL register read ---
    property p_ctrl_reg_rd;
        @(posedge apbif.pclk) disable iff (!apbif.presetn)
            (apb_read && apbif.paddr == OFF_CTRL) |-> (apbif.prdata == ctrl_word);
    endproperty

    a_ctrl_reg_rd : assert property (p_ctrl_reg_rd)
        else $error("[ASSERTION_ERROR] a_ctrl_reg_rd: CTRL read mismatch. Expected=%h Got=%h",
                    ctrl_word, apbif.prdata);
    c_ctrl_reg_rd : cover property (p_ctrl_reg_rd);

    // --- R1: CTRL register write ---
    property p_ctrl_reg_wr;
        @(posedge apbif.pclk) disable iff (!apbif.presetn)
            (apb_write && apbif.paddr == OFF_CTRL)
            |=> ($past(apbif.pwdata[7:0]) == ctrl_word[7:0]);
    endproperty

    a_ctrl_reg_wr : assert property (p_ctrl_reg_wr)
        else $error("[ASSERTION_ERROR] a_ctrl_reg_wr: CTRL write mismatch. Written=%h Actual=%h",
                    $past(apbif.pwdata[7:0]), ctrl_word[7:0]);
    c_ctrl_reg_wr : cover property (p_ctrl_reg_wr);

    // --- R1: STATUS register read ---
    property p_status_reg_rd;
        @(posedge apbif.pclk) disable iff (!apbif.presetn)
            (apb_read && apbif.paddr == OFF_STATUS) |-> (apbif.prdata == status_word);
    endproperty

    a_status_reg_rd : assert property (p_status_reg_rd)
        else $error("[ASSERTION_ERROR] a_status_reg_rd: STATUS read mismatch. Expected=%h Got=%h",
                    status_word, apbif.prdata);
    c_status_reg_rd : cover property (p_status_reg_rd);

    // --- R1: CLK_DIV register read ---
    property p_clk_div_reg_rd;
        @(posedge apbif.pclk) disable iff (!apbif.presetn)
            (apb_read && apbif.paddr == OFF_CLK_DIV) |-> (apbif.prdata == clk_div_word);
    endproperty

    a_clk_div_reg_rd : assert property (p_clk_div_reg_rd)
        else $error("[ASSERTION_ERROR] a_clk_div_reg_rd: CLK_DIV read mismatch. Expected=%h Got=%h",
                    clk_div_word, apbif.prdata);
    c_clk_div_reg_rd : cover property (p_clk_div_reg_rd);

    // --- R1: SS_CTRL register read ---
    property p_ss_ctrl_reg_rd;
        @(posedge apbif.pclk) disable iff (!apbif.presetn)
            (apb_read && apbif.paddr == OFF_SS_CTRL) |-> (apbif.prdata == ss_ctrl_word);
    endproperty

    a_ss_ctrl_reg_rd : assert property (p_ss_ctrl_reg_rd)
        else $error("[ASSERTION_ERROR] a_ss_ctrl_reg_rd: SS_CTRL read mismatch. Expected=%h Got=%h",
                    ss_ctrl_word, apbif.prdata);
    c_ss_ctrl_reg_rd : cover property (p_ss_ctrl_reg_rd);

    // --- R1: INT_EN register read ---
    property p_int_en_reg_rd;
        @(posedge apbif.pclk) disable iff (!apbif.presetn)
            (apb_read && apbif.paddr == OFF_INT_EN) |-> (apbif.prdata == int_en_word);
    endproperty

    a_int_en_reg_rd : assert property (p_int_en_reg_rd)
        else $error("[ASSERTION_ERROR] a_int_en_reg_rd: INT_EN read mismatch. Expected=%h Got=%h",
                    int_en_word, apbif.prdata);
    c_int_en_reg_rd : cover property (p_int_en_reg_rd);

    // --- R1: INT_STAT register read ---
    property p_int_stat_reg_rd;
        @(posedge apbif.pclk) disable iff (!apbif.presetn)
            (apb_read && apbif.paddr == OFF_INT_STAT) |-> (apbif.prdata == int_stat_word);
    endproperty

    a_int_stat_reg_rd : assert property (p_int_stat_reg_rd)
        else $error("[ASSERTION_ERROR] a_int_stat_reg_rd: INT_STAT read mismatch. Expected=%h Got=%h",
                    int_stat_word, apbif.prdata);
    c_int_stat_reg_rd : cover property (p_int_stat_reg_rd);

    // --- R1: DELAY register read ---
    property p_delay_reg_rd;
        @(posedge apbif.pclk) disable iff (!apbif.presetn)
            (apb_read && apbif.paddr == OFF_DELAY) |-> (apbif.prdata == delay_word);
    endproperty

    a_delay_reg_rd : assert property (p_delay_reg_rd)
        else $error("[ASSERTION_ERROR] a_delay_reg_rd: DELAY read mismatch. Expected=%h Got=%h",
                    delay_word, apbif.prdata);
    c_delay_reg_rd : cover property (p_delay_reg_rd);

    // =========================================================================
    // GROUP: R2 — Reset Values
    // =========================================================================
    always_comb begin
        if (!apbif.presetn) begin
            a_ctrl_reset : assert final (ctrl_word == 32'h0000_0000)
                else $error("[ASSERTION_ERROR] a_ctrl_reset: CTRL not 0 on reset. Got=%h", ctrl_word);

            a_status_reset : assert final (status_word == 32'h0000_0014)
                else $error("[ASSERTION_ERROR] a_status_reset: STATUS not 0x14 on reset. Got=%h", status_word);

            a_clk_div_reset : assert final (clk_div_word == 32'h0000_0000)
                else $error("[ASSERTION_ERROR] a_clk_div_reset: CLK_DIV not 0 on reset. Got=%h", clk_div_word);

            a_ss_ctrl_reset : assert final (ss_ctrl_word == 32'h0000_0000)
                else $error("[ASSERTION_ERROR] a_ss_ctrl_reset: SS_CTRL not 0 on reset. Got=%h", ss_ctrl_word);

            a_int_en_reset : assert final (int_en_word == 32'h0000_0000)
                else $error("[ASSERTION_ERROR] a_int_en_reset: INT_EN not 0 on reset. Got=%h", int_en_word);

            a_int_stat_reset : assert final (int_stat_word == 32'h0000_0000)
                else $error("[ASSERTION_ERROR] a_int_stat_reset: INT_STAT not 0 on reset. Got=%h", int_stat_word);

            a_delay_reset : assert final (delay_word == 32'h0000_0000)
                else $error("[ASSERTION_ERROR] a_delay_reset: DELAY not 0 on reset. Got=%h", delay_word);
        end
    end

    // =========================================================================
    // GROUP: R3 — CTRL.EN=0 holds FIFOs in reset
    // =========================================================================

    // --- R3: TX FIFO flushed when EN=0 ---
    property p_en0_tx_flush;
        @(posedge apbif.pclk) disable iff (!apbif.presetn)
            $fell(ctrl_en) |=> (tx_count == 4'd0);
    endproperty

    a_en0_tx_flush : assert property (p_en0_tx_flush)
        else $error("[ASSERTION_ERROR] a_en0_tx_flush: TX FIFO not flushed after EN=0. tx_count=%0d", tx_count);
    c_en0_tx_flush : cover property (p_en0_tx_flush);

    // --- R3: RX FIFO flushed when EN=0 ---
    property p_en0_rx_flush;
        @(posedge apbif.pclk) disable iff (!apbif.presetn)
            $fell(ctrl_en) |=> (rx_count == 4'd0);
    endproperty

    a_en0_rx_flush : assert property (p_en0_rx_flush)
        else $error("[ASSERTION_ERROR] a_en0_rx_flush: RX FIFO not flushed after EN=0. rx_count=%0d", rx_count);
    c_en0_rx_flush : cover property (p_en0_rx_flush);

    // =========================================================================
    // GROUP: R9 — TX FIFO Push
    // =========================================================================

    sequence s_txfifo_wr;
        setup && apbif.pwrite && apbif.paddr == OFF_TX_DATA
            && !tx_full_w && ctrl_en && tx_count < FIFO_DEPTH;
    endsequence

    property p_txfifo_wr;
        @(posedge apbif.pclk) disable iff (!apbif.presetn)
            s_txfifo_wr |=> tx_count == ($past(tx_count) + 1 - $past(tx_pop)) && apbif.pready;
    endproperty

    a_txfifo_wr : assert property (p_txfifo_wr)
        else $error("[ASSERTION_ERROR] a_txfifo_wr: TX FIFO push failed. tx_count=%0d past_count=%0d",
                    tx_count, $past(tx_count));
    c_txfifo_wr : cover property (p_txfifo_wr);

    // =========================================================================
    // GROUP: R10 — RX FIFO Pop
    // =========================================================================

    sequence s_rxfifo_rd;
        setup && !apbif.pwrite && rx_count > 0
            && apbif.paddr == OFF_RX_DATA && !rx_empty_w && ctrl_en && !rx_push_valid;
    endsequence

    property p_rxfifo_rd;
        @(posedge apbif.pclk) disable iff (!apbif.presetn)
            s_rxfifo_rd |=> rx_count == ($past(rx_count) - 1 + $past(rx_push_valid)) && apbif.pready;
    endproperty

    a_rxfifo_rd : assert property (p_rxfifo_rd)
        else $error("[ASSERTION_ERROR] a_rxfifo_rd: RX FIFO pop failed. rx_count=%0d past_count=%0d",
                    rx_count, $past(rx_count));
    c_rxfifo_rd : cover property (p_rxfifo_rd);

    // =========================================================================
    // GROUP: R11 — TX FIFO Full (depth = 8)
    // =========================================================================

    property p_txfifo_full;
        @(posedge apbif.pclk) disable iff (!apbif.presetn)
            (tx_push_accepted && tx_count == FIFO_DEPTH-1)
            |=> tx_count == $past(tx_count) + 1 && tx_full_w;
    endproperty

    a_txfifo_full : assert property (p_txfifo_full)
        else $error("[ASSERTION_ERROR] a_txfifo_full: TX_FULL not set on 8th entry. tx_full=%b tx_count=%0d",
                    tx_full_w, tx_count);
    c_txfifo_full : cover property (p_txfifo_full);

    // =========================================================================
    // GROUP: R12 — RX FIFO Full (depth = 8)
    // =========================================================================

    property p_rxfifo_full;
        @(posedge apbif.pclk) disable iff (!apbif.presetn)
            (rx_push_accepted && rx_count == FIFO_DEPTH-1 && !rx_pop_this_cycle)
            |=> rx_count == $past(rx_count) + 1 && rx_full_w;
    endproperty

    a_rxfifo_full : assert property (p_rxfifo_full)
        else $error("[ASSERTION_ERROR] a_rxfifo_full: RX_FULL not set on 8th entry. rx_full=%b rx_count=%0d",
                    rx_full_w, rx_count);
    c_rxfifo_full : cover property (p_rxfifo_full);

    // =========================================================================
    // GROUP: R13 — TX FIFO Overflow
    // =========================================================================

    property p_txfifo_ovf;
        @(posedge apbif.pclk) disable iff (!apbif.presetn)
            (tx_push_dropped && !tx_pop)
            |=> $rose(status_word[5]) && $rose(int_stat_word[IRQ_TX_OVF]);
    endproperty

    a_txfifo_ovf : assert property (p_txfifo_ovf)
        else $error("[ASSERTION_ERROR] a_txfifo_ovf: TX OVF not set on full push. tx_full=%b status[5]=%b",
                    tx_full_w, status_word[5]);
    c_txfifo_ovf : cover property (p_txfifo_ovf);

    // =========================================================================
    // GROUP: R14 — RX FIFO Overflow
    // =========================================================================

    property p_rxfifo_ovf;
        @(posedge apbif.pclk) disable iff (!apbif.presetn)
            (rx_push_dropped && !rx_pop_this_cycle)
            |=> status_word[6] && int_stat_word[IRQ_RX_OVF];
    endproperty

    a_rxfifo_ovf : assert property (p_rxfifo_ovf)
        else $error("[ASSERTION_ERROR] a_rxfifo_ovf: RX OVF not set on full push. rx_full=%b status[6]=%b",
                    rx_full_w, status_word[6]);
    c_rxfifo_ovf : cover property (p_rxfifo_ovf);

    // =========================================================================
    // GROUP: R15 — RX Read When Empty
    // =========================================================================

    property p_rxfifo_rd_empty;
        @(posedge apbif.pclk) disable iff (!apbif.presetn)
            (apb_read && apbif.paddr == OFF_RX_DATA && rx_empty_w)
            |-> apbif.pready && apbif.prdata == 32'h0000_0000;
    endproperty

    a_rxfifo_rd_empty : assert property (p_rxfifo_rd_empty)
        else $error("[ASSERTION_ERROR] a_rxfifo_rd_empty: Empty RX read returned non-zero. prdata=%h",
                    apbif.prdata);
    c_rxfifo_rd_empty : cover property (p_rxfifo_rd_empty);

    // =========================================================================
    // GROUP: R16 — IRQ Aggregation (Mandatory §10.2)
    // =========================================================================

    // Combinational check — must hold every delta cycle
    always_comb begin
        a_irq_agg : assert final (IRQ == |(int_stat & int_en))
            else $error("[ASSERTION_ERROR] a_irq_agg: IRQ mismatch. IRQ=%b int_stat=%b int_en=%b",
                        IRQ, int_stat, int_en);
    end

    // Concurrent version for coverage
    property p_irq_agg;
        @(posedge apbif.pclk) disable iff (!apbif.presetn)
            IRQ == |(int_stat & int_en);
    endproperty

    c_irq_agg : cover property (p_irq_agg);

    // =========================================================================
    // GROUP: R17 — INT_STAT W1C
    // =========================================================================

    property p_int_stat_w1c;
        @(posedge apbif.pclk) disable iff (!apbif.presetn)
            (apb_write && apbif.paddr == OFF_INT_STAT && !IRQ)
            |=> (int_stat_word[4:0] == ($past(int_stat_word[4:0]) & ~$past(apbif.pwdata[4:0])));
    endproperty

    a_int_stat_w1c : assert property (p_int_stat_w1c)
        else $error("[ASSERTION_ERROR] a_int_stat_w1c: W1C failed. prev_stat=%b wdata=%b cur_stat=%b",
                    $past(int_stat_word[4:0]), $past(apbif.pwdata[4:0]), int_stat_word[4:0]);
    c_int_stat_w1c : cover property (p_int_stat_w1c);

    // =========================================================================
    // GROUP: R18 — W1C Race (set wins over clear)
    // =========================================================================

    property p_w1c_race;
        @(posedge apbif.pclk) disable iff (!apbif.presetn)
            (apb_write && apbif.paddr == OFF_INT_STAT && IRQ)
            |=> IRQ;
    endproperty

    a_w1c_race : assert property (p_w1c_race)
        else $error("[ASSERTION_ERROR] a_w1c_race: W1C race lost event. IRQ dropped after concurrent set+clear.");
    c_w1c_race : cover property (p_w1c_race);

    // =========================================================================
    // GROUP: R20 — SS_n Combinational Equation
    // =========================================================================

    // Combinational — must hold every delta
    always_comb begin
        a_ss_ctrl : assert final (ss_n == (~ss_en | ss_val))
            else $error("[ASSERTION_ERROR] a_ss_ctrl: SS_n mismatch. SS_n=%b ss_en=%b ss_val=%b",
                        ss_n, ss_en, ss_val);
    end

    // =========================================================================
    // GROUP: R22 — Zero Wait-State (PREADY=1, PSLVERR=0)
    // =========================================================================

    property p_zero_wait;
        @(posedge apbif.pclk) disable iff (!apbif.presetn)
            (setup) |=> apbif.pready && !apbif.pslverr;
    endproperty

    a_zero_wait : assert property (p_zero_wait)
        else $error("[ASSERTION_ERROR] a_zero_wait: PREADY=%b PSLVERR=%b during access",
                    apbif.pready, apbif.pslverr);
    c_zero_wait : cover property (p_zero_wait);

    // =========================================================================
    // GROUP: R23 — Reserved Address Read Returns 0
    // =========================================================================

    property p_reserved_addr;
        @(posedge apbif.pclk) disable iff (!apbif.presetn)
            (setup && (apbif.paddr > 8'h20) && !apbif.pwrite)
            |=> apbif.pready && apbif.prdata == 32'h0000_0000;
    endproperty

    a_reserved_addr : assert property (p_reserved_addr)
        else $error("[ASSERTION_ERROR] a_reserved_addr: Reserved read non-zero. Addr=%h prdata=%h",
                    apbif.paddr, apbif.prdata);
    c_reserved_addr : cover property (p_reserved_addr);

endmodule

`endif // APB_SVA_ENHANCED_SV
