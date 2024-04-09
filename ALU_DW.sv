/*
###########################################
# Title:  ALU_DW.sv
# Author: Michal Gorywoda
# Date:   29.02.2024
###########################################
*/
module ALU import vect_pkg::*; #(
    parameter DATA_WIDTH    =   32,
    parameter PIPE_ST       =   3
)(
    input                           clk_i,
    input                           resetn_i,
    input                           valid_i,
    input                           mask_e_i,
    input   [DATA_WIDTH-1:0]        a_i,
    input   [DATA_WIDTH-1:0]        b_i,
    input   [DATA_WIDTH-1:0]        c_i,
    input   [6:0]                   ocode_i,
    output  logic [DATA_WIDTH-1:0]  alu_q_o
);


localparam SHIFT_B = $clog2(DATA_WIDTH);

logic                           com_tc;
logic                           com_lt_le;
logic                           com_ge_gt;
logic                           com_leq;

logic                           ash_tc;

logic                           a_signed;
logic                           b_signed;

logic                           is_alu;
logic                           is_mul;
logic                           is_div;
logic                           is_mac;


logic   [(DATA_WIDTH*2)-1:0]    mul_raw_out;
logic   [DATA_WIDTH-1:0]        mul_result;
logic   [DATA_WIDTH-1:0]        div_result;
logic   [DATA_WIDTH-1:0]        addsub_res;
logic   [DATA_WIDTH-1:0]        mac_result;
logic   [DATA_WIDTH-1:0]        shifter_res;
logic   [DATA_WIDTH-1:0]        logic_res;

logic                           addsub_carry_e;
logic                           alu_addsub_sel;
logic                           mac_addsub;
logic                           shifter_tc;
logic                           shifter_dir;

logic   [DATA_WIDTH-1:0]        alu_a;
logic   [DATA_WIDTH-1:0]        alu_b;
logic   [DATA_WIDTH-1:0]        alu_c;
logic   [6:0]                   alu_oc;
logic   [DATA_WIDTH-1:0]        alu_res;
logic                           alu_mask_e;
logic                           alu_valid;



// Clock gate control
logic                           clk_logic_e;
logic                           clk_adder_e;
logic                           clk_mac_e;
logic                           clk_com_e;
logic                           clk_mul_e;
logic                           clk_shifter_e;


assign alu_a                =   a_i;
assign alu_b                =   b_i;
assign alu_c                =   c_i; //- needs to be pipelined
assign alu_oc               =   ocode_i;


assign alu_mask_e          =   mask_e_i;
assign alu_valid            =   valid_i;

always_comb begin : blockName
    if(is_alu)      alu_q_o =   alu_res;
    else if(is_mul) alu_q_o =   mul_result;
    else            alu_q_o =   '0;
    //else            alu_q_o =   div_result;   
end



assign a_signed         =   (alu_oc == VMULH);
assign b_signed         =   ((alu_oc == VMULH) || alu_oc == VMULHSU);

assign is_mul           =   (alu_oc inside {{VSLL_VMUL, MULT}, {VMULH, MULT}, {VMULHU, MULT}, {VMULHSU, MULT},
                        {VSSRA_VNMSUB, MULT}, {VNSRA_VMACC, MULT}, {VNCLIP_VNMSAC, MULT}, {VSRA_VMADD, MULT}});
assign is_div           =   (alu_oc inside {{VDIV, MULT}, {VDIVU, MULT}, {VREMU, MULT}, {VREM,MULT}});   
assign is_alu           =   !is_mul && !is_div;
assign is_mac           =   (alu_oc inside {{VSSRA_VNMSUB, MULT}, {VNSRA_VMACC, MULT}, {VNCLIP_VNMSAC, MULT}, {VSRA_VMADD, MULT}}); 

//Zero extend - 0, Sign extend (arithmetic) - 1
assign shifter_tc       =   (alu_oc inside {{VSRA_VMADD, INT}, {VNSRA_VMACC, MULT}});
//Shift left - 0, shift right - 1
assign shifter_dir      =   !(alu_oc inside {{VSLL_VMUL, INT}});
/////////////////////FIX!!!/////////////////////

// 0 - add, 1 - sub
assign alu_addsub_sel   =   (alu_oc inside {{VSUB_VREDOR, INT}, {VSBC, INT}, {VMSBC, INT}, {VRSUB_VREDXOR, INT}});

// 0 - add, 1 - sub
assign mac_addsub       =   (alu_oc inside {{VSSRA_VNMSUB, MULT}, {VNCLIP_VNMSAC, MULT}});

assign addsub_carry_e  =   (alu_oc inside {{VADC, INT}, {VMADC, INT}, {VSBC, INT}, {VMSBC, INT}});

