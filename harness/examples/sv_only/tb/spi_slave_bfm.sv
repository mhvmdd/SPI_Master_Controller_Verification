// =============================================================================
// spi_slave_bfm.sv  (SV-only starter scaffold)
// -----------------------------------------------------------------------------
// Minimal SPI slave responder. Drives MISO with a configurable pattern that
// is rotated on every sampled SCLK edge. Students should extend this to
// capture the MOSI stream into a queue and expose it to their scoreboard.
//
// This BFM mirrors the SPI mode from the DUT's CTRL register via a shared
// testbench "mode" input. Students MUST keep it in lock-step with CTRL.MODE
// when writing new tests.
// =============================================================================

`ifndef SPI_SLAVE_BFM_SV
`define SPI_SLAVE_BFM_SV
`timescale 1ns/1ps

module spi_slave_bfm (
    spi_if.slave  spi,
    input  logic  [1:0] mode,        // {CPOL, CPHA}
    input  logic  [7:0] miso_byte    // pattern repeatedly returned on MISO
);

    logic sclk_q;   // SCLK previous value for edge detection
    int   bit_idx;  // which bit of miso_byte is currently on the line

    wire cpol  = mode[1];
    wire cpha  = mode[0];
    wire ss_act = (spi.ss_n != 4'hF);

    initial begin
        spi.cb_slave.miso <= 1'b0;
        sclk_q  = cpol;
        bit_idx = 7;  // MSB-first by default; tests can override
    end

    // MISO shifter. For simplicity this BFM only supports CPOL=0 / CPHA=0
    // (mode 0). Students should generalise to all four modes to catch the
    // mode_coverage_test bugs.
    always @(posedge spi.pclk) begin
        if (!ss_act) begin
            bit_idx <= 7;
            spi.cb_slave.miso <= miso_byte[7];
        end else begin
            // Change MISO on the falling edge of SCLK (mode 0 convention
            // from the DUT's perspective: setup on falling, sample on rising)
            if (sclk_q === 1'b1 && spi.sclk === 1'b0) begin
                bit_idx <= (bit_idx == 0) ? 7 : bit_idx - 1;
                spi.cb_slave.miso <= miso_byte[(bit_idx == 0) ? 7 : bit_idx - 1];
            end
            sclk_q <= spi.sclk;
        end
    end

endmodule

`endif // SPI_SLAVE_BFM_SV
