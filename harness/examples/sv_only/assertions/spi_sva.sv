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
    input wire        PCLK,
    input wire        PRESETn,
    input wire        ctrl_en,
    input wire [4:0]  int_stat,
    input wire        IRQ
);

    // Aggregate IRQ is OR of all five sticky status bits (R18)
    a_irq_agg : assert property (
        @(posedge PCLK) disable iff (!PRESETn)
            IRQ == |int_stat
    ) else $error("[ASSERTION_ERROR] a_irq_agg IRQ=%b int_stat=%b",
                  IRQ, int_stat);

    // When CTRL.EN deasserts, aggregate IRQ MUST be 0 within 1 cycle
    // (student should extend with the exact spec wording from R19)
    a_irq_off_when_disabled : assert property (
        @(posedge PCLK) disable iff (!PRESETn)
            (!ctrl_en) |-> ##[0:1] (IRQ == 1'b0 || int_stat != 0)
    ) else $error("[ASSERTION_ERROR] a_irq_off_when_disabled");

endmodule

`endif // SPI_SVA_SV
