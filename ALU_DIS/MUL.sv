/*
###########################################
# Title:  MUL.sv
# Author: Michal Gorywoda
# Date:   26.04.2023
###########################################
*/
module SYN_MUL #
(
    parameter   DATA_WIDTH = 32
)(

    input                                       module_clk_i,
    input                                       en_i,
    input    [DATA_WIDTH-1:0]                   a_i,
    input    [DATA_WIDTH-1:0]                   b_i,
    input    tc_i,

    output  logic unsigned  [2*DATA_WIDTH-1:0]  result_o
);

logic   [DATA_WIDTH-1:0]   a;
logic   [DATA_WIDTH-1:0]   b;


always_comb begin
    a = en_i ? a_i : '0;
    b = en_i ? b_i : '0;
end

DW02_mult #(DATA_WIDTH, DATA_WIDTH)
    U1 ( 
        .A(a), 
        .B(b), 
        .TC(tc_i), 
        .PRODUCT(result_o) 
    );

endmodule