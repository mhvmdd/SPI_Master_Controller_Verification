// =============================================================================
// stim_lib.sv  (SV-only starter scaffold)
// -----------------------------------------------------------------------------
// Reusable randomisable transaction classes. Tests `new` these, call
// `randomize()`, and drive the resulting fields through the APB master BFM.
//
// NOTE: The scaffold only defines a single spi_txn class; students should
// add per-test variants as their coverage goals require.
// =============================================================================

`ifndef SPI_STIM_LIB_SV
`define SPI_STIM_LIB_SV

class spi_txn;
    rand bit [1:0]  mode;       // {CPOL, CPHA}
    rand bit        lsb_first;
    rand bit [1:0]  width;      // 00=8, 01=16, 10=32
    rand bit [15:0] clk_div;
    rand bit [7:0]  delay_cfg;
    rand bit [31:0] tx_data;
    rand bit        loopback;

    constraint c_width_legal  { width inside {[0:2]}; }
    constraint c_clk_div_sane { clk_div inside {[0:2048]}; }
    constraint c_delay_sane   { delay_cfg inside {[0:31]}; }

    function string sprint();
        return $sformatf("mode=%0d lsb=%0b width=%0d div=%0d delay=%0d tx=0x%08h lb=%0b",
                         mode, lsb_first, width, clk_div, delay_cfg, tx_data, loopback);
    endfunction
endclass

`endif // SPI_STIM_LIB_SV
