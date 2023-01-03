module ALU import vect_pkg::*; #(
    parameter DATA_WIDTH    =   32,
    parameter PIPE_ST       =   5
)(
    input                           clk_i,
    input                           resetn_i,
    input                           valid_i,
    input                           mask_en_i,
    input   [DATA_WIDTH-1:0]        a_i,
    input   [DATA_WIDTH-1:0]        b_i,
    input   [DATA_WIDTH-1:0]        c_i,
    input   [6:0]                   opcode_i,
    output  logic [DATA_WIDTH-1:0]  alu_q_o
);


localparam SHIFT_B = $clog2(DATA_WIDTH);

logic                           a_less_b;
logic                           a_equal_b;
logic                           a_signed;
logic                           b_signed;

logic                           is_mul;
logic                           is_div;
logic                           is_mac;
logic   [(DATA_WIDTH*2)-1:0]    mul_raw_out;
logic   [DATA_WIDTH-1:0]        div_quotient;
logic   [DATA_WIDTH-1:0]        div_remainder;
logic                           div_error;
logic   [DATA_WIDTH-1:0]        mul_result;
logic   [DATA_WIDTH-1:0]        div_result;

logic   [DATA_WIDTH-1:0]        alu_a;
logic   [DATA_WIDTH-1:0]        alu_b;
logic   [DATA_WIDTH-1:0]        alu_c;
logic   [6:0]                   alu_op;
logic   [DATA_WIDTH-1:0]        alu_res;
logic                           alu_a_less_b;
logic                           alu_a_equal_b;
logic                           alu_mask_en;
logic                           alu_valid;



assign a_less_b     =   $signed(alu_a < alu_b);
assign a_equal_b    =   alu_a == alu_b;
assign a_signed     =   (alu_op == VMULH);
assign b_signed     =   ((alu_op == VMULH) || alu_op == VMULHSU);

assign is_mul       =   (alu_op inside {{VSLL_VMUL, MULT}, {VMULH, MULT}, {VMULHU, MULT}, {VMULHSU, MULT},
                        {VSSRA_VNMSUB, MULT}, {VNSRA_VMACC, MULT}, {VNCLIP_VNMSAC, MULT}, {VSRA_VMADD, MULT}});
assign is_div       =   (alu_op inside {{VDIV, MULT}, {VDIVU, MULT}, {VREMU, MULT}, {VREM,MULT}});   
assign is_alu       =   !is_mul && !is_div;
assign is_mac       =   (alu_op inside {{VSSRA_VNMSUB, MULT}, {VNSRA_VMACC, MULT}, {VNCLIP_VNMSAC, MULT}, {VSRA_VMADD, MULT}}); 

//assign mul_raw_out   =   $signed({alu_a[DATA_WIDTH-1] & a_signed, alu_a}) * $signed({alu_b[DATA_WIDTH-1] & b_signed, alu_b});
//assign div_quotient =   alu_a / alu_b;   
//assign div_remainder=   alu_a % alu_b;


  ///////////////////////
  // C (Vs3) pipeline for MAC - multiplier is pipelined       
  ///////////////////////

logic   [DATA_WIDTH-1:0]    c_pipe_d [0:PIPE_ST-1];
logic   [DATA_WIDTH-1:0]    c_pipe_q [0:PIPE_ST-2];


assign  c_pipe_d[0] =   c_i;
assign  alu_c       =   c_pipe_q[PIPE_ST-2];
genvar iC;
generate
    for(iC = 0; iC < PIPE_ST-1; iC = iC + 1) begin

        assign  c_pipe_d[iC+1]    =   c_pipe_q[iC];
        always_ff @(posedge clk_i or negedge resetn_i) begin : CPipe
            if(~resetn_i)   c_pipe_q[iC]    <=    '0;
            else if(is_mac) c_pipe_q[iC]    <=    c_pipe_d[iC];
        end  
    end

endgenerate


  ///////////////////////
  // Pipelined multiplier from DW
  // Replace with your own design       
  ///////////////////////

DW_mult_pipe #
(
	.a_width(DATA_WIDTH), 
	.b_width(DATA_WIDTH), 
	.num_stages(PIPE_ST),
	.stall_mode(1), 
	.rst_mode(1), 
	.op_iso_mode(1)
) MULT_PIPE (
	.clk(clk_i), 
	.rst_n(resetn_i), 
	.en(is_mul && mask_en_i),
	//.tc(mul_b_is_signed), 
    .tc(b_signed), 
	.a(alu_b), 
	.b(alu_a),
	.product(mul_raw_out) 
);


always_comb begin : mulLogic

    if(alu_valid && alu_mask_en) begin

        unique case (alu_op)

            //Multiply
            
            {VSLL_VMUL, MULT}       :   mul_result = mul_raw_out[DATA_WIDTH-1:0];
            {VMULH, MULT}           :   mul_result = mul_raw_out[(DATA_WIDTH*2)-1:DATA_WIDTH];
            {VMULHU, MULT}          :   mul_result = mul_raw_out[(DATA_WIDTH*2)-1:DATA_WIDTH];
            {VMULHSU, MULT}         :   mul_result = mul_raw_out[(DATA_WIDTH*2)-1:DATA_WIDTH];

            {VNSRA_VMACC, MULT}, 
            {VSRA_VMADD, MULT}      :   mul_result = mul_raw_out[DATA_WIDTH-1:0]  + alu_c;   //add C to A*B - change in register, not in ALU
            {VNCLIP_VNMSAC, MULT},
            {VSSRA_VNMSUB, MULT}    :   mul_result = -mul_raw_out[DATA_WIDTH-1:0] + alu_c;  //subtract A*B from C, change in register, not in ALU
            default                 :   mul_result = '0;
        endcase
    end
