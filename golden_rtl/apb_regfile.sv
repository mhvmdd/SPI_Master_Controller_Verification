// =============================================================================
// apb_regfile.sv
// -----------------------------------------------------------------------------
// Ain Shams University - Digital Design Verification - Spring 2026
// Final Project - SPI Master Controller, APB Slave + Register File sub-block
//
// This is the APB-facing half of the DUT. It owns:
//   - APB v2.0 slave handshake (zero wait-state)
//   - All nine programmable registers (CTRL, STATUS, TX_DATA, RX_DATA,
//     CLK_DIV, SS_CTRL, INT_EN, INT_STAT, DELAY)
//   - TX and RX FIFO storage (8 x 32 each)
//   - Interrupt sticky logic with W1C priority (R18)
//   - SS_n drive from SS_CTRL (R20)
//
// It is a pure slave of the SPI core: the core tells us when to pop TX, when
// to push RX, and when a transfer completed. Per-transfer configuration is
// still driven out as a flat cfg_* bus (the core latches it on start, per R25).
// =============================================================================

`default_nettype none
`timescale 1ns/1ps

module apb_regfile (
    input  wire         PCLK,
    input  wire         PRESETn,

    // APB slave
    input  wire         PSEL,
    input  wire         PENABLE,
    input  wire         PWRITE,
    input  wire [7:0]   PADDR,
    input  wire [31:0]  PWDATA,
    output reg  [31:0]  PRDATA,
    output wire         PREADY,
    output wire         PSLVERR,

    // Configuration to core
    output wire         cfg_en,
    output wire         cfg_mstr,
    output wire [1:0]   cfg_mode,
    output wire         cfg_lsb_first,
    output wire         cfg_loopback,
    output wire [1:0]   cfg_width,
    output wire [15:0]  cfg_clk_div,
    output wire [7:0]   cfg_delay,

    // SS lane drive (combinational, outputs via SS_n)
    output wire [3:0]   SS_n,

    // TX FIFO interface to core
    output wire [31:0]  tx_word,        // head of TX FIFO
    output wire         tx_empty,
    input  wire         tx_pop,         // core pops one word

    // RX FIFO interface from core
    input  wire         rx_push_valid,
    input  wire [31:0]  rx_push_data,

    // Core status -> regfile
    input  wire         busy_in,
    input  wire         transfer_done_pulse,

    // Aggregate interrupt
    output wire         IRQ
);

    // -------------------------------------------------------------------------
    // Register offsets
    // -------------------------------------------------------------------------
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

    // -------------------------------------------------------------------------
    // Configuration registers
    // -------------------------------------------------------------------------
    reg        ctrl_en;
    reg        ctrl_mstr;
    reg [1:0]  ctrl_mode;       // {CPOL, CPHA}
    reg        ctrl_lsb_first;
    reg        ctrl_loopback;
    reg [1:0]  ctrl_width;

    reg [15:0] clk_div;
    reg [3:0]  ss_en;
    reg [3:0]  ss_val;
    reg [IRQ_COUNT-1:0] int_en;
    reg [IRQ_COUNT-1:0] int_stat;
    reg [7:0]  delay_cfg;

    // -------------------------------------------------------------------------
    // APB handshake
    // -------------------------------------------------------------------------
    wire apb_access = PSEL & PENABLE;
    wire apb_write  = apb_access &  PWRITE;
    wire apb_read   = apb_access & ~PWRITE;
    assign PREADY   = 1'b1;
    assign PSLVERR  = 1'b0;

    // -------------------------------------------------------------------------
    // FIFO storage - 8 deep, 32 wide
    // -------------------------------------------------------------------------
    localparam integer FIFO_DEPTH = 8;
    localparam integer FIFO_AW    = 3;

    reg [31:0] tx_mem   [0:FIFO_DEPTH-1];
    reg [FIFO_AW:0] tx_wp, tx_rp;
    wire [FIFO_AW:0] tx_count = tx_wp - tx_rp;
    wire tx_full_w  = (tx_count == FIFO_DEPTH);
    wire tx_empty_w = (tx_count == 0);

    reg [31:0] rx_mem   [0:FIFO_DEPTH-1];
    reg [FIFO_AW:0] rx_wp, rx_rp;
    wire [FIFO_AW:0] rx_count = rx_wp - rx_rp;
    wire rx_full_w  = (rx_count == FIFO_DEPTH);
    wire rx_empty_w = (rx_count == 0);

    assign tx_empty = tx_empty_w;
    assign tx_word  = tx_mem[tx_rp[FIFO_AW-1:0]];

    // -------------------------------------------------------------------------
    // Combinational APB read data
    // -------------------------------------------------------------------------
    wire [31:0] status_word = {
        25'b0,
        int_stat[IRQ_RX_OVF],     // [6] RX_OVF
        int_stat[IRQ_TX_OVF],     // [5] TX_OVF
        rx_empty_w,               // [4] RX_EMPTY (reset = 1)
        rx_full_w,                // [3] RX_FULL
        tx_empty_w,               // [2] TX_EMPTY (reset = 1)
        tx_full_w,                // [1] TX_FULL
        busy_in                   // [0] BUSY
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

    reg rx_pop_this_cycle;
    always @(*) begin
        rx_pop_this_cycle = 1'b0;
        PRDATA = 32'h0;
        if (apb_read) begin
            case (PADDR)
                OFF_CTRL    : PRDATA = ctrl_word;
                OFF_STATUS  : PRDATA = status_word;
                OFF_TX_DATA : PRDATA = 32'h0;                // WO
                OFF_RX_DATA : begin
                    PRDATA = rx_empty_w ? 32'h0 : rx_mem[rx_rp[FIFO_AW-1:0]];
                    rx_pop_this_cycle = ~rx_empty_w;         // R15: empty read no OVF
                end
                OFF_CLK_DIV : PRDATA = clk_div_word;
                OFF_SS_CTRL : PRDATA = ss_ctrl_word;
                OFF_INT_EN  : PRDATA = int_en_word;
                OFF_INT_STAT: PRDATA = int_stat_word;
                OFF_DELAY   : PRDATA = delay_word;
                default     : PRDATA = 32'h0;                // R23
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // TX push side
    // -------------------------------------------------------------------------
    reg tx_push_valid;
    reg [31:0] tx_push_data;

    always @(*) begin
        tx_push_valid = 1'b0;
        tx_push_data  = 32'h0;
        if (apb_write && PADDR == OFF_TX_DATA && ctrl_en) begin
            tx_push_valid = 1'b1;
            case (ctrl_width)
                2'b00: tx_push_data = {24'b0, PWDATA[7:0]};
                2'b01: tx_push_data = {16'b0, PWDATA[15:0]};
                default: tx_push_data = PWDATA;
            endcase
        end
    end

    wire tx_push_accepted = tx_push_valid & ~tx_full_w;
    wire tx_push_dropped  = tx_push_valid &  tx_full_w;   // sets TX_OVF

    // -------------------------------------------------------------------------
    // Configuration register bank
    // -------------------------------------------------------------------------
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            ctrl_en        <= 1'b0;
            ctrl_mstr      <= 1'b0;
            ctrl_mode      <= 2'b00;
            ctrl_lsb_first <= 1'b0;
            ctrl_loopback  <= 1'b0;
            ctrl_width     <= 2'b00;
            clk_div        <= 16'h0;
            ss_en          <= 4'h0;
            ss_val         <= 4'h0;
            int_en         <= '0;
            int_stat       <= '0;
            delay_cfg      <= 8'h0;
        end else begin
            if (apb_write) begin
                case (PADDR)
                    OFF_CTRL: begin
                        ctrl_width     <= PWDATA[7:6];
                        ctrl_loopback  <= PWDATA[5];
                        ctrl_lsb_first <= PWDATA[4];
                        ctrl_mode      <= PWDATA[3:2];
                        ctrl_mstr      <= PWDATA[1];
                        ctrl_en        <= PWDATA[0];
                    end
                    OFF_CLK_DIV: clk_div <= PWDATA[15:0];
                    OFF_SS_CTRL: begin
                        ss_val <= PWDATA[7:4];
                        ss_en  <= PWDATA[3:0];
                    end
                    OFF_INT_EN : int_en    <= PWDATA[IRQ_COUNT-1:0];
                    OFF_DELAY  : delay_cfg <= PWDATA[7:0];
                    default: ;
                endcase
            end

            // ----- INT_STAT update (R18 W1C priority) ------------------------
            //   1) default: hold value
            //   2) apply W1C mask
            //   3) OR in new events (so set+clear stays set)
            begin : int_stat_update
                reg [IRQ_COUNT-1:0] next_stat;
                next_stat = int_stat;

                if (apb_write && PADDR == OFF_INT_STAT) begin
                    next_stat = next_stat & ~PWDATA[IRQ_COUNT-1:0];
                end

                if (tx_push_dropped)
                    next_stat[IRQ_TX_OVF] = 1'b1;
                if (rx_push_valid && rx_full_w)
                    next_stat[IRQ_RX_OVF] = 1'b1;
                if (rx_push_valid && !rx_full_w && (rx_count == FIFO_DEPTH-1))
                    next_stat[IRQ_RX_FULL] = 1'b1;
                if (tx_pop && (tx_count == 1))
                    next_stat[IRQ_TX_EMPTY] = 1'b1;
                if (transfer_done_pulse)
                    next_stat[IRQ_TRANSFER_DONE] = 1'b1;

                int_stat <= next_stat;
            end
        end
    end

    assign IRQ  = |(int_stat & int_en);
    assign SS_n = ~ss_en | ss_val;    // R20

    // -------------------------------------------------------------------------
    // TX FIFO storage
    // -------------------------------------------------------------------------
    integer i;
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            tx_wp <= '0;
            tx_rp <= '0;
            for (i = 0; i < FIFO_DEPTH; i = i + 1) tx_mem[i] <= 32'h0;
        end else if (!ctrl_en) begin
            tx_wp <= '0;
            tx_rp <= '0;
        end else begin
            if (tx_push_accepted) begin
                tx_mem[tx_wp[FIFO_AW-1:0]] <= tx_push_data;
                tx_wp <= tx_wp + 1'b1;
            end
            if (tx_pop) begin
                tx_rp <= tx_rp + 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // RX FIFO storage
    // -------------------------------------------------------------------------
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            rx_wp <= '0;
            rx_rp <= '0;
            for (i = 0; i < FIFO_DEPTH; i = i + 1) rx_mem[i] <= 32'h0;
        end else if (!ctrl_en) begin
            rx_wp <= '0;
            rx_rp <= '0;
        end else begin
            if (rx_push_valid && !rx_full_w) begin
                rx_mem[rx_wp[FIFO_AW-1:0]] <= rx_push_data;
                rx_wp <= rx_wp + 1'b1;
            end
            if (rx_pop_this_cycle) begin
                rx_rp <= rx_rp + 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Outputs to core
    // -------------------------------------------------------------------------
    assign cfg_en        = ctrl_en;
    assign cfg_mstr      = ctrl_mstr;
    assign cfg_mode      = ctrl_mode;
    assign cfg_lsb_first = ctrl_lsb_first;
    assign cfg_loopback  = ctrl_loopback;
    assign cfg_width     = ctrl_width;
    assign cfg_clk_div   = clk_div;
    assign cfg_delay     = delay_cfg;

endmodule

`default_nettype wire
