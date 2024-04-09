/*
###########################################
# Title:  SHIFTER.sv
# Author: Michal Gorywoda
# Date:   29.02.2024
###########################################
*/
module SHIFTER #(
    parameter DATA_WIDTH = 32
    )(
    input                       module_clk_i,
    input                       en_i,
    input                       dir_sel_i,  
    input                       data_tc_i,
    input [DATA_WIDTH-1:0]      a_i,
    input [DATA_WIDTH-1:0]      shift_i,
    output [DATA_WIDTH-1:0]     result_o

);

logic clk_gated;

CKLNQD12 SHIFTER_GATE(
    .TE(en_i),
    .E(en_i),
    .CP(module_clk_i),
    .Q(clk_gated)
);


DW01_ash #(
    .A_width(DATA_WIDTH), 
    .SH_width(DATA_WIDTH)
    ) ASH (
        .A(a_i), 
        .DATA_TC(data_tc_i), 
        .SH(shift_i),
        .SH_TC(dir_sel_i), 
        .B(result_o) 
    );



endmodule