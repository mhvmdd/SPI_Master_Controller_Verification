// =============================================================================
// spi_core.sv
// -----------------------------------------------------------------------------
// Ain Shams University - Digital Design Verification - Spring 2026
// Final Project - SPI Master Controller, Shift / SCLK / SS engine sub-block
//
// Pure slave of apb_regfile. Consumes configuration (mode/width/div/delay/
// lsb/loopback/en/mstr/ss_en/ss_val), pops TX words from the regfile, and
// pushes RX words back. Drives SCLK/MOSI directly; SS_n is driven by the
// regfile so register readback of SS_CTRL matches what is on the pins.
//
// Contains the S_IDLE / S_SHIFT / S_FINISH / S_GAP FSM and all per-transfer
// latching required by R25 of the spec.
// =============================================================================

`default_nettype none
`timescale 1ns/1ps

module spi_core (
    input  wire         PCLK,
    input  wire         PRESETn,

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
    output reg          tx_pop,

    // core -> RX FIFO
    output reg          rx_push_valid,
    output reg  [31:0]  rx_push_data,

    // Status
    output wire         busy,
    output reg          transfer_done_pulse,

    // SPI pins
    output reg          SCLK,
    output reg          MOSI,
    input  wire         MISO
);

    // -------------------------------------------------------------------------
    // FSM
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] {
        S_IDLE   = 2'd0,
        S_SHIFT  = 2'd1,
        S_FINISH = 2'd2,
        S_GAP    = 2'd3
    } xfer_state_e;

    xfer_state_e state;

    reg [1:0]  xfer_mode;
    reg        xfer_lsb_first;
    reg [1:0]  xfer_width;
    reg [15:0] xfer_div;

    reg [31:0] sh_tx;
    reg [31:0] sh_rx;
    reg [5:0]  bit_cnt;
    reg [16:0] sclk_cnt;
    reg [8:0]  gap_cnt;
    reg        sclk_phase;

    wire [5:0] width_bits = (xfer_width == 2'b00) ? 6'd8  :
                            (xfer_width == 2'b01) ? 6'd16 : 6'd32;

    wire cpol = xfer_mode[1];
    wire cpha = xfer_mode[0];
    wire [16:0] half_period = {1'b0, xfer_div} + 17'd1;

    assign busy = (state != S_IDLE);

    wire miso_eff = cfg_loopback ? MOSI : MISO;

    // Helper functions
    function automatic logic get_tx_bit(input logic [31:0] v,
                                        input logic [5:0]  remaining,
                                        input logic [5:0]  total_bits,
                                        input logic        lsb_first);
        if (lsb_first)
            get_tx_bit = v[total_bits - remaining];
        else
            get_tx_bit = v[remaining - 1];
    endfunction

    function automatic logic [31:0] align_rx(input logic [31:0] sh,
                                             input logic [5:0]  total_bits);
        align_rx = sh & ((total_bits == 6'd32) ? 32'hFFFF_FFFF :
                         ((32'h1 << total_bits) - 32'h1));
    endfunction

    // -------------------------------------------------------------------------
    // FSM + datapath
    // -------------------------------------------------------------------------
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            state            <= S_IDLE;
            SCLK             <= 1'b0;
            MOSI             <= 1'b0;
            sh_tx            <= 32'h0;
            sh_rx            <= 32'h0;
            bit_cnt          <= 6'h0;
            sclk_cnt         <= 17'h0;
            sclk_phase       <= 1'b0;
            gap_cnt          <= 9'h0;
            xfer_mode        <= 2'b00;
            xfer_lsb_first   <= 1'b0;
            xfer_width       <= 2'b00;
            xfer_div         <= 16'h0;
            tx_pop           <= 1'b0;
            rx_push_valid    <= 1'b0;
            rx_push_data     <= 32'h0;
            transfer_done_pulse <= 1'b0;
        end else begin
            tx_pop              <= 1'b0;
            rx_push_valid       <= 1'b0;
            transfer_done_pulse <= 1'b0;

            if (!cfg_en) begin
                state      <= S_IDLE;
                SCLK       <= cfg_mode[1];   // hold at CPOL idle
                MOSI       <= 1'b0;
                sclk_cnt   <= 17'h0;
                sclk_phase <= 1'b0;
                gap_cnt    <= 9'h0;
            end else begin
                case (state)
                    // ---------------- IDLE ------------------------------------
                    S_IDLE: begin
                        SCLK <= cfg_mode[1];
                        // Start condition: TX has data, master mode, and at
                        // least one SS lane on the pins is driven low.
                        if (!tx_empty && cfg_mstr && (ss_n_drive != 4'hF)) begin
                            // Latch config for this transfer (R25)
                            xfer_mode      <= cfg_mode;
                            xfer_lsb_first <= cfg_lsb_first;
                            xfer_width     <= cfg_width;
                            xfer_div       <= cfg_clk_div;

                            sh_tx  <= tx_word;
                            tx_pop <= 1'b1;

                            bit_cnt    <= (cfg_width == 2'b00) ? 6'd8  :
                                          (cfg_width == 2'b01) ? 6'd16 : 6'd32;
                            sclk_cnt   <= 17'h0;
                            sclk_phase <= 1'b0;

                            // Present first bit immediately for CPHA=0
                            if (cfg_mode[0] == 1'b0) begin
                                MOSI <= cfg_lsb_first ? tx_word[0]
                                                      : tx_word[
                                                          ((cfg_width==2'b00)?7:
                                                           (cfg_width==2'b01)?15:31)];
                            end
                            sh_rx <= 32'h0;
                            state <= S_SHIFT;
                            SCLK  <= cfg_mode[1];
                        end
                    end

                    // ---------------- SHIFT -----------------------------------
                    S_SHIFT: begin
                        if (sclk_cnt == half_period - 1) begin
                            sclk_cnt   <= 17'h0;
                            sclk_phase <= ~sclk_phase;
                            SCLK       <= ~SCLK;

                            begin : edge_work
                                logic leading;
                                logic is_sample_edge;
                                logic is_launch_edge;
                                leading = ~sclk_phase;
                                is_sample_edge = (cpha == 1'b0) ? leading : ~leading;
                                is_launch_edge = ~is_sample_edge;

                                if (is_sample_edge) begin
                                    if (xfer_lsb_first) begin
                                        sh_rx[width_bits - bit_cnt] <= miso_eff;
                                    end else begin
                                        sh_rx[bit_cnt - 1] <= miso_eff;
                                    end

                                    if (bit_cnt == 6'd1) begin
                                        state <= S_FINISH;
                                    end
                                    bit_cnt <= bit_cnt - 6'd1;
                                end

                                if (is_launch_edge) begin
                                    if (bit_cnt > 6'd0) begin
                                        MOSI <= get_tx_bit(sh_tx, bit_cnt,
                                                           width_bits, xfer_lsb_first);
                                    end
                                end

                                // CPHA=1 first-bit-launch on very first edge
                                if (cpha == 1'b1 && leading && bit_cnt == width_bits) begin
                                    MOSI <= get_tx_bit(sh_tx, bit_cnt,
                                                       width_bits, xfer_lsb_first);
                                end
                            end
                        end else begin
                            sclk_cnt <= sclk_cnt + 17'h1;
                        end
                    end

                    // ---------------- FINISH ----------------------------------
                    S_FINISH: begin
                        if (sclk_cnt == half_period - 1) begin
                            sclk_cnt   <= 17'h0;
                            SCLK       <= cpol;
                            sclk_phase <= 1'b0;

                            rx_push_valid <= 1'b1;
                            rx_push_data  <= align_rx(sh_rx, width_bits);
                            transfer_done_pulse <= 1'b1;

                            if (!tx_empty && cfg_delay != 8'h0) begin
                                gap_cnt <= {1'b0, cfg_delay};
                                state   <= S_GAP;
                            end else begin
                                state <= S_IDLE;
                            end
                        end else begin
                            sclk_cnt <= sclk_cnt + 17'h1;
                        end
                    end

                    // ---------------- GAP -------------------------------------
                    S_GAP: begin
                        SCLK <= cpol;
                        if (sclk_cnt == half_period - 1) begin
                            sclk_cnt <= 17'h0;
                            if (gap_cnt == 9'h1) begin
                                state <= S_IDLE;
                            end
                            gap_cnt <= gap_cnt - 9'h1;
                        end else begin
                            sclk_cnt <= sclk_cnt + 17'h1;
                        end
                    end

                    default: state <= S_IDLE;
                endcase
            end
        end
    end

endmodule

`default_nettype wire
