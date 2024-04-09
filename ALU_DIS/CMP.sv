/*
###########################################
# Title:  CMP.sv
# Author: Michal Gorywoda
# Date:   29.02.2024
###########################################
*/
module CMP #(
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

logic   [DATA_WIDTH-1:0]   a;
logic   [DATA_WIDTH-1:0]   b;


always_comb begin
    a = en_i ? a_i : '0;
    b = en_i ? b_i : '0;
end


DW01_cmp2 #(
    .width(DATA_WIDTH)
    ) CMP (
        .A(a), 
        .B(b), 
        .LEQ(leq_i),
        .TC(tc_i), 
        .LT_LE(lt_le_o), 
        .GE_GT(ge_gt_o)
);

endmodule