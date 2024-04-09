/*
###########################################
# Title:  CMP.sv
# Author: Michal Gorywoda
# Date:   29.02.2024
###########################################
*/
module COM import vect_pkg::*; #(
    parameter DATA_WIDTH = 32
)(
    input                               module_clk_i,
    input                               en_i,
    input           [DATA_WIDTH-1:0]    a_i,
    input           [DATA_WIDTH-1:0]    b_i,
    input           [6:0]               ocode_i,
    output  logic   [DATA_WIDTH-1:0]    result_o
);

logic clk_gated;

logic                           com_tc;
logic                           com_lt_le;
logic                           com_ge_gt;
logic                           com_leq;

assign com_leq          =   (ocode_i inside {{VMSLT_VMXOR, INT}, {VMSLTU_VMOR, INT}});
assign com_tc           =   (ocode_i inside {{VMIN_VREDMIN, INT}, {VMINU_VREDMINU, INT}, {VMAX_VREDMAX, INT}, {VMAXU_VREDMAXU, INT}, {VMSEQ_VMANDNOT, INT}, {VMSNE_VMAND, INT}, {VMSLT_VMXOR, INT}, {VMSLTU_VMOR, INT}, {VMSLE_VMNAND, INT}, {VMSLEU_VMORNOT, INT}, {VMSGT_VMXNOR, INT}, {VMSGTU_VMNOR, INT}, {VMERGE_VCOMPRESS, INT}});


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
        .LEQ(com_leq),
        .TC(com_tc), 
        .LT_LE(com_lt_le), 
        .GE_GT(com_ge_gt)
);

always_comb begin : CMP_SEL
    

    case (ocode_i)
        {VMIN_VREDMIN, INT},
        {VMINU_VREDMINU, INT}, 
        {VMAX_VREDMAX, INT},
        {VMAXU_VREDMAXU, INT}   :   begin
            result_o = ((com_lt_le & !com_ge_gt) ^ (ocode_i == VMAX_VREDMAX || ocode_i == VMAXU_VREDMAXU)) ? b_i : a_i;
        end
        {VMSEQ_VMANDNOT, INT},
        {VMSNE_VMAND, INT}      :   begin
            result_o = {DATA_WIDTH{(com_lt_le & com_ge_gt) ^ (ocode_i == VMSNE_VMAND)}};
                   
        end
        {VMSLT_VMXOR, INT},
        {VMSLTU_VMOR, INT}      :   begin
            result_o = {DATA_WIDTH{com_lt_le}};
        end
        {VMSLE_VMNAND, INT},
        {VMSLEU_VMORNOT, INT}   :   begin
            result_o = {DATA_WIDTH{com_lt_le ^ ((ocode_i == VMSGT_VMXNOR) || (ocode_i == VMSGTU_VMNOR))}};
        end
        default                 :   
            result_o = {DATA_WIDTH{com_lt_le}};           
    endcase
end

endmodule