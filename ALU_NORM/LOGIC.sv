/*
###########################################
# Title:  LOGIC.sv
# Author: Michal Gorywoda
# Date:   29.02.2024
###########################################
*/
module LOGIC import vect_pkg::*; #(
    parameter DATA_WIDTH = 32
)(
    input                               clk_i,
    input                               en_i,
    input           [DATA_WIDTH-1:0]    a_i,
    input           [DATA_WIDTH-1:0]    b_i,
    input           [6:0]               ocode_i,
    output  logic   [DATA_WIDTH-1:0]    result_o

);




//Logical
always_comb begin
    unique case (ocode_i)
        {VAND, INT},
        {VMSNE_VMAND, MULT}     :   result_o = a_i & b_i;
        {VOR, INT},
        {VMSLTU_VMOR, MULT}     :   result_o = a_i | b_i;
        {VXOR, INT},
        {VMSLT_VMXOR, MULT}     :   result_o = a_i ^ b_i;
        {VMSLE_VMNAND, MULT}    :   result_o = ~(a_i & b_i);
        {VMSEQ_VMANDNOT, MULT}  :   result_o = ~a_i & b_i;
        {VMSGTU_VMNOR, MULT}    :   result_o = ~(a_i | b_i);
        {VMSLEU_VMORNOT, MULT}  :   result_o = ~a_i | b_i;
        {VMSGT_VMXNOR, MULT}    :   result_o = ~(a_i ^ b_i);
        default                 :   result_o = {DATA_WIDTH{1'b0}};
    endcase

end
endmodule