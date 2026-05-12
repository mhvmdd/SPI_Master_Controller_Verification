// =============================================================================
// apb_if.sv
// -----------------------------------------------------------------------------
// APB v2.0 interface used to drive the SPI Master DUT from the testbench.
// Signal names match the spec exactly. Clocking blocks are provided so students
// can use either Verilog-style bind or SystemVerilog-style clocking-block
// drivers.
// =============================================================================

`ifndef SPI_APB_IF_SV
`define SPI_APB_IF_SV
`timescale 1ns/1ps

interface apb_if #(parameter int AW = 8, parameter int DW = 32) (
    input logic pclk,
    input logic presetn
);

    logic              psel;
    logic              penable;
    logic              pwrite;
    logic [AW-1:0]     paddr;
    logic [DW-1:0]     pwdata;
    logic [DW-1:0]     prdata;
    logic              pready;
    logic              pslverr;

    // --------------- Master-side clocking block (TB drives DUT) -------------
    clocking cb_master @(posedge pclk);
        default input #1step output #1;
        output psel, penable, pwrite, paddr, pwdata;
        input  prdata, pready, pslverr;
    endclocking

    // --------------- Monitor-side clocking block ----------------------------
    clocking cb_monitor @(posedge pclk);
        default input #1step;
        input psel, penable, pwrite, paddr, pwdata;
        input prdata, pready, pslverr;
    endclocking

    modport master  (clocking cb_master,  input pclk, presetn);
    modport monitor (clocking cb_monitor, input pclk, presetn);

endinterface

`endif // SPI_APB_IF_SV
