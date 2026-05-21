// =============================================================================
// apb_master_bfm.sv
// -----------------------------------------------------------------------------
// Extended APB master BFM. Exposes apb_write, apb_read, and wait_not_busy.
// Tests will call these tasks via hierarchical reference (e.g., tb_top.u_apb_bfm.apb_write(...)).
// =============================================================================

`ifndef APB_MASTER_BFM_SV
`define APB_MASTER_BFM_SV
`timescale 1ns/1ps

module apb_master_bfm (apb_if.master apb);

    // Register offsets
    localparam [7:0] CTRL     = 8'h00;
    localparam [7:0] STATUS   = 8'h04;
    localparam [7:0] TX_DATA  = 8'h08;
    localparam [7:0] RX_DATA  = 8'h0C;
    localparam [7:0] CLK_DIV  = 8'h10;
    localparam [7:0] SS_CTRL  = 8'h14;
    localparam [7:0] INT_EN   = 8'h18;
    localparam [7:0] INT_STAT = 8'h1C;
    localparam [7:0] DELAY    = 8'h20;

    initial begin
        apb.cb_master.psel    <= 1'b0;
        apb.cb_master.penable <= 1'b0;
        apb.cb_master.pwrite  <= 1'b0;
        apb.cb_master.paddr   <= '0;
        apb.cb_master.pwdata  <= '0;
    end

    task automatic apb_write(input [7:0] addr, input [31:0] data);
        @(apb.cb_master);
        // SETUP phase
        apb.cb_master.psel    <= 1'b1;
        apb.cb_master.penable <= 1'b0;
        apb.cb_master.pwrite  <= 1'b1;
        apb.cb_master.paddr   <= addr;
        apb.cb_master.pwdata  <= data;
        
        @(apb.cb_master);
        // ACCESS phase
        apb.cb_master.penable <= 1'b1;
        
        // IP is a zero-wait-state slave (PREADY always 1 in ACCESS).
        // This loop will instantly pass, but is kept for APB standard compliance.
        do @(apb.cb_master); while (!apb.cb_master.pready);
        
        // deassert 
        apb.cb_master.psel    <= 1'b0;
        apb.cb_master.penable <= 1'b0;
        apb.cb_master.pwrite  <= 1'b0;
    endtask

    task automatic apb_read(input [7:0] addr, output [31:0] data);
        @(apb.cb_master);
        // SETUP phase
        apb.cb_master.psel    <= 1'b1;
        apb.cb_master.penable <= 1'b0;
        apb.cb_master.pwrite  <= 1'b0;
        apb.cb_master.paddr   <= addr;
        
        @(apb.cb_master);
        // ACCESS phase
        apb.cb_master.penable <= 1'b1;
        
        do @(apb.cb_master); while (!apb.cb_master.pready);
        
        data = apb.cb_master.prdata;
        
        apb.cb_master.psel    <= 1'b0;
        apb.cb_master.penable <= 1'b0;
    endtask

    // Extension: Helper task to poll the STATUS.BUSY bit (Bit 0)
    // Called by tests to wait for SPI transfers to complete.
    task automatic wait_not_busy();
        logic [31:0] status_val;
        do begin
            apb_read(STATUS, status_val);
        end while (status_val[0] == 1'b1);
    endtask

endmodule

`endif // APB_MASTER_BFM_SV