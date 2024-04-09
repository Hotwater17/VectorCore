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

logic                           a_signed;
logic                           b_signed;

logic                           is_alu;
logic                           is_mul;
logic                           is_div;
logic                           is_mac;

logic   [(DATA_WIDTH*2)-1:0]    mul_raw_out;
logic   [DATA_WIDTH-1:0]        div_result;
logic   [DATA_WIDTH-1:0]        addsub_res;
logic   [DATA_WIDTH-1:0]        mac_result;
logic   [DATA_WIDTH-1:0]        shifter_res;
logic   [DATA_WIDTH-1:0]        logic_res;
logic   [DATA_WIDTH-1:0]        com_res;

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

logic                           mul_low_e;
logic                           mul_hi_e;

assign alu_a            =   a_i;
assign alu_b            =   b_i;
assign alu_c            =   c_i; //- needs to be pipelined
assign alu_oc           =   ocode_i;

assign alu_mask_e       =   mask_e_i;
assign alu_valid        =   valid_i;

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

assign addsub_carry_e   =   (alu_oc inside {{VADC, INT}, {VMADC, INT}, {VSBC, INT}, {VMSBC, INT}});

assign clk_shifter_e    =   (alu_oc inside {{VSLL_VMUL, INT}, {VSRL, INT}, {VSRA_VMADD, INT}, {VNSRL, INT}, {VNSRA_VMACC, INT}});
assign clk_logic_e      =   (alu_oc inside {{VAND, INT}, {VMSNE_VMAND, MULT}, {VOR, INT}, {VMSLTU_VMOR, MULT}, {VXOR, INT}, {VMSLT_VMXOR, MULT}, {VMSLE_VMNAND, MULT}, {VMSEQ_VMANDNOT, MULT}, {VMSGTU_VMNOR, MULT}, {VMSLEU_VMORNOT, MULT}, {VMSGT_VMXNOR, MULT}});
assign clk_adder_e      =   (alu_oc inside {{VADD_VREDSUM, INT}, {VADC, INT}, {VMADC, INT}, {VSUB_VREDOR, INT}, {VSBC, INT}, {VMSBC, INT}, {VRSUB_VREDXOR, INT}});
assign clk_com_e        =   (alu_oc inside {{VMIN_VREDMIN, INT}, {VMINU_VREDMINU, INT}, {VMAX_VREDMAX, INT}, {VMAXU_VREDMAXU, INT}, {VMSEQ_VMANDNOT, INT}, {VMSNE_VMAND, INT}, {VMSLT_VMXOR, INT}, {VMSLTU_VMOR, INT}, {VMSLE_VMNAND, INT}, {VMSLEU_VMORNOT, INT}, {VMSGT_VMXNOR, INT}, {VMSGTU_VMNOR, INT}, {VMERGE_VCOMPRESS, INT}});
assign clk_mul_e        =   (alu_oc inside {{VSLL_VMUL, MULT}, {VMULH, MULT}, {VMULHU, MULT}, {VMULHSU, MULT}, {VNSRA_VMACC, MULT}, {VSRA_VMADD, MULT}, {VNCLIP_VNMSAC, MULT}, {VSSRA_VNMSUB, MULT}});
assign clk_mac_e        =   (alu_oc inside {{VNSRA_VMACC, MULT}, {VSRA_VMADD, MULT}, {VSSRA_VNMSUB, MULT}, {VNCLIP_VNMSAC, MULT}});

assign mul_hi_e         =   (alu_oc inside {{VMULH, MULT}, {VMULHU, MULT}, {VMULHSU, MULT}});
assign mul_low_e        =   (alu_oc inside {{VSLL_VMUL, MULT}});

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
    .DATA_WIDTH(DATA_WIDTH)
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
    .DATA_WIDTH(DATA_WIDTH)
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
    .ocode_i(alu_oc),
    .result_o(com_res)
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

SELECTOR #(
    .DATA_WIDTH(DATA_WIDTH)
) SELECTOR_I (
    .addsub_sel_i(clk_adder_e),
    .shift_sel_i(clk_shifter_e),
    .logic_sel_i(clk_logic_e),
    .mul_sel_hi_i(mul_hi_e),
    .mul_sel_low_i(mul_low_e),
    .com_sel_i(clk_com_e),
    .mac_sel_i(clk_mac_e),
    .addsub_data_i(addsub_res),
    .shift_data_i(shifter_res),
    .logic_data_i(logic_res),
    .mul_low_data_i(mul_raw_out[DATA_WIDTH-1:0]),
    .mul_hi_data_i(mul_raw_out[(DATA_WIDTH*2)-1:DATA_WIDTH]),
    .com_data_i(com_res),
    .mac_data_i(mac_result),
    .data_o(alu_q_o)
);

endmodule




