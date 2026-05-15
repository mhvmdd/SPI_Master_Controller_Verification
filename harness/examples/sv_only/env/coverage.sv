// =============================================================================
// coverage.sv  (SV-only starter scaffold)
// -----------------------------------------------------------------------------
// Minimal functional-coverage collector built on covergroups. Students must
// extend this to hit the 85% functional-coverage gate in the grading rubric.
// =============================================================================

`ifndef SPI_COVERAGE_COL_SV
`define SPI_COVERAGE_COL_SV

class spi_coverage_col;

    bit [1:0] cv_mode;
    bit       cv_lsb_first;
    bit [1:0] cv_width;

    covergroup cg_config;
        option.per_instance = 1;
        cp_mode : coverpoint cv_mode  {
            bins modes[] = {[0:3]};
        }
        cp_first : coverpoint cv_lsb_first {
            bins msb_first = {0};
            bins lsb_first = {1};
        }
        cp_width : coverpoint cv_width {
            bins w8  = {2'b00};
            bins w16 = {2'b01};
            bins w32 = {2'b10};
        }
        cx_mode_width : cross cp_mode, cp_width;
    endgroup

    function new();
        cg_config = new();
    endfunction

    task sample_config(input bit [1:0] mode,
                       input bit       lsb_first,
                       input bit [1:0] width);
        cv_mode      = mode;
        cv_lsb_first = lsb_first;
        cv_width     = width;
        cg_config.sample();
    endtask

endclass

`endif // SPI_COVERAGE_COL_SV
