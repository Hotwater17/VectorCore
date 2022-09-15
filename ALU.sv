module ALU import vect_pkg::*; #(
    parameter DATA_WIDTH = 32
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

logic   a_less_b;
logic   a_equal_b;
logic   a_signed;
logic   b_signed;

logic   [(DATA_WIDTH*2)-1:0]    mul_result;
logic   [DATA_WIDTH-1:0]        div_quotient;
logic   [DATA_WIDTH-1:0]        div_remainder;
logic                           div_error;


assign a_less_b = $signed(a_i < b_i);
assign a_equal_b = a_i == b_i;
assign a_signed = (opcode_i == VMULH);
assign b_signed = ((opcode_i == VMULH) || opcode_i == VMULHSU);

//assign mul_result = $signed({a_i[DATA_WIDTH-1] & a_signed, a_i}) * $signed({b_i[DATA_WIDTH-1] & b_signed, b_i});


DW02_mult #(
    .A_width(DATA_WIDTH), 
    .B_width(DATA_WIDTH)
    )mult (
    .A(b_i),
    .B(a_i),
    .TC(b_signed),
    .PRODUCT(mul_result) 
);

DW_div #(
    DATA_WIDTH,
    DATA_WIDTH,
    1, //Signed
    1 //Rem = A % B
    )U1 (
    .a(b_i), 
    .b(a_i), //reverse the order - A/B = Vs2/Vs1
    .quotient(div_quotient),
    .remainder(div_remainder),
    .divide_by_0(div_error)
);