assign com_leq          =   (alu_oc inside {{VMSLT_VMXOR, INT}, {VMSLTU_VMOR, INT}});
assign com_tc           =   (alu_oc inside {{VMIN_VREDMIN, INT}, {VMINU_VREDMINU, INT}, {VMAX_VREDMAX, INT}, {VMAXU_VREDMAXU, INT}, {VMSEQ_VMANDNOT, INT}, {VMSNE_VMAND, INT}, {VMSLT_VMXOR, INT}, {VMSLTU_VMOR, INT}, {VMSLE_VMNAND, INT}, {VMSLEU_VMORNOT, INT}, {VMSGT_VMXNOR, INT}, {VMSGTU_VMNOR, INT}, {VMERGE_VCOMPRESS, INT}});



assign clk_shifter_e   =   (alu_oc inside {{VSLL_VMUL, INT}, {VSRL, INT}, {VSRA_VMADD, INT}, {VNSRL, INT}, {VNSRA_VMACC, INT}});
assign clk_logic_e     =   (alu_oc inside {{VAND, INT}, {VMSNE_VMAND, MULT}, {VOR, INT}, {VMSLTU_VMOR, MULT}, {VXOR, INT}, {VMSLT_VMXOR, MULT}, {VMSLE_VMNAND, MULT}, {VMSEQ_VMANDNOT, MULT}, {VMSGTU_VMNOR, MULT}, {VMSLEU_VMORNOT, MULT}, {VMSGT_VMXNOR, MULT}});
assign clk_adder_e     =   (alu_oc inside {{VADD_VREDSUM, INT}, {VADC, INT}, {VMADC, INT}, {VSUB_VREDOR, INT}, {VSBC, INT}, {VMSBC, INT}, {VRSUB_VREDXOR, INT}});
assign clk_com_e       =   (alu_oc inside {{VMIN_VREDMIN, INT}, {VMINU_VREDMINU, INT}, {VMAX_VREDMAX, INT}, {VMAXU_VREDMAXU, INT}, {VMSEQ_VMANDNOT, INT}, {VMSNE_VMAND, INT}, {VMSLT_VMXOR, INT}, {VMSLTU_VMOR, INT}, {VMSLE_VMNAND, INT}, {VMSLEU_VMORNOT, INT}, {VMSGT_VMXNOR, INT}, {VMSGTU_VMNOR, INT}, {VMERGE_VCOMPRESS, INT}});
assign clk_mul_e       =   (alu_oc inside {{VSLL_VMUL, MULT}, {VMULH, MULT}, {VMULHU, MULT}, {VMULHSU, MULT}, {VNSRA_VMACC, MULT}, {VSRA_VMADD, MULT}, {VNCLIP_VNMSAC, MULT}, {VSSRA_VNMSUB, MULT}});
assign clk_mac_e       =   (alu_oc inside {{VNSRA_VMACC, MULT}, {VSRA_VMADD, MULT}, {VSSRA_VNMSUB, MULT}, {VNCLIP_VNMSAC, MULT}});



LOGIC #(
    .DATA_WIDTH(DATA_WIDTH)
) LOGIC (
    .module_clk_i(clk_i),
    .e_i(clk_logic_e),
    .a_i(alu_a), 
    .b_i(alu_b), 
    .ocode_i(alu_oc), 
    .result_o(logic_res)
);

SYN_MUL I_MUL(
    .module_clk_i(clk_i),
    .en_i(clk_mul_e),
    .a_i(alu_a),
    .b_i(alu_b),
    .tc_i(b_signed),
    .result_o(mul_raw_out)

);

ADDSUB #(

) ADDSUB(
    .module_clk_i(clk_i),
    .en_i(clk_adder_e),
    .a_i(alu_a),
    .b_i(alu_b),
    .ci_i(alu_mask_e && addsub_carry_e),
    .add_sub_i(alu_addsub_sel),
    .sum_o(addsub_res),
    .co_o()
);

ADDSUB #(

) ADDSUB_MAC(
    .module_clk_i(clk_i),
    .en_i(clk_mac_e),
    .a_i(alu_c),
    .b_i(mul_raw_out[DATA_WIDTH-1:0]),
    .ci_i(alu_mask_e && addsub_carry_e),
    .add_sub_i(mac_addsub),
    .sum_o(mac_result),
    .co_o()

);

COM #(
    .DATA_WIDTH(DATA_WIDTH)
) COM(
    .module_clk_i(clk_i),
    .en_i(clk_com_e),
    .a_i(alu_a),
    .b_i(alu_b),
    .leq_i(com_leq),
    .tc_i(com_tc),
    .lt_le_o(com_lt_le),
    .ge_gt_o(com_ge_gt)

);

SHIFTER #(
    .DATA_WIDTH(DATA_WIDTH)
) SHIFTER (
    .module_clk_i(clk_i),
    .en_i(clk_shifter_e),
    .dir_sel_i(shifter_dir),
    .data_tc_i(shifter_tc),
    .a_i(alu_a),
    .shift_i(alu_b),
    .result_o(shifter_res)

);

