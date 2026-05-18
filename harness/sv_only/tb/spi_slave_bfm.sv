
`ifndef SPI_SLAVE_BFM_SV
`define SPI_SLAVE_BFM_SV
`timescale 1ns/1ps

/*
    drive MISO correctly
    capture MOSI
    obey SPI mode timing
    emulate SPI slave behavior enough for DUT verification
*/

/*
    Critical note:
        SS_act responds to any SS line that is not assigned to a specific slave.
    review specs again.
*/

module spi_slave_bfm (
    spi_if.slave  spi,
    input  logic  [1:0] mode,        // {CPOL, CPHA}
    input  logic  [31:0] miso_frame,    // pattern repeatedly returned on MISO
    input logic [1:0] data_size,
    input logic lsb_first              
);

    logic sclk_q;   // SCLK previous value for edge detection
    int bit_count , bit_count_tx;  //count no of bits sampled
    logic [31:0] mosi_shift_reg;
    logic [31:0] rx_queue[$];

    logic [31:0] next_mosi;
    int frame_width;

    wire cpol  = mode[1];
    wire cpha  = mode[0];
    wire ss_act = (spi.ss_n != 4'hF);               //ANY slave select active activates the BFM

    //For supporting four modes
    logic rise_edge;
    logic fall_edge;

    logic leading_edge;
    logic trailing_edge;

    logic sample_edge;
    logic shift_edge;

    assign rise_edge = (sclk_q == 0 && spi.sclk == 1);
    assign fall_edge = (sclk_q == 1 && spi.sclk == 0);

    assign leading_edge  = (cpol) ? fall_edge : rise_edge;
    assign trailing_edge = (cpol) ? rise_edge : fall_edge;

    assign sample_edge = (cpha) ? trailing_edge : leading_edge;
    assign shift_edge  = (cpha) ? leading_edge  : trailing_edge;

    function int get_frame_width();
        case(data_size)
            2'b00: return 8;
            2'b01: return 16;
            default: return 32;                 //according to GM default will be 32 
        endcase
    endfunction

    always_comb
        frame_width = get_frame_width();

    function int get_tx_index(int count);
        if(lsb_first)
            return count;
        else
            return frame_width-1-count;
    endfunction

    function void clear_rx_queue();
        rx_queue.delete();
    endfunction

    function int get_rx_queue_size();
        return rx_queue.size();
    endfunction

    task automatic pop_frame(output logic [31:0] frame);
        if(rx_queue.size() == 0)
            $fatal("[SPI_BFM] RX queue empty");

        frame = rx_queue.pop_front();
    endtask

    task automatic wait_for_frame();
        wait(rx_queue.size() > 0);
    endtask
    
    initial begin
        spi.cb_slave.miso <= 1'b0;
        sclk_q  = 1'b0;
        bit_count = 0;
    end



    always @(posedge spi.pclk) begin
        if (!ss_act)
            sclk_q <= cpol;
        else
            sclk_q <= spi.sclk;
    end


    always @(posedge spi.pclk) begin
        if (!ss_act) begin
            bit_count <= 0;
            bit_count_tx <= 0;
            if(cpha == 0) begin
                spi.cb_slave.miso <= miso_frame[get_tx_index(bit_count_tx)];
                bit_count_tx      <= 1;
            end

            mosi_shift_reg <= '0;
        end else begin
            // Change MISO on the falling edge of SCLK (mode 0 convention
            // from the DUT's perspective: setup on falling, sample on rising)
            if (shift_edge) begin
                $display("[SPI_BFM] SHIFT edge");
                spi.cb_slave.miso <= miso_frame[get_tx_index(bit_count_tx)];

                if(bit_count_tx == frame_width-1)
                    bit_count_tx <= 0;
                else
                    bit_count_tx <= bit_count_tx + 1;

            end

            if(sample_edge) begin
                //Sampling logic
                $display("[SPI_BFM] SAMPLE edge");

                if(lsb_first) begin
                    next_mosi = (mosi_shift_reg >> 1);
                    next_mosi[frame_width-1] = spi.mosi;
                end
                else begin
                    next_mosi = (mosi_shift_reg << 1);
                    next_mosi[0] = spi.mosi;
                end

                if(bit_count == frame_width - 1) begin                         //not get_frame_width() due to semantics
                    case(frame_width)
                        8  : rx_queue.push_back(next_mosi & 32'h000000FF);
                        16 : rx_queue.push_back(next_mosi & 32'h0000FFFF);
                        default : rx_queue.push_back(next_mosi);
                    endcase
                    $display("[SPI_SLV_BFM] RX Frame = %h", next_mosi);
                    mosi_shift_reg <= '0;
                    bit_count <= 0;
                end
                else begin
                    bit_count <= bit_count + 1;
                    mosi_shift_reg <= next_mosi;
                end

            end
        end
    end

endmodule

`endif // SPI_SLAVE_BFM_SV
