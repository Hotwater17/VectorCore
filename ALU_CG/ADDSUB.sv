/*
###########################################
# Title:  ADDSUB.sv
# Author: Michal Gorywoda
# Date:   29.02.2024
###########################################
*/
module ADDSUB #(
    parameter DATA_WIDTH = 32
)(
    input                       module_clk_i,
    input                       en_i,
    input [DATA_WIDTH-1:0]      a_i,
    input [DATA_WIDTH-1:0]      b_i,
    input                       ci_i,
    input                       add_sub_i,
    output [DATA_WIDTH-1:0]     sum_o,
    output                      co_o
);

logic clk_gated;

CKLNQD12 ADDSUB_GATE(
    .TE(en_i),
    .E(en_i),
    .CP(module_clk_i),
    .Q(clk_gated)
);

DW01_addsub #(
    .width(DATA_WIDTH)
)   ADD ( 
    .A(a_i), 
    .B(b_i), 
    .CI(ci_i), 
    .ADD_SUB(add_sub_i),
    .SUM(sum_o), 
    .CO(co_o) 
    );

endmodule