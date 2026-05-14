
`ifndef REF_MODEL_SV
    `define REF_MODEL_SV

class ref_model;

    localparam FIFO_DEPTH = 8;

    // Register offsets
    localparam CTRL_ADDR     = 8'h00;
    localparam STATUS_ADDR   = 8'h04;
    localparam TX_DATA_ADDR  = 8'h08;
    localparam RX_DATA_ADDR  = 8'h0C;   
    localparam CLK_DIV_ADDR  = 8'h10;
    localparam SS_CTRL_ADDR  = 8'h14;
    localparam INT_EN_ADDR   = 8'h18;
    localparam INT_STAT_ADDR = 8'h1C;
    localparam DELAY_ADDR    = 8'h20;

    localparam CTRL_EN_BIT          = 0;
    localparam CTRL_LOOPBACK_BIT    = 5;


    localparam integer IRQ_TX_EMPTY      = 0;
    localparam integer IRQ_RX_FULL       = 1;
    localparam integer IRQ_TX_OVF        = 2;
    localparam integer IRQ_RX_OVF        = 3;
    localparam integer IRQ_TRANSFER_DONE = 4;
    localparam integer IRQ_COUNT         = 5;



    // REGISTER MIRRORS
    bit [31:0] ctrl_reg;
    bit [31:0] clk_div_reg;
    bit [31:0] ss_ctrl_reg;
    bit [31:0] int_en_reg;
    bit [31:0] int_stat_reg;
    bit [31:0] delay_reg;

    /*
        Registers' clssification in your notes
    */

    // FIFO MODELS
    bit [31:0] tx_fifo[$];
    bit [31:0] rx_fifo[$];

    // EXPECTED OUTPUT QUEUES
    //bit [31:0] expected_rx_q[$];
    //bit [31:0] expected_status_q[$];          //more simple approach:compute it dynamically through get_status method
    //bit        expected_irq_q[$];             //same as last one : combinational output , derived from INT_STAT & INT_EN

    // SCOREBOARD
    int error_count;

    bit busy;                                   //derived by monitor Or we can ignore it
                                                //i will ignore it
    // CONSTRUCTOR
    function new();
        reset_model();
    endfunction

    // RESET MODEL
    function void reset_model();

        ctrl_reg     = 32'h0;
        clk_div_reg  = 32'h0;
        ss_ctrl_reg  = 32'h0;
        int_en_reg   = 32'h0;
        int_stat_reg = 32'h0;
        delay_reg    = 32'h0;

        tx_fifo.delete();
        rx_fifo.delete();

        //expected_rx_q.delete();

        error_count = 0;
        busy = 0;
    endfunction

    // APB PREDICTORS
    /*
        Checklist:
            mirror writable registers
            push TX FIFO
            clear W1C bits 
            trigger side effects
            handle flushes
            update overflow flags

        ex:
            CTRL.EN=0 => disable , FIFO flush , BUSY clear , IDLE FSM
            
        Handles:
            register update , side effects , FIFO effects , interrupt effects
    */

    
    task handle_register_write(
        input bit [7:0]  addr,
        input bit [31:0] data);

        case(addr)
            CTRL_ADDR    :   ctrl_reg     = data;
                
            CLK_DIV_ADDR :   clk_div_reg  = data;
            SS_CTRL_ADDR :   ss_ctrl_reg  = data;
            DELAY_ADDR   :   delay_reg    = data;       
            TX_DATA_ADDR :   begin 
                    if(tx_fifo.size() < FIFO_DEPTH)         //R15 
                        tx_fifo.push_back(data); 
                    else
                        int_stat_reg[IRQ_TX_OVF] = 1;
                end
            
            default: ;
        endcase
    endtask

    task handle_interrupt_write(
        input bit [7:0]  addr,
        input bit [31:0] data
    );
        //R17:int_stat_reg is sticky and clears by writing 1 to corresping bit
        if(addr == INT_STAT_ADDR)
            int_stat_reg &= ~data;
        else if(addr == INT_EN_ADDR)
            int_en_reg   = data;

    endtask

    task handle_enable_side_effects();      //side effects should operate on already-updated mirrors
        if(ctrl_reg[CTRL_EN_BIT] == 1'b0)
            begin
                /*  R3:
                        flushes tx/rx FIFOs
                */
                tx_fifo.delete();
                rx_fifo.delete();
                
            end
    endtask

    
    task predict_apb_write(
        input bit [7:0]  addr,
        input bit [31:0] data
    );
    //Predict all DUT architectural side effects caused by an APB write transaction (request queued)
    /*
        handle_register_write()               //mirror writable registers , FIFO
        handle_interrupt_write()        //clear W1C bits
        handle_enable_side_effects()    // trigger side effects
    */
        handle_register_write(addr , data);
        handle_interrupt_write(addr, data);

        if(addr == CTRL_ADDR)
            handle_enable_side_effects();


    endtask

    /*
        ex:
            Reading RX_DATA => RX FIFO pop
            Reading Status  => no side effect (So predictor may do nothing)
        Imp_summ:
            Reads are NOT always passive , Some reads change DUT state.
        Passive Reads:
            CTRL
            STATUS
            CLK_DIV
            SS_CTRL
            INT_EN
            INT_STAT
            DELAY
        Destructive Reads:
            RX_DATA => return FIFO front , THEN pop FIFO
    */
    task predict_apb_read(
        input bit [7:0] addr
    );
    //Predict architectural consequences of APB read transaction

        if(addr == RX_DATA_ADDR && (rx_fifo.size() != 0))
            rx_fifo.pop_front();

    endtask
        //CRITICAL note: in Scoreboard : calling get_expected_read_data() must be before predict_apb_read() as predict pops FIFO
    /*
        1. get expected value
        2. compare with DUT
        3. apply read side effect
    */
    function bit [31:0] get_expected_read_data(input bit [7:0] addr);
        case(addr)
            CTRL_ADDR    : return ctrl_reg;
            STATUS_ADDR  : return get_status();
            TX_DATA_ADDR : return 32'b0;                //returns 0  write-only register
            RX_DATA_ADDR : return ((rx_fifo.size() == 0) ? 32'b0 : rx_fifo.front());              //passive read
            CLK_DIV_ADDR : return clk_div_reg;
            SS_CTRL_ADDR : return ss_ctrl_reg;
            INT_STAT_ADDR: return int_stat_reg;
            INT_EN_ADDR  : return  int_en_reg;
            DELAY_ADDR   : return delay_reg;
            default      : return 32'b0;
        endcase
    endfunction

    /*
        Responsibilities:
            Inputs:
                TX word , current sampled config , MISO data/response
            Predic:
                RX word , RX FIFO push , interrupt generation , BUSY completion effect , overflow effects

        Handles:
            consume TX transaction , determine RX result , push RX FIFO , set transfer_done interrupt , update status-affecting state
            NOTE:Protocol/timing verification is not our task here we are just build predictors
        
        architectural note:
            predict_transfer() should NOT happen immediately on APB write. 
                Because: transfer may not start yet OR DUT may be disabled Or SS may not be enabled Or transfer timing independent
        
        SPI monitor observes completed transfer => predict_transfer() 

        chicklist:
            consume TX transaction
            generate RX result
            push RX FIFO
            set transfer-done interrupt
            update BUSY-related state
    */
    // TRANSFER PREDICTOR
    task predict_transfer(
        input bit [31:0] miso_data
    );
    //Predict completed SPI transfer result and its architectural effects(request executed)
        bit [31:0] sh_tx , sh_rx;
        if(tx_fifo.size() == 0 || ctrl_reg[CTRL_EN_BIT]==0)
            return;
        else
            sh_tx = tx_fifo.pop_front();
        
        //SS logic???????

        if(tx_fifo.size() == 0)
                int_stat_reg[IRQ_TX_EMPTY] = 1;

        if(ctrl_reg[CTRL_LOOPBACK_BIT])               //Loopback behaviour
            sh_rx = sh_tx;
        else
            sh_rx = miso_data;

        //we need to handle width here!!
        case(ctrl_reg[7:6])
            2'b00:  sh_rx = {24'b0,sh_rx[7:0]};
            2'b01:  sh_rx = {16'b0,sh_rx[15:0]};
            2'b10:  sh_rx = sh_rx[31:0];
            default:  sh_rx = sh_rx[31:0];     //reserved
        endcase

        if(rx_fifo.size() == FIFO_DEPTH)
            int_stat_reg[IRQ_RX_OVF] = 1;
        else
            begin
                if(rx_fifo.size() == FIFO_DEPTH-1)
                    int_stat_reg[IRQ_RX_FULL] = 1;
                rx_fifo.push_back(sh_rx);
            end

        int_stat_reg[IRQ_TRANSFER_DONE] = 1;

    endtask

    // STATUS / IRQ PREDICTORS
    function bit [31:0] get_status();
        bit [31:0] status_reg;
        status_reg = 'b0;
        status_reg[0] = busy;                                           //busy logic:must drived by monitor??
        status_reg[1] = (tx_fifo.size() == FIFO_DEPTH);                 //TX_FULL logic
        status_reg[2] = (tx_fifo.size() == 0);                          //TX_EMPTY logic
        status_reg[3] = (rx_fifo.size() == FIFO_DEPTH);                 //RX_FULL logic
        status_reg[4] = (rx_fifo.size() == 0);                          //RX_EMPTY logic
        status_reg[5] = int_stat_reg[IRQ_TX_OVF];                       //TX_OVF
        status_reg[6] = int_stat_reg[IRQ_RX_OVF];                       //RX_OVF

        return status_reg;
    endfunction

    function bit get_irq();
        return |(int_stat_reg[IRQ_COUNT-1:0] & int_en_reg[IRQ_COUNT-1:0]);
    endfunction

    // SCOREBOARD CHECKERS                                  
    task check_apb_read(                                    //check_rx apply side effects(pop RX_FIFO) after comparing
        input bit [7:0]  addr,
        input bit [31:0] observed
    );

        bit [31:0] expected;

        // 1. Sample expected BEFORE side effect
        expected = get_expected_read_data(addr);

        // 2. Compare
        if(addr == STATUS_ADDR) begin

            // Ignore BUSY bit
            if(observed[31:1] == expected[31:1])
                $display("[SCOREBOARD] STATUS read check passed");
            else begin
                $display("[SCOREBOARD] STATUS mismatch exp=%h obs=%h",
                            expected, observed);
                error_count++;
            end

        end
        else begin

            if(observed == expected)
                $display("[SCOREBOARD] APB read check passed");
            else begin
                $display("[SCOREBOARD] APB read mismatch exp=%h obs=%h",
                            expected, observed);
                error_count++;
            end

        end

        // 3. Apply read side effect AFTER compare
        predict_apb_read(addr);

    endtask

    task check_status(input bit [31:0] observed);
        bit [31:0] expected_status = get_status();
        if(observed[31:1] == expected_status[31:1])
            $display("[SCOREBOARD] Check_status run successfully ");            //we neglect busy consider it protocol verification
        else begin
            $display("[SCOREBOARD] error in check_status , expected = %h , observed = %h",expected_status,observed);
            error_count++;
        end
    endtask

    task check_irq(input bit observed);
        bit expected_irq = get_irq();
        if(observed == expected_irq)
            $display("[SCOREBOARD] check_irq run successfully ");
        else begin
            $display("[SCOREBOARD] error in check_irq , expected = %b , observed = %b",expected_irq,observed);
            error_count++;
        end
    endtask


    //Main Flows
    /*
        // APB WRITE FLOW
            // 1. Monitor captures APB write transaction
            // 2. Scoreboard calls ref_model.predict_apb_write()
            // 3. No immediate comparison
            // 4. Future observable DUT behavior validates write effect

        // APB READ FLOW(check before predict)
            // 1. Monitor captures APB read transaction
            // 2. expected = ref_model.get_expected_read_data(addr)
            // 3. Compare expected vs DUT PRDATA
            // 4. ref_model.predict_apb_read(addr)                      // apply read side effect(PoP rx_fifo)

        // SPI TRANSFER FLOW
            // 1. SPI monitor observes completed SPI transfer
            // 2. Scoreboard calls ref_model.predict_transfer()
            // 3. No immediate comparison required
            // 4. Future RX_DATA reads validate transfer result

        // IRQ FLOW
            // 1. IRQ monitor samples DUT irq output
            // 2. expected_irq = ref_model.get_irq()
            // 3. Compare expected_irq vs observed irq
    */

endclass


`endif