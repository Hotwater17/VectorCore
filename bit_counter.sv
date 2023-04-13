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
    input   [DATA_WIDTH-1:0]    data_i,
    output  [SBIT_CNT_B-1:0]    sbit_cnt_o
);

    logic [SBIT_CNT_B-1:0] sbit_number;


    integer iSbit;
    always_comb begin : sbitCntLogic
        sbit_number = {SBIT_CNT_B{1'b0}};
        for(iSbit = 0; iSbit < DATA_WIDTH; iSbit = iSbit + 1) begin
            sbit_number =   sbit_number + data_i[iSbit];
        end
    end
    assign  sbit_cnt_o  =   sbit_number;


endmodule
