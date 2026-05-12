// =============================================================================
// spi_if.sv
// -----------------------------------------------------------------------------
// SPI-side pins of the DUT. From the TB point of view, SCLK, MOSI and SS_n are
// inputs (driven by the DUT) and MISO is an output (driven by the TB slave
// responder). Students must supply the slave responder/monitor logic.
// =============================================================================

`ifndef SPI_SPI_IF_SV
`define SPI_SPI_IF_SV
`timescale 1ns/1ps

interface spi_if (input logic pclk);

    logic        sclk;
    logic        mosi;
    logic        miso;
    logic [3:0]  ss_n;
    logic        irq;

    // TB-slave clocking block - drive MISO in response to sample edges.
    // The clock here is PCLK (the DUT's reference clock) because SCLK is a
    // generated signal and should only be observed, not used as a testbench
    // clock (to avoid glitch-sampling issues).
    clocking cb_slave @(posedge pclk);
        default input #1step output #0;
        input  sclk, mosi, ss_n, irq;
        output miso;
    endclocking

    clocking cb_mon @(posedge pclk);
        default input #1step;
        input sclk, mosi, miso, ss_n, irq;
    endclocking

    // The `slave` modport exposes the clocking block (preferred for driving
    // MISO) AND the raw observable signals, so a BFM that wants to do
    // edge-detection on SCLK or check SS_n outside the clocking block can do
    // so without a hierarchical reach-around. MISO stays driven only via
    // `cb_slave.miso` to avoid double-driver elaboration errors.
    modport slave   (clocking cb_slave,   input pclk,
                     input sclk, input mosi, input ss_n, input irq);
    modport monitor (clocking cb_mon,     input pclk);

endinterface

`endif // SPI_SPI_IF_SV
