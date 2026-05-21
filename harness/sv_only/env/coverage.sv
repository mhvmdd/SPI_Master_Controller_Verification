// =============================================================================
// coverage.sv
// -----------------------------------------------------------------------------
// Spec-compliant functional coverage collector
// Driven actively by test sequences via sample() tasks.
// =============================================================================

`ifndef SPI_COVERAGE_COL_SV
`define SPI_COVERAGE_COL_SV

class spi_coverage_col;

    // -------------------------------------------------------------------------
    // Coverage Variables
    // -------------------------------------------------------------------------
    bit [1:0]  cv_mode;
    bit [1:0]  cv_width;
    bit        cv_lsb_first;
    bit [15:0] cv_clk_div;
    bit [7:0]  cv_delay;
    bit        cv_loopback;

    bit [4:0]  cv_tx_count;
    bit [4:0]  cv_rx_count;

    bit [7:0] cv_reg_addr;
    bit       cv_reg_is_write; // 1 = Write, 0 = Read
    bit       cv_reg_is_reset; // 1 = Checking reset value, 0 = Normal operation

    bit [4:0]  cv_int_stat;
    bit [4:0]  cv_int_en;
    bit        cv_w1c_event; // Set to 1 when a test performs a W1C clear

    // -------------------------------------------------------------------------
    // Covergroups 
    // -------------------------------------------------------------------------

    // 1. SPI Modes x Widths x LSB/MSB (24 bins) + DELAY + CLK_DIV
    covergroup cg_config;
        option.per_instance = 1;
        
        cp_mode  : coverpoint cv_mode { bins modes[] = {[0:3]}; }
        cp_width : coverpoint cv_width {
            bins w8  = {2'b00};
            bins w16 = {2'b01};
            bins w32 = {2'b10};
        }
        cp_first : coverpoint cv_lsb_first { bins msb = {0}; bins lsb = {1}; }
        
        cp_delay : coverpoint cv_delay {
            bins zero  = {8'h00};
            bins one   = {8'h01};
            bins large_b = {[8'h80 : 8'hFF]}; // >= 128
        }
        
        cp_clk_div : coverpoint cv_clk_div {
            bins c0    = {16'h0000};
            bins c1    = {16'h0001};
            bins c2    = {16'h0002};
            bins c3    = {16'h0003};
            bins c255  = {16'h00FF};
            bins c1024 = {16'h0400};
            bins cmax  = {16'hFFFF};
            bins rand_mid = {[16'h0004 : 16'h00FE], [16'h0100 : 16'h03FF], [16'h0401 : 16'hFFFE]};
        }

        cp_loopback : coverpoint cv_loopback { bins active = {1}; }

        // All 4 SPI modes x all 3 widths x MSB/LSB = 24 bins
        cx_mode_width_lsb : cross cp_mode, cp_width, cp_first;
        // Loopback mode per width
        cx_loopback_width : cross cp_loopback, cp_width;
    endgroup

    // 2. FIFO Occupancy (empty, 1, mid, 7, full)
    covergroup cg_fifo;
        option.per_instance = 1;
        
        cp_tx_count : coverpoint cv_tx_count {
            bins empty = {0};
            bins one   = {1};
            bins mid   = {4};
            bins seven = {7};
            bins full  = {8};
        }
        cp_rx_count : coverpoint cv_rx_count {
            bins empty = {0};
            bins one   = {1};
            bins mid   = {4};
            bins seven = {7};
            bins full  = {8};
        }
    endgroup

    // 3. Interrupts (Asserted, Masked, W1C)
    covergroup cg_interrupts;
        option.per_instance = 1;

        // Helper macro for the 5 interrupts
        `define IRQ_BINS(NAME, BIT_IDX) \
        NAME : coverpoint cv_int_stat[BIT_IDX] { \
            bins asserted = {1}; \
        } \
        NAME``_masked : coverpoint (cv_int_stat[BIT_IDX] && !cv_int_en[BIT_IDX]) { \
            bins asserted_while_masked = {1}; \
        } \
        NAME``_w1c : cross NAME, cv_w1c_event { \
            bins cleared_via_w1c = binsof(NAME.asserted) && binsof(cv_w1c_event) intersect {1}; \
        }

        `IRQ_BINS(cp_tx_empty, 0)
        `IRQ_BINS(cp_rx_full,  1)
        `IRQ_BINS(cp_tx_ovf,   2)
        `IRQ_BINS(cp_rx_ovf,   3)
        `IRQ_BINS(cp_done,     4)

        `undef IRQ_BINS
    endgroup

    // 4. Register Access (Written, Read, Reset Observed)
    covergroup cg_regs;
        option.per_instance = 1;
        
        cp_addr : coverpoint cv_reg_addr {
            bins ctrl     = {8'h00};
            bins status   = {8'h04};
            bins tx       = {8'h08};
            bins rx       = {8'h0C};
            bins clk_div  = {8'h10};
            bins ss_ctrl  = {8'h14};
            bins int_en   = {8'h18};
            bins int_stat = {8'h1C};
            bins delay    = {8'h20};
        }
        
        cp_op : coverpoint cv_reg_is_write {
            bins read  = {0};
            bins write = {1};
        }
        
        cp_reset_check : coverpoint cv_reg_is_reset {
            bins is_reset = {1};
        }

        // Cross 1: Proves we read AND wrote every register
        cx_rw_all : cross cp_addr, cp_op {
            // Read-only and Write-only exceptions (we can't write STATUS, can't read TX)
            ignore_bins ro_writes = binsof(cp_addr.status) && binsof(cp_op.write);
            ignore_bins wo_reads  = binsof(cp_addr.tx) && binsof(cp_op.read);
            ignore_bins rx_writes = binsof(cp_addr.rx) && binsof(cp_op.write);
        }

        // Cross 2: Proves we checked the reset value of every register
        cx_reset_all : cross cp_addr, cp_reset_check;
    endgroup


    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------
    function new();
        cg_config     = new();
        cg_fifo       = new();
        cg_interrupts = new();
        cg_regs       = new();
    endfunction

    // -------------------------------------------------------------------------
    // Explicit Sampling Tasks (Called by your tests!)
    // -------------------------------------------------------------------------
    
    task sample_config(input bit [1:0] mode, input bit [1:0] width, input bit lsb_first, 
                       input bit [15:0] clk_div, input bit [7:0] delay, input bit loopback);
        this.cv_mode      = mode;
        this.cv_width     = width;
        this.cv_lsb_first = lsb_first;
        this.cv_clk_div   = clk_div;
        this.cv_delay     = delay;
        this.cv_loopback  = loopback;
        cg_config.sample();
    endtask

    // Tests call this and pass the internal hierarchical wires for exact occupancy
    task sample_fifo(input bit [4:0] tx_count, input bit [4:0] rx_count);
        this.cv_tx_count = tx_count;
        this.cv_rx_count = rx_count;
        cg_fifo.sample();
    endtask

    // Tests call this after reading INT_STAT or doing a W1C write
    task sample_interrupts(input bit [4:0] stat, input bit [4:0] en, input bit is_w1c);
        this.cv_int_stat  = stat;
        this.cv_int_en    = en;
        this.cv_w1c_event = is_w1c;
        cg_interrupts.sample();
    endtask

    task sample_reg_access(input bit [7:0] addr, input bit is_write, input bit is_reset_check);
        this.cv_reg_addr     = addr;
        this.cv_reg_is_write = is_write;
        this.cv_reg_is_reset = is_reset_check;
        cg_regs.sample();
    endtask

endclass

`endif // SPI_COVERAGE_COL_SV