always_comb begin : mulLogic

    if(alu_valid && alu_mask_e) begin

        unique case (alu_oc)

            //Multiply
            
            {VSLL_VMUL, MULT}       :   mul_result = mul_raw_out[DATA_WIDTH-1:0];
            {VMULH, MULT}           :   mul_result = mul_raw_out[(DATA_WIDTH*2)-1:DATA_WIDTH];
            {VMULHU, MULT}          :   mul_result = mul_raw_out[(DATA_WIDTH*2)-1:DATA_WIDTH];
            {VMULHSU, MULT}         :   mul_result = mul_raw_out[(DATA_WIDTH*2)-1:DATA_WIDTH];
            {VNSRA_VMACC, MULT}, 
            {VSRA_VMADD, MULT}      :   mul_result = mac_result;   //add C to A*B - change in register, not in ALU
            {VNCLIP_VNMSAC, MULT},
            {VSSRA_VNMSUB, MULT}    :   mul_result = mac_result;  //subtract A*B from C, change in register, not in ALU
            default                 :   mul_result = mul_raw_out[DATA_WIDTH-1:0];
        endcase
    end
    else                                mul_result = '0;
end






always_comb begin : aluLogic

    if(alu_valid && alu_mask_e) begin

        unique case (alu_oc)

            {VAND, INT},
            {VMSNE_VMAND, MULT},
            {VOR, INT},
            {VMSLTU_VMOR, MULT},
            {VXOR, INT},
            {VMSLT_VMXOR, MULT},
            {VMSLE_VMNAND, MULT},
            {VMSEQ_VMANDNOT, MULT},
            {VMSGTU_VMNOR, MULT},
            {VMSLEU_VMORNOT, MULT},
            {VMSGT_VMXNOR, MULT}    :   alu_res = logic_res;


            //Arithmetic
            {VADD_VREDSUM, INT}, 
            {VADC, INT}, 
            {VMADC, INT}            :   begin 
                                        alu_res = addsub_res;
            end
            {VSUB_VREDOR, INT},
            {VSBC, INT},
            {VMSBC, INT}            :   begin 
                                        alu_res = addsub_res;
            end
            {VRSUB_VREDXOR, INT}    :   alu_res = addsub_res;

            //Shift
            /*
            {VSLL_VMUL, INT}        :   alu_res = alu_b << alu_a[SHIFT_B-1:0];
            {VSRL, INT}             :   alu_res = alu_b >> alu_a[SHIFT_B-1:0];
            {VSRA_VMADD, INT}       :   alu_res = alu_b >>> alu_a[SHIFT_B-1:0];
            */
            {VSLL_VMUL, INT},
            {VSRL, INT},
            {VSRA_VMADD, INT}       :   alu_res = shifter_res;
            //VNSRL   :   alu_res = (alu_b >> alu_a[SHIFT_B-1:0]); //Check - but Idk if its needed 
            //VNSRA_VMACC   :   alu_res = $signed(alu_b >>> alu_a[SHIFT_B-1:0]); //Also check, also probably not needed

            //Compare
            {VMIN_VREDMIN, INT},
            {VMINU_VREDMINU, INT}, 
            {VMAX_VREDMAX, INT},
            {VMAXU_VREDMAXU, INT}   :   begin
                                        alu_res = ((com_lt_le & !com_ge_gt) ^ (alu_oc == VMAX_VREDMAX || alu_oc == VMAXU_VREDMAXU)) ? alu_b : alu_a;
            end
            {VMSEQ_VMANDNOT, INT},
            {VMSNE_VMAND, INT}      :   begin
                                        alu_res = {DATA_WIDTH{(com_lt_le & com_ge_gt) ^ (alu_oc == VMSNE_VMAND)}};
                       
            end
            {VMSLT_VMXOR, INT},
            {VMSLTU_VMOR, INT}      :   begin
                                        alu_res = {DATA_WIDTH{com_lt_le }};
            end
            {VMSLE_VMNAND, INT},
            {VMSLEU_VMORNOT, INT}   :   begin
                                        alu_res = {DATA_WIDTH{com_lt_le ^ ((alu_oc == VMSGT_VMXNOR) || (alu_oc == VMSGTU_VMNOR))}};
            end
            {VMSGT_VMXNOR, INT},
            {VMSGTU_VMNOR, INT}     :   begin
                                        alu_res = {DATA_WIDTH{!com_lt_le & com_ge_gt}};
            end      

            //Merge
            {VMERGE_VCOMPRESS, INT} :   alu_res = (alu_mask_e) ? alu_a : alu_b;



            default                 :   alu_res = {DATA_WIDTH{1'b0}};
        endcase
    end
    else                                alu_res =  {DATA_WIDTH{1'b0}};

end





endmodule




