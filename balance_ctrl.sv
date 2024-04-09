
/*
###########################################
# Title:  balance_ctrl.sv
# Author: Michal Gorywoda
# Date:   5.04.2023
###########################################
*/

module balance_ctrl #(
    parameter   DATA_WIDTH    = 32,
    parameter   SBIT_CNT_B    = $clog2(DATA_WIDTH),
    parameter   LANES         = 4,
    parameter   ELEMS         = 4,
    parameter   REGS          = 32
)(
    input   [SBIT_CNT_B:0]    lane_sbit_cnt_i   [LANES-1:0],
    output  [SBIT_CNT_B:0]    balance_cnt_o     [LANES-2:0]
);

    logic   [DATA_WIDTH-1:0]    lane_sbit_diff  [LANES-2:0];
    logic   [SBIT_CNT_B:0]      lane_sbit_abs   [LANES-2:0];

    logic   [SBIT_CNT_B:0]      lane_sbit_prev  [LANES-1:0];

    //logic   [SBIT_CNT_B-1:0]    lane_sbit_reg_entry [ELEMS-1:0][REGS-1:0][LANES-1:0];


    genvar i;

    generate
        for(i = 0; i < LANES-1; i = i + 1) begin : sbitCmpGen
            assign lane_sbit_diff[i] = lane_sbit_cnt_i[i] - lane_sbit_cnt_i[i+1];
        //2's complement to sign-magnitude conversion
            always_comb begin
                if(lane_sbit_diff[i][SBIT_CNT_B]) lane_sbit_abs[i]    =   {(~lane_sbit_diff[i]+ 1)};
                else                                lane_sbit_abs[i]    =   lane_sbit_diff[i];
            end
            assign balance_cnt_o[i] =   lane_sbit_abs[i];    
        end
    endgenerate
    /*
        What do I need to store a previously written number of bits?
        -I need to store number of bits written to EACH REGISTER previously
        This means I need an entry with each register and its elements 
            (32 regs x 4 lanes x 4 elements x 5 bits) = 2560 bits
            That's a lot of memory!
        -I also need the currently written register number
            I can take this from currently executed instruction
        -Element number
            That I need to take directly from lane

        -In future, also take masking into account
            Mask bits are readily available from lane. 


    */
endmodule