end

/*
DW_div_pipe #(
	.a_width(DATA_WIDTH), 
	.b_width(DATA_WIDTH), 
	.tc_mode(1), 
	.rem_mode(1),
	.num_stages(PIPE_ST), 
	.stall_mode(1), 
	.rst_mode(1),
	.op_iso_mode(1)
    ) DIV_PIPE (
	.clk(clk_i),
	.rst_n(resetn_i),
	.en(is_div),
    .a(alu_b), 
    .b(alu_a), //reverse the order - A/B = Vs2/Vs1
    .quotient(div_quotient),
    .remainder(div_remainder),
    .divide_by_0(div_error)
);


always_comb begin : divLogic

    if(alu_valid && alu_mask_en) begin

        unique case (alu_op)
            //Divide
            //Divide will require separate unit, it's too slow
            {VDIV, MULT},  
            {VDIVU, MULT}           :   div_result = div_quotient;
            {VREMU, MULT},    
            {VREM,MULT}             :   div_result = div_remainder; 
            
        endcase
    end
end
*/


assign alu_a                =   a_i;
assign alu_b                =   b_i;
//assign alu_c                =   c_i; - needs to be pipelined
assign alu_op               =   opcode_i;

assign alu_a_less_b         =   a_less_b;
assign alu_a_equal_b        =   a_equal_b;
assign alu_mask_en          =   mask_en_i;
assign alu_valid            =   valid_i;

always_comb begin : blockName
    if(is_alu)      alu_q_o =   alu_res;
    else if(is_mul) alu_q_o =   mul_result;
    else            alu_q_o =   '0;
    //else            alu_q_o =   div_result;   
end




always_comb begin : aluLogic

    if(alu_valid && alu_mask_en) begin

        unique case (alu_op)
            //Logical and masked
            {VAND, INT},
            {VMSNE_VMAND, MULT}     :   alu_res = alu_a & alu_b;
            {VOR, INT},
            {VMSLTU_VMOR, MULT}     :   alu_res = alu_a | alu_b;
            {VXOR, INT},
            {VMSLT_VMXOR, MULT}     :   alu_res = alu_a ^ alu_b;
            {VMSLE_VMNAND, MULT}    :   alu_res = ~(alu_a & alu_b);
            {VMSEQ_VMANDNOT, MULT}  :   alu_res = ~alu_a & alu_b;
            {VMSGTU_VMNOR, MULT}    :   alu_res = ~(alu_a | alu_b);
            {VMSLEU_VMORNOT, MULT}  :   alu_res = ~alu_a | alu_b;
            {VMSGT_VMXNOR, MULT}    :   alu_res = ~(alu_a ^ alu_b);


            //Arithmetic
            {VADD_VREDSUM, INT}, 
            {VADC, INT}, 
            {VMADC, INT}            :   begin 
                                        alu_res = alu_a + alu_b; //MASK!
            end
            {VSUB_VREDOR, INT},
            {VSBC, INT},
            {VMSBC, INT}            :   begin 
                                        alu_res = alu_b - alu_a; //MASK
            end
            {VRSUB_VREDXOR, INT}    :   alu_res = alu_a - alu_b;

            //Shift
            {VSLL_VMUL, INT}        :   alu_res = alu_b << alu_a[SHIFT_B-1:0];
            {VSRL, INT}             :   alu_res = alu_b >> alu_a[SHIFT_B-1:0];
            {VSRA_VMADD, INT}       :   alu_res = alu_b >>> alu_a[SHIFT_B-1:0];
            //VNSRL   :   alu_res = (alu_b >> alu_a[SHIFT_B-1:0]); //Check - but Idk if its needed 
            //VNSRA_VMACC   :   alu_res = $signed(alu_b >>> alu_a[SHIFT_B-1:0]); //Also check, also probably not needed

            //Compare
            {VMIN_VREDMIN, INT},
            {VMINU_VREDMINU, INT},
            {VMAX_VREDMAX, INT},
            {VMAXU_VREDMAXU, INT}   :   begin
                                        alu_res = (alu_a_less_b ^ (alu_op == VMAX_VREDMAX || alu_op == VMAXU_VREDMAXU)) ? alu_b : alu_a;
            end
            {VMSEQ_VMANDNOT, INT},
            {VMSNE_VMAND, INT}      :   begin
                                        alu_res = {DATA_WIDTH{alu_a_equal_b ^ (alu_op == VMSNE_VMAND)}};
                       
            end
            {VMSLT_VMXOR, INT},
            {VMSLTU_VMOR, INT}      :   begin
                                        alu_res = {DATA_WIDTH{alu_a_less_b}};
            end
            {VMSLE_VMNAND, INT},
            {VMSLEU_VMORNOT, INT},
            {VMSGT_VMXNOR, INT},
            {VMSGTU_VMNOR, INT}     :   begin
                                        alu_res = {DATA_WIDTH{(alu_a_less_b || alu_a_equal_b) ^ ((alu_op == VMSGT_VMXNOR) || (alu_op == VMSGTU_VMNOR))}};
            end      

            //Merge
            {VMERGE_VCOMPRESS, INT} :   alu_res = (alu_mask_en) ? alu_a : alu_b;



            default                 :   alu_res = {DATA_WIDTH{1'b0}};
        endcase
    end
    else                                alu_res =  {DATA_WIDTH{1'b0}};

end

endmodule




