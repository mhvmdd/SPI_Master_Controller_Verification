`ifndef APB_SVA_SV
`define APB_SVA_SV

module apb_sva(
    apb_if apbif,
    input wire [31:0]      control_word,
    input wire [31:0]      status_word,
    input wire [31:0]      clk_div_word,
    input wire [31:0]      ss_ctrl_word,
    input wire [31:0]      int_en_word,
    input wire [31:0]      int_status_word,
    input wire [31:0]      delay_word,
    input wire [FIFO_AW:0] tx_count,
    input wire [FIFO_AW:0] rx_count,
    input wire             rx_push_valid,
    input wire             tx_pop
);

bit setup;
assign setup = apbif.psel && !apbif.penable;

bit access;
assign access = apbif.psel && apbif.penable;

bit write;
assign write = access && apbif.pwrite;

bit read;
assign read = access && !apbif.pwrite;


bit [31:0] reg_bank [bit [7:0]];

assign reg_bank[OFF_CTRL] = control_word;
assign reg_bank[OFF_STATUS] = status_word; 
assign reg_bank [OFF_CLK_DIV] = clk_div_word;
assign reg_bank [OFF_SS_CTRL] = ss_ctrl_word;
assign reg_bank [OFF_INT_EN] = int_en_word;
assign reg_bank [OFF_INT_STATUS] = int_status_word;
assign reg_bank [OFF_DELAY] = delay_word;

