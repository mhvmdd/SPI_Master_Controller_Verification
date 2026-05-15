// =============================================================================
// apb_master_bfm.sv  (SV-only starter scaffold)
// -----------------------------------------------------------------------------
// Minimal APB master BFM. Exposes two tasks: apb_write / apb_read. Uses the
// `cb_master` clocking block of apb_if.
//
// This is *not* UVM - it is just a module with tasks that the test programs
// call via a hierarchical reference (`tb_top.u_apb_bfm.apb_write(...)`).
// =============================================================================

`ifndef APB_MASTER_BFM_SV
`define APB_MASTER_BFM_SV
`timescale 1ns/1ps

module apb_master_bfm (apb_if.master apb);

    // Register offsets - duplicated from the spec so students can call:
    //   apb_write(CTRL,   32'h0000_0001);
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
        apb.cb_master.psel    <= 1'b1;
        apb.cb_master.penable <= 1'b0;
        apb.cb_master.pwrite  <= 1'b1;
        apb.cb_master.paddr   <= addr;
        apb.cb_master.pwdata  <= data;
        @(apb.cb_master);
        apb.cb_master.penable <= 1'b1;
        do @(apb.cb_master); while (!apb.cb_master.pready);
        apb.cb_master.psel    <= 1'b0;
        apb.cb_master.penable <= 1'b0;
        apb.cb_master.pwrite  <= 1'b0;
    endtask

    task automatic apb_read(input [7:0] addr, output [31:0] data);
        @(apb.cb_master);
        apb.cb_master.psel    <= 1'b1;
        apb.cb_master.penable <= 1'b0;
        apb.cb_master.pwrite  <= 1'b0;
        apb.cb_master.paddr   <= addr;
        @(apb.cb_master);
        apb.cb_master.penable <= 1'b1;
        do @(apb.cb_master); while (!apb.cb_master.pready);
        data = apb.cb_master.prdata;
        apb.cb_master.psel    <= 1'b0;
        apb.cb_master.penable <= 1'b0;
    endtask

endmodule

`endif // APB_MASTER_BFM_SV
