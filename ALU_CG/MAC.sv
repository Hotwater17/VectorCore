/*
###########################################
# Title:  MAC.sv
# Author: Michal Gorywoda
# Date:   26.04.2023
###########################################
*/
module MUL #
(
    parameter   DATA_WIDTH = 32
)(


    input                       module_clk_i,
    input                       en_i,
    input    [DATA_WIDTH-1:0]   a_i,

    input    [DATA_WIDTH-1:0]   b_i,

    input                   tc_i,

    output  logic unsigned  [2*DATA_WIDTH-1:0]    p_o
);

logic clk_gated;

CKLNQD24 MUL_GATE(
    .TE(en_i),
    .E(en_i),
    .CP(module_clk_i),
    .Q(clk_gated)
);


DW02_mult #(DATA_WIDTH, DATA_WIDTH)
    U1 ( 
        .A(a_i), 
        .B(b_i), 
        .TC(tc_i), 
        .PRODUCT(p_o) 
    );


endmodule