bit [31:0] tx_fifo [$];
bit [2:0] tx_fifo_count;
always_comb begin
    if (!reg_bank[OFF_CONTROL][0] || !apbif.presetn) begin
        tx_fifo = {};
        tx_fifo_count = 0;
    end
    else if ( write && apbif.paddr == 8'h10 && !reg_bank[OFF_STATUS][1] /*TXFIFO is not full*/) begin
        tx_fifo.push_back(apbif.pwdata);
        tx_fifo_count = tx_fifo.size();
    end 
    else if (tx_pop) begin
        tx_fifo.pop_front();
        tx_fifo_count = tx_fifo.size();
    end
end

//APB_1
property apb_sel_stable;
    @(posedge apbif.pclk) disable iff (!apbif.presetn)
        $rose(apbif.psel) |=> $stable(apbif.psel) && !apbif.penable ##1 $stable(apbif.psel) && apbif.penable ;
endproperty
a_apb_sel_stable: assert property (apb_sel_stable)
        else
            $error("[ASSERTION_ERROR] a_apb_sel_stable: APB select signal is not high during transaction phases. PSel = %b, PEnable = %b", apbif.psel, apbif.penable);

//APB_2 
property apb_enable:
    @(posedge apbif.pclk) disable iff (!apbif.presetn)
        $rose(apbif.penable) |-> psel;
endproperty
a_apb_enable: assert property (apb_enable)
        else
            $error("[ASSERTION_ERROR] a_apb_enable: APB enable signal is not asserted when APB select is high. PSel = %b, PEnable = %b", apbif.psel, apbif.penable);

// ABP_3
property apb_transition_stable;
    @(posedge apbif.pclk) disable iff (!apbif.presetn)
        (setup) /*Setup*/ ##1  (access) /*Access*/|-> ($stable(apbif.paddr) && $stable(apbif.pwrite) && $stable(apbif.pwdata));
endproperty
a_apb_transition_stable: assert property (apb_transition_stable)
        else
            $error("[ASSERTION_ERROR] a_apb_transition_stable: APB address, write signal, or write data is not stable during transaction phases. Setup = %b, Access = %b, Address = %b, Write = %b, Write Data = %h", 
                            setup, access, apbif.paddr, apbif.pwrite, apbif.pwdata);

// APB_x (R9) //TODO
property apb_txfifo_wr;
    @(posedge apbif.pclk) disable iff (!apbif.presetn)
        (write && apbif.paddr == 8'h10 && !reg_bank[OFF_STATUS][1] /*TXFIFO is not full*/) |-> apbif.pready;
endproperty
a_apb_txfifo_wr: assert property (apb_txfifo_wr)
        else
            $error("[ASSERTION_ERROR] a_apb_txfifo_wr: APB TX FIFO write assertion failed. Write = %b, Address = %h, Write Data = %h, Tx_Mem = %h", 
                        write, apbif.paddr, apbif.pwdata, tx_mem);

//APB_x (R10) //TODO
property apb_rxfifo_rd;
    @(posedge apbif.pclk) disable iff (!apbif.presetn)
        (read && apbif.paddr == 8'h0C && !reg_bank[OFF_STATUS][2] /*RXFIFO is not empty*/) |-> apbif.pready;
endproperty
a_apb_rxfifo_rd: assert property (apb_rxfifo_rd)
        else
            $error("[ASSERTION_ERROR] a_apb_rxfifo_rd: APB RX FIFO read assertion failed. Read = %b, Address = %h, Read Data = %h, Rx_Mem = %h", 
                        read, apbif.paddr, apbif.paddr, apbif.prdata, rx_mem);


//APB_x (R11)
property apb_txfifo_full;
    @(posedge apbif.pclk) disable iff (!apbif.presetn)
        (write && apbif.paddr == 8'h10 && tx_count == FIFO_DEPTH-1 && !reg_bank[OFF_STATUS][1] /*TXFIFO is not full*/ && reg_bank[OFF_CTRL][0] /*Ctrl En is set*/ && !tx_pop) |=> tx_count == $past(tx_count) + 1 && reg_bank[OFF_STATUS][1] /*TXFIFO is full*/;
endproperty
a_apb_txfifo_full: assert property (apb_txfifo_full)
        else
            $error("[ASSERTION_ERROR] a_apb_txfifo_full: APB TX FIFO full assertion failed. Tx_Full = %b, Tx_Count = %d", 
                        reg_bank[OFF_STATUS][1], tx_fifo_count);   



//APB_x (R12)
property apb_rxfifo_full;
    @(posedge apbif.pclk) disable iff (!apbif.presetn)
        (rx_push_valid && rx_count == FIFO_DEPTH-1 && !reg_bank[OFF_STATUS][3] /*RXFIFO is not full*/ && reg_bank[OFF_CTRL][0] /*Ctrl En is set*/) |=> rx_count == $past(rx_count) + 1 && reg_bank[OFF_STATUS][3] /*RXFIFO is full*/;
endproperty
a_apb_rxfifo_full: assert property (apb_rxfifo_full)
        else
            $error("[ASSERTION_ERROR] a_apb_rxfifo_full: APB RX FIFO full assertion failed. Rx_Full = %b, Rx_Count = %d", 
                        reg_bank[OFF_STATUS][3], rx_count);

// APB_4 (R13)
property apb_txfifo_ovf;
    @(posedge apbif.pclk) disable iff (!apbif.presetn)
        (write && reg_bank[OFF_STATUS][1] /*TXFIFO is full*/ && !reg_bank[OFF_STATUS][5] /*TXFIFO is not overflow*/) |=> reg_bank[OFF_STATUS][5] /*FIFO overflow*/;
endproperty
a_apb_txfifo_ovf: assert property (apb_txfifo_ovf)
        else
            $error("[ASSERTION_ERROR] a_apb_txfifo_ovf: APB TX FIFO overflow assertion failed. Tx_Full = %b, FIFO_Overflow = %b", 
                        reg_bank[OFF_STATUS][1], reg_bank[OFF_STATUS][5]);

// APB_5 (R13)
sequence clear_txfifo_ovf;
    // $past(reg_bank[OFF_STATUS][5], 2) /*FIFO overflow*/ && reg_bank[OFF_STATUS][1] /*TXFIFO is full*/ && !reg_bank[OFF_STATUS][5] /*TXFIFO is not overflow*/ && write
    write && reg_bank[OFF_STATUS][1] /*TXFIFO is full*/ && !reg_bank[OFF_STATUS][5] /*TXFIFO is not overflow*/ 
    ##1 reg_bank[OFF_STATUS][5] /*FIFO overflow*/ 
    ##1 write && reg_bank[OFF_STATUS][1] /*TXFIFO is full*/ && !reg_bank[OFF_STATUS][5] /*FIFO overflow cleared*/;
endsequence

property apb_txfifo_ofv_afterclr;
    @(posedge apbif.pclk) disable iff (!apbif.presetn)
        clear_txfifo_ovf |=> reg_bank[OFF_STATUS][5] /*FIFO overflow*/;
endproperty
a_apb_txfifo_ofv_afterclr: assert property (apb_txfifo_ofv_afterclr)
        else
            $error("[ASSERTION_ERROR] a_apb_txfifo_ofv_afterclr: APB TX FIFO overflow clear assertion failed. FIFO_Overflow = %b, Clear_FIFO_Overflow = %b", 
                        reg_bank[OFF_STATUS][5], reg_bank[OFF_CTRL][0]);

// APB_6 (R14)
property apb_rxfifo_ofv;
    @(posedge apbif.pclk) disable iff (!apbif.presetn)
        (rx_push_valid && reg_bank[OFF_STATUS][3] /*RXFIFO is full*/ && !reg_bank[OFF_STATUS][6] /*RXFIFO is not overflow*/) |=> reg_bank[OFF_STATUS][7] /*FIFO overflow*/;
endproperty
a_apb_rxfifo_ofv: assert property (apb_rxfifo_ofv)
        else
            $error("[ASSERTION_ERROR] a_apb_rxfifo_ofv: APB RX FIFO overflow assertion failed. Rx_Push_Valid = %b, Rx_Full = %b, FIFO_Overflow = %b", 
                        rx_push_valid, reg_bank[OFF_STATUS][3], reg_bank[OFF_STATUS][7]);


// APB_7 (R14)
sequence clear_rxfifo_ovf;
    rx_push_valid && reg_bank[OFF_STATUS][3] /*RXFIFO is full*/ && !reg_bank[OFF_STATUS][6] /*RXFIFO is not overflow*/ 
    ##1 reg_bank[OFF_STATUS][7] /*FIFO overflow*/ 
    ##1 rx_push_valid && reg_bank[OFF_STATUS][3] /*RXFIFO is full*/ && !reg_bank[OFF_STATUS][7] /*RXFIFO overflow cleared*/;
endsequence

property apb_rxfifo_ofv_afterclr;
    @(posedge apbif.pclk) disable iff (!apbif.presetn)
        clear_rxfifo_ovf |=> reg_bank[OFF_STATUS][7] /*FIFO overflow*/;
endproperty
a_apb_rxfifo_ofv_afterclr: assert property (apb_rxfifo_ofv_afterclr)
        else
            $error("[ASSERTION_ERROR] a_apb_rxfifo_ofv_afterclr: APB RX FIFO overflow clear assertion failed. FIFO_Overflow = %b, Clear_FIFO_Overflow = %b, Rx_Full = %b, Rx_Push_Valid = %b", 
                        reg_bank[OFF_STATUS][7], reg_bank[OFF_CTRL][0], reg_bank[OFF_STATUS][3], rx_push_valid);









// Control Register Access (R/W)
property ctrl_reg_rd;
    @(posedge apbif.pclk) disable iff (!apbif.presetn)
        (read && apbif.paddr == 8'h00) |-> apbif.pready && (apbif.prdata == reg_bank[OFF_CTRL]);
endproperty
a_ctrl_reg_rd: assert property (ctrl_reg_rd) 
        else  
            $error("[ASSERTION_ERROR] a_ctrl_reg_rd: Control register  has incorrect read value. Control = %h, Read_Data = %h", 
                    reg_bank[OFF_CTRL], apbif.prdata);
property ctrl_reg_wr;
    @(posedge apbif.pclk) disable iff (!apbif.presetn)
        (write && apbif.paddr == 8'h00) |-> apbif.pready && (apbif.pwdata [7:0] ==  reg_bank[OFF_CTRL][7:0]);
endproperty
a_ctrl_reg_wr: assert property (ctrl_reg_wr)
        else
            $error("[ASSERTION_ERROR] a_ctrl_reg_wr: Control register has incorrect write value. Write_Data = %h, Control = %h", 
                    apbif.pwdata, reg_bank[OFF_CTRL]);

// Status Register Access (RO)
property status_reg_rd;
    @(posedge apbif.pclk) disable iff (!apbif.presetn)
        (read && apbif.paddr == 8'h04) |-> apbif.pready && (apbif.prdata == reg_bank[OFF_STATUS]);
endproperty
a_status_reg_rd: assert property (status_reg_rd)
        else
            $error("[ASSERTION_ERROR] a_status_reg_rd: Status register has incorrect read value. Status = %h, Read_Data = %h", 
                    reg_bank[OFF_STATUS], apbif.prdata);

property status_reg_wr;
    @(posedge apbif.pclk) disable iff (!apbif.presetn)
        (write && apbif.paddr == 8'h04) |-> apbif.pready && $stable(reg_bank[OFF_STATUS]);
endproperty
a_status_reg_wr: assert property (status_reg_wr)
        else
            $error("[ASSERTION_ERROR] a_status_reg_wr: Status register should not be writable. Write_Data = %h, Status = %h", 
                    apbif.pwdata, reg_bank[OFF_STATUS]);



// rest of the registers 








// (R2)

always_comb begin 
    if (!apbif.presetn) begin
        //Control Register Reset Value
        a_ctrl_reset: assert final (reg_bank[OFF_CTRL] == 32'h0000_0000) 
        else 
            $error("[ASSERTION_ERROR] a_ctrl_reset: Control register did not reset to 0. Control = %h", 
                    reg_bank[OFF_CTRL]);
        a_status_reset: assert final (reg_bank[OFF_STATUS] == 32'h0000_0000) 
        else 
            $error("[ASSERTION_ERROR] a_status_reset: Status register did not reset to 0. Status = %h", 
                    reg_bank[OFF_STATUS]);
        a_clk_div_reset: assert final (reg_bank[OFF_CLK_DIV] == 32'h0000_0012) 
        else 
            $error("[ASSERTION_ERROR] a_clk_div_reset: Clock Divider register did not reset to 0. Clock Divider = %h", 
                    reg_bank[OFF_CLK_DIV]);
        a_ss_ctrl_reset: assert final (reg_bank[OFF_SS_CTRL] == 32'h0000_0000) 
        else 
            $error("[ASSERTION_ERROR] a_ss_ctrl_reset: Slave Select Control register did not reset to 0. Slave Select Control = %h", 
                    reg_bank[OFF_SS_CTRL]);
        a_int_en_reset: assert final (reg_bank[OFF_INT_EN] == 32'h0000_0000) 
        else 
            $error("[ASSERTION_ERROR] a_int_en_reset: Interrupt Enable register did not reset to 0. Interrupt Enable = %h", 
                    reg_bank[OFF_INT_EN]);
        a_int_status_reset: assert final (reg_bank[OFF_INT_STATUS] == 32'h0000_0000) 
        else 
            $error("[ASSERTION_ERROR] a_int_status_reset: Interrupt Status register did not reset to 0. Interrupt Status = %h", 
                    reg_bank[OFF_INT_STATUS]);
        a_delay_reset: assert final (reg_bank[OFF_DELAY] == 32'h0000_0000) 
        else 
            $error("[ASSERTION_ERROR] a_delay_reset: Delay register did not reset to 0. Delay = %h", 
                    reg_bank[OFF_DELAY]);
    end
end
// Status Register Reset Value
// a_status_reset: assert property (
//     @(posedge apbif.pclk) 
//         reg_bank[OFF_STATUS] == 32'h0000_0000
// ) else $error("[ASSERTION_ERROR] a_status_reset: Status register did not reset to 0. Status = %h", 
// reg_bank[OFF_STATUS]);

// (R3) (APB_3)
// (R4) (APB_4)
// (R5) (APB_5)  
endmodule

`endif // APB_SVA_SV
