`ifndef APB_SVA_SV
`define APB_SVA_SV

module apb_sva(
    apb_if apbif,

    // Control signals
    input wire                  ctrl_en,
    input wire                  ctrl_mstr,
    input wire [1:0]            ctrl_mode,  
    input wire                  ctrl_lsb_first,
    input wire                  ctrl_loopback,
    input wire [1:0]            ctrl_width,

    // Clock divider configuration
    input wire [15:0]           clk_div,

    // Slave select control signals
    input wire [3:0]            ss_en,
    input wire [3:0]            ss_val,
    input wire [3:0]            ss_n,

    // Interrupt signals
    input wire [4:0]            int_en,
    input wire [4:0]            int_stat,
    input wire                  IRQ,

    //Delay configuration
    input wire [7:0]            delay_cfg,

    // APB transaction signals
    input wire                  apb_write,
    input wire                  apb_read,

    // TX FIFO interface signals
    input wire [3:0]            tx_count,
    input wire                  tx_push_accepted,
    input wire                  tx_push_dropped,
    input wire                  tx_full_w,
    input wire                  tx_empty_w,
    input wire                  tx_pop,

    // RX FIFO interface signals
    input wire [3:0]            rx_count,
    input wire                  rx_push_valid,
    input wire                  rx_pop_this_cylcle,
    input wire                  rx_full_w,
    input wire                  rx_empty_w,
    // Core status -> regfile
    input  wire                 busy_in,
    input  wire                 transfer_done_pulse
);


// Register offsets
    localparam [7:0] OFF_CTRL     = 8'h00;
    localparam [7:0] OFF_STATUS   = 8'h04;
    localparam [7:0] OFF_TX_DATA  = 8'h08;
    localparam [7:0] OFF_RX_DATA  = 8'h0C;
    localparam [7:0] OFF_CLK_DIV  = 8'h10;
    localparam [7:0] OFF_SS_CTRL  = 8'h14;
    localparam [7:0] OFF_INT_EN   = 8'h18;
    localparam [7:0] OFF_INT_STAT = 8'h1C;
    localparam [7:0] OFF_DELAY    = 8'h20;


// Interrupt bit positions
    localparam integer IRQ_TX_EMPTY      = 0;
    localparam integer IRQ_RX_FULL       = 1;
    localparam integer IRQ_TX_OVF        = 2;
    localparam integer IRQ_RX_OVF        = 3;
    localparam integer IRQ_TRANSFER_DONE = 4;
    localparam integer IRQ_COUNT         = 5;

// FIFO depth
    localparam integer FIFO_DEPTH = 8;

// Status register bit positions
    wire [31:0] status_word = {
        25'b0,
        int_stat[IRQ_RX_OVF],     // [6] RX_OVF
        int_stat[IRQ_TX_OVF],     // [5] TX_OVF
        rx_empty_w,               // [4] RX_EMPTY (reset = 1)
        rx_full_w,                // [3] RX_FULL
        tx_empty_w,               // [2] TX_EMPTY (reset = 1)
        tx_full_w,                // [1] TX_FULL
        busy_in                   // [0] BUSY
    };


