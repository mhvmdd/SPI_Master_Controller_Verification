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

    localparam int TIMEOUT_CYCLES = 100;

    task automatic drive_idle();
        apb.cb_master.psel    <= 1'b0;
        apb.cb_master.penable <= 1'b0;
        apb.cb_master.pwrite  <= 1'b0;
        apb.cb_master.paddr   <= '0;
        apb.cb_master.pwdata  <= '0;
    endtask

    initial begin
        drive_idle();
    end

    task automatic wait_ready(string task_name , input [7:0] addr);
        int timeout;
        timeout = 0;
        do begin
            @(apb.cb_master);
                timeout++;

            if(timeout >= TIMEOUT_CYCLES)
                $fatal("[APB_BFM] Timeout for PREADY in %s addr=%h time=%0t", task_name , addr, $time);
        end
        while(!apb.cb_master.pready);

        if(apb.cb_master.pslverr)                   //R22:check that it is in assertion,if(yes) => remove this if condition no need
            $display("[SCOREBOARD_ERROR] [check_pslverr] PSLVERR asserted at addr=%h time=%0t", addr, $time);
    endtask

    task automatic apb_write(input [7:0] addr, input [31:0] data);
        @(apb.cb_master);
        //Setup Phase
        apb.cb_master.psel    <= 1'b1;
        apb.cb_master.penable <= 1'b0;
        apb.cb_master.pwrite  <= 1'b1;
        apb.cb_master.paddr   <= addr;
        apb.cb_master.pwdata  <= data;
        @(apb.cb_master);
        //Access Phase
        apb.cb_master.penable <= 1'b1;
        //do @(apb.cb_master); while (!apb.cb_master.pready);                   //Infinite waiting could hang simulation
        wait_ready("apb_write" , addr);

        $display("[APB_BFM][WRITE] addr=%h data=%h time=%0t", addr,data, $time);

        drive_idle();
    endtask

    task automatic apb_read(input [7:0] addr, output [31:0] data);
        @(apb.cb_master);
        // Setup Phase
        apb.cb_master.psel    <= 1'b1;
        apb.cb_master.penable <= 1'b0;
        apb.cb_master.pwrite  <= 1'b0;
        apb.cb_master.pwdata  <= '0;
        apb.cb_master.paddr   <= addr;
        @(apb.cb_master);
        // Access Phase
        apb.cb_master.penable <= 1'b1;
        //do @(apb.cb_master); while (!apb.cb_master.pready);
        wait_ready("apb_read" , addr);

        data = apb.cb_master.prdata;
        $display("[APB_BFM][READ] addr=%h data=%h time=%0t",addr,data,$time);

        drive_idle();
    endtask

endmodule

`endif // APB_MASTER_BFM_SV