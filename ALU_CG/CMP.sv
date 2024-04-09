/*
###########################################
# Title:  CMP.sv
# Author: Michal Gorywoda
# Date:   29.02.2024
###########################################
*/
module COM #(
    parameter DATA_WIDTH = 32
)(
    input                       module_clk_i,
    input                       en_i,
    input [DATA_WIDTH-1:0]      a_i,
    input [DATA_WIDTH-1:0]      b_i,
    input                       leq_i,
    input                       tc_i,
    output                      lt_le_o,
    output                      ge_gt_o

);

logic clk_gated;

CKLNQD12 CMP_GATE(
    .TE(en_i),
    .E(en_i),
    .CP(module_clk_i),
    .Q(clk_gated)
);

DW01_cmp2 #(
    .width(DATA_WIDTH)
    ) CMP (
        .A(a_i), 
        .B(b_i), 
        .LEQ(leq_i),
        .TC(tc_i), 
        .LT_LE(lt_le_o), 
        .GE_GT(ge_gt_o)
);

endmodule