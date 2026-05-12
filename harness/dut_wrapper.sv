// =============================================================================
// dut_wrapper.sv
// -----------------------------------------------------------------------------
// Fixed DUT wrapper. Students MUST instantiate this wrapper (never the raw
// spi_master directly) so that the grader can swap the golden RTL for the
// faulty RTL without touching student testbench code.
//
// The wrapper takes interface handles (generic modports) and connects them to
// the DUT's flat port list. Because apb_if is a slave on the DUT side, and
// spi_if has the DUT driving SCLK/MOSI/SS_n/IRQ and consuming MISO, the raw
// signals are used directly without a specialised modport - this keeps the
// wrapper simple and portable across simulators.
//
// -----------------------------------------------------------------------------
// DUT internal hierarchy (exposed on purpose)
// -----------------------------------------------------------------------------
// spi_master is a thin top that wires two visible sub-blocks:
//
//   u_dut.u_regfile : apb_regfile  -- APB slave + register file + TX/RX FIFO
//   u_dut.u_core    : spi_core     -- SPI shift FSM + SCLK/MOSI drive
//
// Both can be probed by hierarchical name. Typical uses:
//
//   * Backdoor register read in an SV-only testbench or UVM RAL:
//         value = dut_wrapper_inst.u_dut.u_regfile.ctrl_en; // example
//
//   * `bind`-based SVA targets (use the *instance path* of your dut_wrapper
//     instance, e.g. `u_wrap`, NOT the bare module-type `dut_wrapper`):
//         bind u_wrap.u_dut.u_regfile my_regfile_sva ...
//         bind u_wrap.u_dut.u_core    my_core_sva    ...
//
// The register map, pinout, and all external behaviour are identical to the
// pre-split version. Students MAY rely on the hierarchy names for backdoor
// checks and bind points; the grader never varies them.
// =============================================================================

`ifndef SPI_DUT_WRAPPER_SV
`define SPI_DUT_WRAPPER_SV
`timescale 1ns/1ps

module dut_wrapper (
    apb_if apb,
    spi_if spi
);

    spi_master u_dut (
        .PCLK    (apb.pclk),
        .PRESETn (apb.presetn),
        .PSEL    (apb.psel),
        .PENABLE (apb.penable),
        .PWRITE  (apb.pwrite),
        .PADDR   (apb.paddr),
        .PWDATA  (apb.pwdata),
        .PRDATA  (apb.prdata),
        .PREADY  (apb.pready),
        .PSLVERR (apb.pslverr),
        .SCLK    (spi.sclk),
        .MOSI    (spi.mosi),
        .MISO    (spi.miso),
        .SS_n    (spi.ss_n),
        .IRQ     (spi.irq)
    );

endmodule

`endif // SPI_DUT_WRAPPER_SV
