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

logic   [DATA_WIDTH-1:0]   a;
logic   [DATA_WIDTH-1:0]   shift;


always_comb begin
    a       = en_i ? a_i        : '0;
    shift   = en_i ? shift_i    : '0;
end



DW01_ash #(
    .A_width(DATA_WIDTH), 
    .SH_width(DATA_WIDTH)
    ) ASH (
        .A(a), 
        .DATA_TC(data_tc_i), 
        .SH(shift),
        .SH_TC(dir_sel_i), 
        .B(result_o) 
    );



endmodule