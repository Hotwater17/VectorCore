/*
###########################################
# Title:  bit_counter.sv
# Author: Michal Gorywoda
# Date:   5.04.2023
###########################################
*/
module bit_counter #(
    parameter DATA_WIDTH = 32,
    parameter SBIT_CNT_B = $clog2(DATA_WIDTH)
)
(
    input                           clk_i,
    input                           resetn_i,
    input       [DATA_WIDTH-1:0]    data_i,
    input                           enable_i,
    output  reg [SBIT_CNT_B:0]      sbit_cnt_o
);

    logic [SBIT_CNT_B:0] sbit_number;


    integer iSbit;
    always_comb begin : sbitCntLogic
        sbit_number = '0;
        for(iSbit = 0; iSbit < DATA_WIDTH; iSbit = iSbit + 1) begin
            sbit_number =   sbit_number + data_i[iSbit];
        end
    end
    /*
    always_ff @(posedge clk_i or negedge resetn_i) begin : sbitCntReg
        if(!resetn_i)       sbit_cnt_o  <=  '0;
        else if(enable_i)   sbit_cnt_o  <=  sbit_number;
    end
    */

    always_latch begin : sbitCntLatch
        if(!resetn_i)               sbit_cnt_o  <=  '0;
        else if(enable_i && clk_i)  sbit_cnt_o  <=  sbit_number;
    end

    //assign  sbit_cnt_o  =   sbit_number;


endmodule
