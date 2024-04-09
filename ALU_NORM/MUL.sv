/*
###########################################
# Title:  MUL.sv
# Author: Michal Gorywoda
# Date:   26.04.2023
###########################################
*/
module MUL #
(
    parameter   DATA_WIDTH = 32
)(

    input                                       clk_i,
    input                                       en_i,
    input    [DATA_WIDTH-1:0]                   a_i,
    input    [DATA_WIDTH-1:0]                   b_i,
    input    tc_i,

    output  logic unsigned  [2*DATA_WIDTH-1:0]  result_o
);


DW02_mult #(DATA_WIDTH, DATA_WIDTH)
    U1 ( 
        .A(a_i), 
        .B(b_i), 
        .TC(tc_i), 
        .PRODUCT(result_o) 
    );

endmodule