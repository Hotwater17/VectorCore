module ALU import vect_pkg::*; #(
    parameter DATA_WIDTH    =   32,
    parameter PIPE_ST       =   3
)(
    input                           clk_i,
    input                           resetn_i,
    input                           valid_i,
    input                           mask_i,
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

logic   [DATA_WIDTH-1:0]        alu_pipe_a_q    [0:PIPE_ST-1];
logic   [DATA_WIDTH-1:0]        alu_pipe_b_q    [0:PIPE_ST-1];
logic   [DATA_WIDTH-1:0]        alu_pipe_c_q    [0:PIPE_ST-1];
//logic   [DATA_WIDTH-1:0]        alu_pipe_res_q  [0:PIPE_ST-1];
logic   [6:0]                   alu_pipe_op_q   [0:PIPE_ST-1];

logic                           alu_pipe_alb_q  [0:PIPE_ST-1];
logic                           alu_pipe_aeb_q  [0:PIPE_ST-1];
logic                           alu_pipe_m_q    [0:PIPE_ST-1];
logic                           alu_pipe_v_q    [0:PIPE_ST-1];

logic   [DATA_WIDTH-1:0]        alu_pipe_a_d    [0:PIPE_ST];
logic   [DATA_WIDTH-1:0]        alu_pipe_b_d    [0:PIPE_ST];
logic   [DATA_WIDTH-1:0]        alu_pipe_c_d    [0:PIPE_ST];
//logic   [DATA_WIDTH-1:0]        alu_pipe_res_d  [0:PIPE_ST-1];
logic   [6:0]                   alu_pipe_op_d   [0:PIPE_ST];

logic                           alu_pipe_alb_d  [0:PIPE_ST];
logic                           alu_pipe_aeb_d  [0:PIPE_ST];
logic                           alu_pipe_m_d    [0:PIPE_ST];
logic                           alu_pipe_v_d    [0:PIPE_ST];


assign a_less_b     =   $signed(alu_a < alu_b);
assign a_equal_b    =   alu_a == alu_b;
assign a_signed     =   (alu_op == VMULH);
assign b_signed     =   ((alu_op == VMULH) || alu_op == VMULHSU);

assign is_mul       =   (alu_op inside {{VSLL_VMUL, MULT}, {VMULH, MULT}, {VMULHU, MULT}, {VMULHSU, MULT}});
assign is_div       =   (alu_op inside {{VDIV, MULT}, {VDIVU, MULT}, {VREMU, MULT}, {VREM,MULT}});   
assign is_alu       =   !is_mul && !is_div;
//assign mul_raw_out   =   $signed({alu_a[DATA_WIDTH-1] & a_signed, alu_a}) * $signed({alu_b[DATA_WIDTH-1] & b_signed, alu_b});
//assign div_quotient =   alu_a / alu_b;   
//assign div_remainder=   alu_a % alu_b;
/*
DW02_mult #(
    .A_width(DATA_WIDTH), 
    .B_width(DATA_WIDTH)
    )mult (
    .A(alu_b),
    .B(alu_a),
    .TC(b_signed),
    .PRODUCT(mul_raw_out) 
);

DW_div #(
    DATA_WIDTH,
    DATA_WIDTH,
    1, //Signed
    1 //Rem = A % B
    )U1 (
    .a(alu_b), 
    .b(alu_a), //reverse the order - A/B = Vs2/Vs1
    .quotient(div_quotient),
    .remainder(div_remainder),
    .divide_by_0(div_error)
);
*/

DW_mult_pipe #
(
	.a_width(DATA_WIDTH), 
	.b_width(DATA_WIDTH), 
	.num_stages(5),
	.stall_mode(1), 
	.rst_mode(1), 
	.op_iso_mode(1)
) MULT_PIPE (
	.clk(clk_i), 
	.rst_n(resetn_i), 
	.en(is_mul),
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
            {VSRA_VMADD, MULT}      :   mul_result = mul_raw_out[DATA_WIDTH-1:0]  + alu_c;   //add B to A*C - change in register, not in ALU
            {VNCLIP_VNMSAC, MULT},
            {VSSRA_VNMSUB, MULT}    :   mul_result = -mul_raw_out[DATA_WIDTH-1:0] + alu_c;  //subtract B from A*C, change in register, not in ALU
            
        endcase
    end
end


DW_div_pipe #(
	.a_width(DATA_WIDTH), 
	.b_width(DATA_WIDTH), 
	.tc_mode(1), 
	.rem_mode(1),
	.num_stages(8), 
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
//##### PIPELINE #####

assign alu_pipe_a_d[0]      =   a_i;
assign alu_pipe_b_d[0]      =   b_i;
assign alu_pipe_c_d[0]      =   c_i;
//assign alu_pipe_res_d[0]    =   ;
assign alu_pipe_op_d[0]     =   opcode_i;

assign alu_pipe_alb_d[0]    =   a_less_b;
assign alu_pipe_aeb_d[0]    =   a_equal_b;
assign alu_pipe_m_d[0]      =   mask_en_i;
assign alu_pipe_v_d[0]      =   valid_i;

assign alu_a                =   alu_pipe_a_d[PIPE_ST];
assign alu_b                =   alu_pipe_b_d[PIPE_ST];
assign alu_c                =   alu_pipe_c_d[PIPE_ST];
assign alu_op               =   alu_pipe_op_d[PIPE_ST];

assign alu_a_less_b         =   alu_pipe_alb_d[PIPE_ST];
assign alu_a_equal_b        =   alu_pipe_aeb_d[PIPE_ST];
assign alu_mask_en          =   alu_pipe_m_d[PIPE_ST];
assign alu_valid            =   alu_pipe_v_d[PIPE_ST];

always_comb begin : blockName
    if(is_alu)      alu_q_o =   alu_res;
    else if(is_mul) alu_q_o =   mul_result;
    else            alu_q_o =   div_result;   
end



genvar iPipe;

generate

    for(iPipe = 0; iPipe < PIPE_ST; iPipe = iPipe + 1) begin

        assign alu_pipe_a_d[iPipe + 1]      = alu_pipe_a_q[iPipe];
        assign alu_pipe_b_d[iPipe + 1]      = alu_pipe_b_q[iPipe];
        assign alu_pipe_c_d[iPipe + 1]      = alu_pipe_c_q[iPipe];
        //assign alu_pipe_res_d[iPipe + 1]    = alu_pipe_res_q[iPipe];
        assign alu_pipe_op_d[iPipe + 1]     = alu_pipe_op_q[iPipe];
        assign alu_pipe_alb_d[iPipe + 1]    = alu_pipe_alb_q[iPipe];
        assign alu_pipe_aeb_d[iPipe + 1]    = alu_pipe_aeb_q[iPipe];
        assign alu_pipe_m_d[iPipe + 1]      = alu_pipe_m_q[iPipe];   
        assign alu_pipe_v_d[iPipe + 1]      = alu_pipe_v_q[iPipe];   

        
        always_ff @(posedge clk_i or negedge resetn_i) begin : aluPipe
            if(!resetn_i) begin
                alu_pipe_a_q[iPipe]     <=  '0;    
                alu_pipe_b_q[iPipe]     <=  '0;
                alu_pipe_c_q[iPipe]     <=  '0;
                //alu_pipe_res_q[iPipe]   <=  '0;
                alu_pipe_op_q[iPipe]    <=  '0;
                alu_pipe_alb_q[iPipe]   <=  '0;  
                alu_pipe_aeb_q[iPipe]   <=  '0;
                alu_pipe_m_q[iPipe]     <=  '0;  
                alu_pipe_v_q[iPipe]     <=  '0;  
                
            end
            else if(valid_i) begin
                alu_pipe_a_q[iPipe]     <=  alu_pipe_a_d[iPipe];
                alu_pipe_b_q[iPipe]     <=  alu_pipe_b_d[iPipe];
                alu_pipe_c_q[iPipe]     <=  alu_pipe_c_d[iPipe];
                //alu_pipe_res_q[iPipe]   <=  alu_pipe_res_d[iPipe];
                alu_pipe_op_q[iPipe]    <=  alu_pipe_op_d[iPipe];
                alu_pipe_alb_q[iPipe]   <=  alu_pipe_alb_d[iPipe];  
                alu_pipe_aeb_q[iPipe]   <=  alu_pipe_aeb_d[iPipe];  
                alu_pipe_m_q[iPipe]     <=  alu_pipe_m_d[iPipe];    
                alu_pipe_v_q[iPipe]     <=  alu_pipe_v_d[iPipe];    
            end
        end    
        
/*
        SEQGEN A_PIPE(
            .EN(valid_i),
            .AC(resetn_i),
            .D(alu_pipe_a_d[iPipe]),
            .Q(alu_pipe_a_q[iPipe]),
            .CLK(clk_i)
        );
        SEQGEN B_PIPE(
            .EN(valid_i),
            .AC(resetn_i),
            .D(alu_pipe_b_d[iPipe]),
            .Q(alu_pipe_b_q[iPipe]),
            .CLK(clk_i)
        );   
        SEQGEN C_PIPE(
            .EN(valid_i),
            .AC(resetn_i),
            .D(alu_pipe_c_d[iPipe]),
            .Q(alu_pipe_c_q[iPipe]),
            .CLK(clk_i)
        );
        SEQGEN OP_PIPE(
            .EN(valid_i),
            .AC(resetn_i),
            .D(alu_pipe_op_d[iPipe]),
            .Q(alu_pipe_op_q[iPipe]),
            .CLK(clk_i)
        );
*/

    end

endgenerate


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
            {VMSBC, INT}   :   begin 
                                        alu_res = alu_b - alu_a; //MASK
            end
            {VRSUB_VREDXOR, INT}   :    alu_res = alu_a - alu_b;

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




