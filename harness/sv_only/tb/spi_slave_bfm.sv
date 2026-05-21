// =============================================================================
// spi_slave_bfm.sv 
// -----------------------------------------------------------------------------
// SPI slave monitor/driver.
// Fully supports 8/16/32-bit widths, MSB/LSB first, and all 4 SPI modes.
// =============================================================================

`ifndef SPI_SLAVE_BFM_SV
`define SPI_SLAVE_BFM_SV
`timescale 1ns/1ps

module spi_slave_bfm (
    spi_if.slave  spi,
    input  logic [1:0]  mode,       // {CPOL, CPHA}
    input  logic [1:0]  width,      // 00=8b, 01=16b, 10=32b
    input  logic        lsb_first,  // 1=LSB-first, 0=MSB-first
    input  logic [31:0] miso_data,  // Word to drive back to master
    output logic [31:0] rx_capture, // Word captured from MOSI
    output logic        rx_valid    // 1-tick PCLK pulse when capture completes
);

    // -------------------------------------------------------------------------
    // 1. Parameter Decoding
    // -------------------------------------------------------------------------
    wire cpol = mode[1];
    wire cpha = mode[0];
    wire ss_act = (spi.ss_n != 4'hF);

    int num_bits;
    always_comb begin
        case(width)
            2'b00: num_bits = 8;
            2'b01: num_bits = 16;
            2'b10: num_bits = 32;
            default: num_bits = 8;
        endcase
    end

    // -------------------------------------------------------------------------
    // 2. Synchronous Edge Detection
    // -------------------------------------------------------------------------
    logic sclk_q;
    always @(spi.cb_slave) begin
        if (!ss_act) begin
            sclk_q <= cpol; // Idle state based on CPOL when not active
        end else begin
            sclk_q <= spi.sclk;
        end
    end

    wire sclk_rise = (sclk_q == 0 && spi.sclk == 1);
    wire sclk_fall = (sclk_q == 1 && spi.sclk == 0);

    // Resolve Sample and Launch edges based on CPOL and CPHA rules
    wire sample_edge = (cpol == cpha) ? sclk_rise : sclk_fall;
    wire launch_edge = (cpol == cpha) ? sclk_fall : sclk_rise;

    // -------------------------------------------------------------------------
    // 3. Shift Engine
    // -------------------------------------------------------------------------
    int bit_cnt;
    logic [31:0] shift_reg;
    logic [31:0] next_shift_reg;

    // Combinational MOSI capture logic
    always_comb begin
        next_shift_reg = shift_reg;
        if (sample_edge) begin
             if (lsb_first) next_shift_reg[bit_cnt] = spi.mosi;
             else           next_shift_reg[num_bits - 1 - bit_cnt] = spi.mosi;
        end
    end

    always @(spi.cb_slave) begin
        rx_valid <= 1'b0; // Default pulse low

        if (!ss_act) begin
            bit_cnt <= 0;
            shift_reg <= '0;
            
            // Setup MISO before the first sample edge if CPHA=0 (Mode 0 or 2)
            if (cpha == 0) begin
                spi.cb_slave.miso <= (lsb_first) ? miso_data[0] : miso_data[num_bits - 1];
            end else begin
                spi.cb_slave.miso <= 1'b0; // Park MISO when inactive
            end

        end else begin
            // --- Sample Phase ---
            if (sample_edge) begin
                shift_reg <= next_shift_reg;
                bit_cnt   <= bit_cnt + 1;

                // Transfer complete
                if (bit_cnt == num_bits - 1) begin
                    rx_capture <= next_shift_reg;
                    rx_valid   <= 1'b1;
                end
            end

            // --- Launch Phase ---
            if (launch_edge) begin
                // Ensure we don't index out of bounds on the trailing edge
                if (bit_cnt < num_bits) begin
                    spi.cb_slave.miso <= (lsb_first) ? miso_data[bit_cnt] : miso_data[num_bits - 1 - bit_cnt];
                end
            end
        end
    end

endmodule
`endif // SPI_SLAVE_BFM_SV