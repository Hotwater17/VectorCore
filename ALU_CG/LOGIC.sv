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
    input                               module_clk_i,
    input                               e_i,
    input           [DATA_WIDTH-1:0]    a_i,
    input           [DATA_WIDTH-1:0]    b_i,
    input           [6:0]               ocode_i,
    output  logic   [DATA_WIDTH-1:0]    result_o

);

logic clk_gated;

logic clk_xor_e;
logic clk_ad_e;
logic clk_or_e;

logic clk_xor;
logic clk_ad;
logic clk_or;

logic xor_res_inv;
logic ad_a_inv;
logic ad_res_inv;
logic or_a_inv;
logic or_res_inv;

logic [DATA_WIDTH-1:0]  xor_result;
logic [DATA_WIDTH-1:0]  ad_result;
logic [DATA_WIDTH-1:0]  or_result;


always_comb begin : RES_MUX
    case ({clk_xor_e, clk_ad_e, clk_or_e})
        3'b100   :   
            result_o = xor_result;
        3'b010   :   
            result_o = ad_result;
        3'b001   :   
            result_o = or_result; 
        default: 
            result_o = or_result;
    endcase
end


CKLNQD12 LOGIC_GATE(
    .TE(e_i),
    .E(e_i),
    .CP(module_clk_i),
    .Q(clk_gated)
);

CKLNQD12 XOR_I_GATE(
    .TE(clk_xor_e),
    .E(clk_xor_e),
    .CP(module_clk_i),
    .Q(clk_xor)
);

CKLNQD12 OR_I_GATE(
    .TE(clk_or_e),
    .E(clk_or_e),
    .CP(module_clk_i),
    .Q(clk_or)
);

CKLNQD12 AD_I_GATE(
    .TE(clk_ad_e),
    .E(clk_ad_e),
    .CP(module_clk_i),
    .Q(clk_ad)
);


assign clk_xor_e = (ocode_i inside {{VXOR, INT}, {VMSLT_VMXOR, MULT}, {VMSGT_VMXNOR ,MULT}});
assign clk_ad_e = (ocode_i inside {{VAND, INT}, {VMSNE_VMAND, MULT}, {VMSEQ_VMANDNOT, MULT}});
assign clk_or_e  = (ocode_i inside {{VOR, INT}, {VMSLEU_VMORNOT, MULT}, {VMSGTU_VMNOR, MULT}, {VMSLTU_VMOR, MULT}});

assign xor_res_inv = (ocode_i inside {{VMSGT_VMXNOR, MULT}});
assign ad_a_inv   = (ocode_i inside {{VMSEQ_VMANDNOT, MULT}});
assign ad_res_inv = (ocode_i inside {{VMSLE_VMNAND, MULT}});
assign or_a_inv    = (ocode_i inside {{VMSLEU_VMORNOT, MULT}});
assign or_res_inv  = (ocode_i inside {{VMSGTU_VMNOR, MULT}});



/*
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

end*/

    XOR #(
        .DATA_WIDTH(DATA_WIDTH)
    ) XOR_I(
        .module_clk_i(clk_xor),
        .a_i(a_i),
        .b_i(b_i),
        .e_i(clk_xor_e),
        .res_inv_i(xor_res_inv),
        .result_o(xor_result)
    );

    AD #(
        .DATA_WIDTH(DATA_WIDTH)
    ) AD_I(
        .module_clk_i(clk_ad),
        .a_i(a_i),
        .b_i(b_i),
        .e_i(clk_ad_e),
        .a_inv_i(ad_a_inv),
        .res_inv_i(ad_res_inv),
        .result_o(ad_result)
    );

    OR #(
        .DATA_WIDTH(DATA_WIDTH)
    ) OR_I(
        .module_clk_i(clk_or),
        .a_i(a_i),
        .b_i(b_i),
        .e_i(clk_or_e),
        .a_inv_i(or_a_inv),
        .res_inv_i(or_res_inv),
        .result_o(or_result)
    );


endmodule

module XOR #(
    parameter DATA_WIDTH = 32
)(
    input                               module_clk_i,
    input           [DATA_WIDTH-1:0]    a_i,
    input           [DATA_WIDTH-1:0]    b_i,
    input                               e_i,
    input                               res_inv_i,
    output  logic   [DATA_WIDTH-1:0]    result_o

);


    assign result_o = res_inv_i ? ~(a_i ^ b_i) : a_i ^ b_i;

endmodule

module AD #(
    parameter DATA_WIDTH = 32
)(
    input                               module_clk_i,
    input           [DATA_WIDTH-1:0]    a_i,
    input           [DATA_WIDTH-1:0]    b_i,
    input                               e_i,
    input                               a_inv_i,
    input                               res_inv_i,
    output  logic   [DATA_WIDTH-1:0]    result_o

);

    assign result_o =   res_inv_i ? ~(a_inv_i ? ~a_i : a_i) & b_i :
                        (a_inv_i ? ~a_i : a_i) & b_i;

endmodule

module OR #(
    parameter DATA_WIDTH = 32
)(
    input                               module_clk_i,
    input           [DATA_WIDTH-1:0]    a_i,
    input           [DATA_WIDTH-1:0]    b_i,
    input                               e_i,
    input                               a_inv_i,
    input                               res_inv_i,
    output  logic   [DATA_WIDTH-1:0]    result_o

);

    assign result_o =   res_inv_i ? ~(a_inv_i ? ~a_i : a_i) | b_i :
                        (a_inv_i ? ~a_i : a_i) | b_i;
endmodule