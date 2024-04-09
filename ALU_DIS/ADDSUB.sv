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

logic   [DATA_WIDTH-1:0]   a;
logic   [DATA_WIDTH-1:0]   b;
logic                      ci;


always_comb begin
    a = en_i ? a_i : '0;
    b = en_i ? b_i : '0;
    ci = en_i ? ci_i : '0;
end

DW01_addsub #(
    .width(DATA_WIDTH)
)   ADD ( 
    .A(a), 
    .B(b), 
    .CI(ci), 
    .ADD_SUB(add_sub_i),
    .SUM(sum_o), 
    .CO(co_o) 
    );

endmodule