// Control register bit positions
    wire [31:0] ctrl_word = {
        24'b0,
        ctrl_width,
        ctrl_loopback,
        ctrl_lsb_first,
        ctrl_mode,
        ctrl_mstr,
        ctrl_en
    };
    wire [31:0] ss_ctrl_word  = {24'b0, ss_val,    ss_en};
    wire [31:0] int_en_word   = {{(32-IRQ_COUNT){1'b0}}, int_en};
    wire [31:0] int_stat_word = {{(32-IRQ_COUNT){1'b0}}, int_stat};
    wire [31:0] clk_div_word  = {16'b0, clk_div};
    wire [31:0] delay_word    = {24'b0, delay_cfg};


// Helper signals for assertions
logic setup;
assign setup = apbif.psel && !apbif.penable;

logic access;
assign access = apbif.psel && apbif.penable;

logic rx_push_accepted;
assign rx_push_accepted = rx_push_valid && !rx_full_w /*RXFIFO is not Full*/ && ctrl_en /*Ctrl En is set*/;

logic rx_push_dropped;
assign rx_push_dropped = rx_push_valid && rx_full_w /*RXFIFO is Full*/ && ctrl_en /*Ctrl En is set*/;


//APB_1 -
property apb_sel_stable;
    @(posedge apbif.pclk) disable iff (!apbif.presetn)
        $rose(apbif.psel) |=> $stable(apbif.psel) && !apbif.penable ##1 $stable(apbif.psel) && apbif.penable ;
endproperty
a_apb_sel_stable: assert property (apb_sel_stable)
        else
            $error("[ASSERTION_ERROR] a_apb_sel_stable: APB select signal is not high during transaction phases. PSel = %b, PEnable = %b", apbif.psel, apbif.penable);

//APB_2 -
property apb_enable;
    @(posedge apbif.pclk) disable iff (!apbif.presetn)
        $rose(apbif.penable) |-> apbif.psel;
endproperty
a_apb_enable: assert property (apb_enable)
        else
            $error("[ASSERTION_ERROR] a_apb_enable: APB enable signal is not asserted when APB select is high. PSel = %b, PEnable = %b", apbif.psel, apbif.penable);

// ABP_3 - 
property apb_transition_stable;
    @(posedge apbif.pclk) disable iff (!apbif.presetn)
        (setup) /*Setup*/ ##1  (access) /*Access*/|-> ($stable(apbif.paddr) && $stable(apbif.pwrite) && $stable(apbif.pwdata));
endproperty
a_apb_transition_stable: assert property (apb_transition_stable)
        else
            $error("[ASSERTION_ERROR] a_apb_transition_stable: APB address, write signal, or write data is not stable during transaction phases. Setup = %b, Access = %b, Address = %b, Write = %b, Write Data = %h", 
                            setup, access, apbif.paddr, apbif.pwrite, apbif.pwdata);

//R1
property ctrl_reg_rd;
    @(posedge apbif.pclk) disable iff (!apbif.presetn)
        (apb_read && apbif.paddr == 8'h00) |=>  (apbif.prdata == ctrl_word);
endproperty
a_ctrl_reg_rd: assert property (ctrl_reg_rd) 
        else  
            $error("[ASSERTION_ERROR] a_ctrl_reg_rd: Control register  has incorrect read value. Control = %h, Read_Data = %h", 
                    ctrl_word, apbif.prdata);
property ctrl_reg_wr;
    @(posedge apbif.pclk) disable iff (!apbif.presetn)
        (apb_write && apbif.paddr == 8'h00) |=>($past (apbif.pwdata[7:0]) ==  ctrl_word[7:0]);
endproperty
a_ctrl_reg_wr: assert property (ctrl_reg_wr)
        else
            $error("[ASSERTION_ERROR] a_ctrl_reg_wr: Control register has incorrect write value. Write_Data = %h, Control = %h", 
                    apbif.pwdata, ctrl_word);

property status_reg_rd;
    @(posedge apbif.pclk) disable iff (!apbif.presetn)
        (apb_read && apbif.paddr == 8'h04) |=> (apbif.prdata == status_word);
endproperty
a_status_reg_rd: assert property (status_reg_rd)
        else
            $error("[ASSERTION_ERROR] a_status_reg_rd: Status register has incorrect read value. Status = %h, Read_Data = %h", 
                    status_word, apbif.prdata);

property clk_div_reg_rd;
    @(posedge apbif.pclk) disable iff (!apbif.presetn)
        (apb_read && apbif.paddr == 8'h10) |=> (apbif.prdata == clk_div_word);
endproperty
a_clk_div_reg_rd: assert property (clk_div_reg_rd)
        else
            $error("[ASSERTION_ERROR] a_clk_div_reg_rd: Clock Divider register has incorrect read value. Clock Divider = %h, Read_Data = %h", 
                    clk_div_word, apbif.prdata);

property ss_ctrl_reg_rd;
    @(posedge apbif.pclk) disable iff (!apbif.presetn)
        (apb_read && apbif.paddr == 8'h14) |=> (apbif.prdata == ss_ctrl_word);
endproperty
a_ss_ctrl_reg_rd: assert property (ss_ctrl_reg_rd)      
        else
            $error("[ASSERTION_ERROR] a_ss_ctrl_reg_rd: Slave Select Control register has incorrect read value. Slave Select Control = %h, Read_Data = %h", 
                    ss_ctrl_word, apbif.prdata);
property int_en_reg_rd;
    @(posedge apbif.pclk) disable iff (!apbif.presetn)
        (apb_read && apbif.paddr == 8'h18) |=> (apbif.prdata == int_en_word);
endproperty
a_int_en_reg_rd: assert property (int_en_reg_rd)
        else
            $error("[ASSERTION_ERROR] a_int_en_reg_rd: Interrupt Enable register has incorrect read value. Interrupt Enable = %h, Read_Data = %h", 
                    int_en_word, apbif.prdata);
property int_status_reg_rd;
    @(posedge apbif.pclk) disable iff (!apbif.presetn)
        (apb_read && apbif.paddr == 8'h1C) |=> (apbif.prdata == int_stat_word);
endproperty
a_int_status_reg_rd: assert property (int_status_reg_rd)
        else
            $error("[ASSERTION_ERROR] a_int_status_reg_rd: Interrupt Status register has incorrect read value. Interrupt Status = %h, Read_Data = %h", 
                    int_stat_word, apbif.prdata);
property delay_reg_rd;
    @(posedge apbif.pclk) disable iff (!apbif.presetn)
        (apb_read && apbif.paddr == 8'h20) |=> (apbif.prdata == delay_word);
endproperty
a_delay_reg_rd: assert property (delay_reg_rd)
        else
            $error("[ASSERTION_ERROR] a_delay_reg_rd: Delay register has incorrect read value. Delay = %h, Read_Data = %h", 
                    delay_word, apbif.prdata); 

// (R2)
always_comb begin 
    if (!apbif.presetn) begin
        //Control Register Reset Value
        a_ctrl_reset: assert final (ctrl_word == 32'h0000_0000) 
        else 
            $error("[ASSERTION_ERROR] a_ctrl_reset: Control register did not reset to 0. Control = %h", 
                    ctrl_word);
        a_status_reset: assert final (status_word == 32'h0000_0012) 
        else 
            $error("[ASSERTION_ERROR] a_status_reset: Status register did not reset to 32'h12. Status = %h", 
                    status_word);
        a_clk_div_reset: assert final (clk_div_word == 32'h0000_0000) 
        else 
            $error("[ASSERTION_ERROR] a_clk_div_reset: Clock Divider register did not reset to 0. Clock Divider = %h", 
                    clk_div_word);
        a_ss_ctrl_reset: assert final (ss_ctrl_word == 32'h0000_0000) 
        else 
            $error("[ASSERTION_ERROR] a_ss_ctrl_reset: Slave Select Control register did not reset to 0. Slave Select Control = %h", 
                    ss_ctrl_word);
        a_int_en_reset: assert final (int_en_word == 32'h0000_0000) 
        else 
            $error("[ASSERTION_ERROR] a_int_en_reset: Interrupt Enable register did not reset to 0. Interrupt Enable = %h", 
                    int_en_word);
        a_int_status_reset: assert final (int_stat_word == 32'h0000_0000) 
        else 
            $error("[ASSERTION_ERROR] a_int_status_reset: Interrupt Status register did not reset to 0. Interrupt Status = %h", 
                    int_stat_word);
        a_delay_reset: assert final (delay_word == 32'h0000_0000) 
        else 
            $error("[ASSERTION_ERROR] a_delay_reset: Delay register did not reset to 0. Delay = %h", 
                    delay_word);
    end
end

//R3 - APB
property apb_ctrl_en_reset;
    @(posedge apbif.pclk) disable iff (!apbif.presetn)
        !ctrl_en |=> (rx_count == 0)&&(tx_count == 0) && !tx_full_w && !rx_full_w && !rx_push_valid;
endproperty
a_apb_ctrl_en_reset: assert property (apb_ctrl_en_reset)
        else
            $error("[ASSERTION_ERROR] a_apb_ctrl_en_reset: CTRL.EN=0 does not hold FIFOs in reset. Ctrl En = %b, Tx_Count = %d, Tx_Full = %b, Rx_Full = %b, Rx_Push_Valid = %b", 
                    ctrl_en, tx_count, tx_full_w, rx_full_w, rx_push_valid);    

// APB_x (R9) 
sequence apb_txfifo_wr_seq;
    setup && apbif.pwrite && apbif.paddr == 8'h08 && !tx_full_w /*TXFIFO is not full*/ && ctrl_en /*Ctrl En is set*/ && tx_count < FIFO_DEPTH ;
endsequence

property apb_txfifo_wr;
    @(posedge apbif.pclk) disable iff (!apbif.presetn)
        apb_txfifo_wr_seq |=> tx_count == ($past(tx_count) + 1 - $past(tx_pop)) && apbif.pready; 
endproperty
a_apb_txfifo_wr: assert property (apb_txfifo_wr)
        else
            $error("[ASSERTION_ERROR] a_apb_txfifo_wr: APB TX FIFO write assertion failed. Write = %b, Address = %h, Write Data = %h, Tx_Count = %d", 
                        apb_write, apbif.paddr, apbif.pwdata, tx_count);


//APB_x (R10)
sequence apb_rxfifo_rd_seq;
    setup && !apbif.pwrite && rx_count > 0 && apbif.paddr == 8'h0C && !rx_empty_w /*RXFIFO is not empty*/ && ctrl_en /*Ctrl En is set*/ && !rx_push_valid;
endsequence

property apb_rxfifo_rd;
    @(posedge apbif.pclk) disable iff (!apbif.presetn)
        apb_rxfifo_rd_seq |=> rx_count == ($past(rx_count) - 1 + $past(rx_push_valid)) && apbif.pready;
endproperty
a_apb_rxfifo_rd: assert property (apb_rxfifo_rd)
        else
            $error("[ASSERTION_ERROR] a_apb_rxfifo_rd: APB RX FIFO read assertion failed. Read = %b, Address = %h, Read Data = %h, Rx_Count = %d, Rx_Push_Valid = %b", 
                        apb_read, apbif.paddr, apbif.prdata, rx_count, rx_push_valid);


//APB_x (R11)
property apb_txfifo_full;
    @(posedge apbif.pclk) disable iff (!apbif.presetn)
        (tx_push_accepted && tx_count == FIFO_DEPTH-1) |=> tx_count == $past(tx_count) + 1 && tx_full_w /*TXFIFO is full*/;
endproperty
a_apb_txfifo_full: assert property (apb_txfifo_full)
        else
            $error("[ASSERTION_ERROR] a_apb_txfifo_full: APB TX FIFO full assertion failed. Tx_Full = %b, Tx_Count = %d", 
                        tx_full_w, tx_count);   

//APB_x (R12)
property apb_rxfifo_full;
    @(posedge apbif.pclk) disable iff (!apbif.presetn)
        (rx_push_accepted && rx_count == FIFO_DEPTH-1 && !rx_pop_this_cylcle) |=> rx_count == $past(rx_count) + 1 && rx_full_w /*RXFIFO is full*/;
endproperty
a_apb_rxfifo_full: assert property (apb_rxfifo_full)
        else
            $error("[ASSERTION_ERROR] a_apb_rxfifo_full: APB RX FIFO full assertion failed. Rx_Full = %b, Rx_Count = %d", 
                        rx_full_w, rx_count);

// APB_4 (R13)
property apb_txfifo_ovf;
    @(posedge apbif.pclk) disable iff (!apbif.presetn)
        (tx_push_dropped && !tx_pop) |=> $rose(status_word[5]) && $rose(int_stat_word[2]) /*TXFIFO overflow*/;
endproperty
a_apb_txfifo_ovf: assert property (apb_txfifo_ovf)
        else
            $error("[ASSERTION_ERROR] a_apb_txfifo_ovf: APB TX FIFO overflow assertion failed. Tx_Full = %b, FIFO_Overflow = %b", 
                        tx_full_w, status_word[5]);

// APB_5 (R13)
sequence clear_txfifo_ovf;
    ##1 status_word[5] /*FIFO overflow*/ 
    ##1 tx_push_dropped && status_word[5] /*FIFO overflow cleared*/;
endsequence

property apb_txfifo_ofv_afterclr;
    @(posedge apbif.pclk) disable iff (!apbif.presetn)
        clear_txfifo_ovf |=> $rose(status_word[5]) /*TXFIFO overflow*/;
endproperty
a_apb_txfifo_ofv_afterclr: assert property (apb_txfifo_ofv_afterclr)
        else
            $error("[ASSERTION_ERROR] a_apb_txfifo_ofv_afterclr: APB TX FIFO overflow clear assertion failed. FIFO_Overflow = %b", 
                        status_word[5]);

// APB_6 (R14)
property apb_rxfifo_ofv;
    @(posedge apbif.pclk) disable iff (!apbif.presetn)
        (rx_push_dropped && !rx_pop_this_cylcle) |=> status_word[6] /*RXFIFO overflow*/;
endproperty
a_apb_rxfifo_ofv: assert property (apb_rxfifo_ofv)
        else
            $error("[ASSERTION_ERROR] a_apb_rxfifo_ofv: APB RX FIFO overflow assertion failed. Rx_Push_Dropped = %b, Rx_Full = %b, FIFO_Overflow = %b", 
                        rx_push_dropped, status_word[3], status_word[6]);


// APB_7 (R14)
sequence clear_rxfifo_ovf;
    rx_push_dropped && !status_word[6] /*RXFIFO is not overflow*/ 
    ##1 status_word[6] /*FIFO overflow*/ 
    ##1 rx_push_dropped && status_word[6] /*FIFO overflow*/;
endsequence

property apb_rxfifo_ofv_afterclr;
    @(posedge apbif.pclk) disable iff (!apbif.presetn)
        clear_rxfifo_ovf |=> status_word[6] /*RXFIFO overflow*/;
endproperty
a_apb_rxfifo_ofv_afterclr: assert property (apb_rxfifo_ofv_afterclr)
        else
            $error("[ASSERTION_ERROR] a_apb_rxfifo_ofv_afterclr: APB RX FIFO overflow clear assertion failed. FIFO_Overflow = %b, Rx_Full = %b, Rx_Push_Dropped = %b", 
                        status_word[6], status_word[3], rx_push_dropped);


//APB_x (R15)
property apb_rxfifo_rd_empty;
    @(posedge apbif.pclk) disable iff (!apbif.presetn)
        (apb_read && apbif.paddr == 8'h0C && status_word[4] /*RXFIFO is empty*/) |-> apbif.pready ##1 !status_word[6] /*RXFIFO is not overflow*/ && apbif.prdata == 32'h0000_0000; 
endproperty
a_apb_rxfifo_rd_empty: assert property (apb_rxfifo_rd_empty)
        else
            $error("[ASSERTION_ERROR] a_apb_rxfifo_rd_empty: APB RX FIFO read when empty assertion failed. Read = %b, Address = %h, RXFIFO Empty = %b, Read Data = %h", 
                        apb_read, apbif.paddr, status_word[4], apbif.prdata);

always_comb begin
    a_comb_irq_agg: assert final (IRQ == |(int_stat & int_en)) 
    else $error("[ASSERTION_ERROR] a_comb_irq_agg: IRQ=%b int_stat=%b int_en=%b",
                    IRQ, int_stat, int_en);
end


//APB_x (R17) 
property apb_int_status_w1c;
    @(posedge apbif.pclk) disable iff (!apbif.presetn)
        (apb_write && apbif.paddr == 8'h1C && !IRQ /*Aggregate IRQ is not set*/) |-> apbif.pready ##1 (int_stat_word) == $past(int_stat_word) & {{27{1'b0}},~apbif.pwdata[4:0]};
endproperty
a_apb_int_status_w1c: assert property (apb_int_status_w1c)
        else
            $error("[ASSERTION_ERROR] a_apb_int_status_w1c: APB Interrupt Status W1C assertion failed. Write = %b, Address = %h, Write Data = %h, Interrupt Status = %h", 
                        apb_write, apbif.paddr, apbif.pwdata, int_stat_word);
    
// APB_x (R18)
property apb_w1c_race;
    @(posedge apbif.pclk) disable iff (!apbif.presetn)
        (apb_write && apbif.paddr == 8'h1C && IRQ /*Aggregate IRQ is set*/ && apbif.pwdata[0] /*Write to clear aggregate IRQ*/) |-> apbif.pready && IRQ /*Aggregate IRQ is still set*/;
endproperty
a_apb_w1c_race: assert property (apb_w1c_race)
        else
            $error("[ASSERTION_ERROR] a_apb_w1c_race: APB W1C race condition assertion failed. Write = %b, Address = %h, Write Data = %h, Interrupt Status = %h", 
                        apb_write, apbif.paddr, apbif.pwdata, int_stat_word);

// a_irq_agg : assert property (
//         @(posedge apbif.pclk) disable iff (!apbif.presetn)
//             IRQ == |int_stat
//     ) else $error("[ASSERTION_ERROR] a_irq_agg IRQ=%b int_stat=%b",
//                   IRQ, int_stat);

// APB_x (R20)
always_comb begin
    assert(ss_n == (~ss_en | ss_val)) 
    else 
        $error("[ASSERTION_ERROR] a_ss_ctrl: Slave select control assertion failed. SS_n = %b, ss_en = %b, ss_val = %b", 
                    ss_n, ss_en, ss_val);
end

//APB_x (R21)
property apb_error_or_ready;
    @(posedge apbif.pclk) disable iff (!apbif.presetn)
        (setup) |=> apbif.ready && !apbif.pslverr;
endproperty
a_apb_error_or_ready: assert property (apb_error_or_ready)
        else
            $error("[ASSERTION_ERROR] a_apb_error_or_ready: APB error or ready assertion failed. Setup = %b, Ready = %b, PSLVERR = %b", 
                        setup, apbif.pready, apbif.pslverr);


// APB_x (R23)
property apb_reserved_addr;
    @(posedge apbif.pclk) disable iff (!apbif.presetn)
        (setup && (apbif.paddr > 8'h20) && !apbif.pwrite) |=> apbif.pready && apbif.prdata == 32'h0000_0000;
endproperty
a_apb_reserved_addr: assert property (apb_reserved_addr)
        else
            $error("[ASSERTION_ERROR] a_apb_reserved_addr: APB reserved address read assertion failed. Setup = %b, Address = %h, Read Data = %h", 
                        setup, apbif.paddr, apbif.prdata);





endmodule

`endif // APB_SVA_SV