/*
logic div_en;
assign div_en = (opcode_i inside {{VDIV, MULT}, {VDIVU, MULT},
{VREMU, MULT}, {VREM,MULT}});  


DW_div_pipe #(
.a_width(DATA_WIDTH), 
.b_width(DATA_WIDTH),
.tc_mode(1),
.rem_mode(1),
.num_stages(4),
.stall_mode(0),
.rst_mode(1),
.op_iso_mode(0)
)U1 (
.clk(clk_i),
.rst_n(resetn_i),
.en(div_en),
.a(b_i),
.b(a_i),
.quotient(div_quotient),
.remainder(div_remainder),
.divide_by_0(div_error) 
);
*/
/*

 VADD      
 VSUB      
 VRSUB     
 VMINU     
 VMIN      
 VMAXU     
 VMAX      
 VAND      
 VOR       
 VXOR      
 VRGATHER  
 VSLIDEUP  
 VSLIDEDOWN
 VADC      
 VMADC     
 VSBC      
 VMSBC     
 VMERGE    
 VMSEQ     
 VMSNE     
 VMSLTU    
 VMSLT     
 VMSLEU    
 VMSLE     
 VMSGTU    
 VMSGT     
 VCOMPRESS 
 VMANDNOT  
 VMAND     
 VMOR      
 VMXOR     
 VMORNOT   
 VMNAND    
 VMNOR     
 VMXNOR    
 VSLL      
 VSRL      
 VSRA      
 VSSRL     
 VSSRA     
 VNSRL     
 VNSRA     
 VNCLIPU   
 VNCLIP    
 VDIVU     
 VDIV      
 VREMU     
 VREM      
 VMULHU    
 VMUL      
 VMULHSU   
 VMULH     
 VMADD     
 VNMSUB    
 VMACC     
 VNMSAC    

*/
always_comb begin : aluLogic

    if(valid_i && mask_en_i) begin

        unique case (opcode_i)
            //Logical and masked
            {VAND, INT},
            {VMSNE_VMAND, MULT}   :   alu_q_o = a_i & b_i;
            {VOR, INT},
            {VMSLTU_VMOR, MULT}    :   alu_q_o = a_i | b_i;
            {VXOR, INT},
            {VMSLT_VMXOR, MULT}   :   alu_q_o = a_i ^ b_i;
            {VMSLE_VMNAND, MULT}  :   alu_q_o = ~(a_i & b_i);
            {VMSEQ_VMANDNOT, MULT}:   alu_q_o = ~a_i & b_i;
            {VMSGTU_VMNOR, MULT}   :   alu_q_o = ~(a_i | b_i);
            {VMSLEU_VMORNOT, MULT} :   alu_q_o = ~a_i | b_i;
            {VMSGT_VMXNOR, MULT}  :   alu_q_o = ~(a_i ^ b_i);


            //Arithmetic
            {VADD_VREDSUM, INT}, 
            {VADC, INT}, 
            {VMADC, INT}   :   begin 
                        alu_q_o = a_i + b_i; //MASK!
            end
            {VSUB_VREDOR, INT},
            {VSBC, INT},
            {VMSBC, INT}   :   begin 
                        alu_q_o = b_i - a_i; //MASK
            end
            {VRSUB_VREDXOR, INT}   :   alu_q_o = a_i - b_i;

            //Shift
            {VSLL_VMUL, INT}    :   alu_q_o = b_i << a_i[SHIFT_B-1:0];
            {VSRL, INT}         :   alu_q_o = b_i >> a_i[SHIFT_B-1:0];
            {VSRA_VMADD, INT}   :   alu_q_o = b_i >>> a_i[SHIFT_B-1:0];
            //VNSRL   :   alu_q_o = (b_i >> a_i[SHIFT_B-1:0]); //Check - but Idk if its needed 
            //VNSRA_VMACC   :   alu_q_o = $signed(b_i >>> a_i[SHIFT_B-1:0]); //Also check, also probably not needed

            //Compare
            {VMIN_VREDMIN, INT},
            {VMINU_VREDMINU, INT},
            {VMAX_VREDMAX, INT},
            {VMAXU_VREDMAXU, INT}   :   begin
                        alu_q_o = (a_less_b ^ (opcode_i == VMAX_VREDMAX || opcode_i == VMAXU_VREDMAXU)) ? b_i : a_i;
            end
            {VMSEQ_VMANDNOT, INT},
            {VMSNE_VMAND, INT}   :   begin
                        alu_q_o = {DATA_WIDTH{a_equal_b ^ (opcode_i == VMSNE_VMAND)}};
                       
            end
            {VMSLT_VMXOR, INT},
            {VMSLTU_VMOR, INT}  :   begin
                        alu_q_o = {DATA_WIDTH{a_less_b}};
            end
            {VMSLE_VMNAND, INT},
            {VMSLEU_VMORNOT, INT},
            {VMSGT_VMXNOR, INT},
            {VMSGTU_VMNOR, INT}  :   begin
                        alu_q_o = {DATA_WIDTH{(a_less_b || a_equal_b) ^ ((opcode_i == VMSGT_VMXNOR) || (opcode_i == VMSGTU_VMNOR))}};
            end      

            //Merge
            {VMERGE_VCOMPRESS, INT} :   alu_q_o = (mask_i) ? a_i : b_i;

            //Multiply
            {VSLL_VMUL, MULT}     :   alu_q_o = mul_result[DATA_WIDTH-1:0];
            {VMULH, MULT}         :   alu_q_o = mul_result[(DATA_WIDTH*2)-1:DATA_WIDTH];
            {VMULHU, MULT}        :   alu_q_o = mul_result[(DATA_WIDTH*2)-1:DATA_WIDTH];
            {VMULHSU, MULT}       :   alu_q_o = mul_result[(DATA_WIDTH*2)-1:DATA_WIDTH];

            {VNSRA_VMACC, MULT}, 
            {VSRA_VMADD, MULT}    :   alu_q_o = mul_result[DATA_WIDTH-1:0] + c_i;   //add B to A*C - change in register, not in ALU
            {VNCLIP_VNMSAC, MULT},
            {VSSRA_VNMSUB, MULT}  :   alu_q_o = -mul_result[DATA_WIDTH-1:0] + c_i;  //subtract B from A*C, change in register, not in ALU

            //Divide
            //Divide will require separate unit, it's too slow
            
            {VDIV, MULT},  
            {VDIVU, MULT}:    alu_q_o = div_quotient;
            {VREMU, MULT},    
            {VREM,MULT}  :    alu_q_o = div_remainder; 
            
            default: alu_q_o = {DATA_WIDTH{1'b0}};
        endcase
    end
    else alu_q_o =  {DATA_WIDTH{1'b0}};

end

endmodule




