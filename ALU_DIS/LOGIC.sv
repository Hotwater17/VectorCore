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

logic xor_res_inv;
logic ad_a_inv;
logic ad_res_inv;
logic or_a_inv;
logic or_res_inv;

//assign clk_logic_e     =   (alu_oc inside {{VAND, INT}, {VMSNE_VMAND, MULT}, {VOR, INT}, {VMSLTU_VMOR, MULT}, {VXOR, INT}, {VMSLT_VMXOR, MULT}, {VMSLE_VMNAND, MULT}, {VMSEQ_VMANDNOT, MULT}, {VMSGTU_VMNOR, MULT}, {VMSLEU_VMORNOT, MULT}, {VMSGT_VMXNOR, MULT}});

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
    ) XOR_GATE(
        .module_clk_i(module_clk_i),
        .a_i(a_i),
        .b_i(b_i),
        .e_i(clk_xor_e),
        .res_inv_i(xor_res_inv),
        .result_o(result_o)
    );

    AND #(
        .DATA_WIDTH(DATA_WIDTH)
    ) AND_GATE(
        .module_clk_i(module_clk_i),
        .a_i(a_i),
        .b_i(b_i),
        .e_i(clk_ad_e),
        .a_inv_i(ad_a_inv),
        .res_inv_i(ad_res_inv),
        .result_o(result_o)
    );

    OR #(
        .DATA_WIDTH(DATA_WIDTH)
    ) OR_GATE(
        .module_clk_i(module_clk_i),
        .a_i(a_i),
        .b_i(b_i),
        .e_i(clk_or_e),
        .a_inv_i(or_a_inv),
        .res_inv_i(or_res_inv),
        .result_o(result_o)
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
    logic [DATA_WIDTH-1:0] a;
    logic [DATA_WIDTH-1:0] b;

    assign a = e_i ? a_i : '0;
    assign b = e_i ? b_i : '0;

    assign result_o = res_inv_i ? ~(a ^ b) : a ^ b;

endmodule

module AND #(
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

    logic [DATA_WIDTH-1:0] a;
    logic [DATA_WIDTH-1:0] b;

    assign a = e_i ? a_i : '0;
    assign b = e_i ? b_i : '0;

    assign result_o =   res_inv_i ? ~(a_inv_i ? ~a : a) & b :
                        (a_inv_i ? ~a : a) & b;

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

    logic [DATA_WIDTH-1:0] a;
    logic [DATA_WIDTH-1:0] b;

    assign a = e_i ? a_i : '0;
    assign b = e_i ? b_i : '0;

    assign result_o =   res_inv_i ? ~(a_inv_i ? ~a : a) | b :
                        (a_inv_i ? ~a : a) | b;
endmodule