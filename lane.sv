module lane import vect_pkg::*; #(
    parameter DATA_WIDTH    =   32,
    parameter REG_NUM       =   32,
    parameter VLEN          =   512,
    parameter LANES         =   4,
    parameter PIPE_ST       =   4,

    localparam ELEM_B               =   $clog2(LANES),
    localparam ADDR_B               =   $clog2(REG_NUM),

    localparam EXE_PIPE_STAGES      =   PIPE_ST,
    localparam EXE_PIPE_B           =   $clog2(EXE_PIPE_STAGES),

    localparam MASK_LANE_B          =   VLEN/(LANES*DATA_WIDTH)
)(

    input                       clk_i,
    input                       resetn_i,

    input   [ELEM_B-1:0]        lane_number_i,
    
    input                       instr_valid_i,
    input                       instr_req_i,
    arithm_instr_t              instr_i,

    output                      ready_o,


    //Mask interface
    input   [MASK_LANE_B-1:0]   mask_bits_i,
    output  [DATA_WIDTH-1:0]    mask_bits_o,
    //Scalar interface
    input   [DATA_WIDTH-1:0]    rs1_rdata_i,
    output  [DATA_WIDTH-1:0]    rd_wdata_o,
    

    //Ext interface
    input   [ELEM_B-1:0]        ext_vs_elem_cnt_i,
    input   [ELEM_B-1:0]        ext_vd_elem_cnt_i,
    input                       ext_vd_wr_en_i,
    input   [DATA_WIDTH-1:0]    ext_vd_wdata_i,
    output  [DATA_WIDTH-1:0]    ext_vs1_rdata_o,
    output  [DATA_WIDTH-1:0]    ext_vs2_rdata_o,
    output  [DATA_WIDTH-1:0]    ext_vs3_rdata_o


);

    arithm_instr_t              instr_running;


    logic   [DATA_WIDTH-1:0]    alu_a;
    logic   [DATA_WIDTH-1:0]    alu_b;
    logic   [DATA_WIDTH-1:0]    alu_c;
    logic   [DATA_WIDTH-1:0]    alu_result;
    logic                       alu_mask_en;
    logic                       alu_valid;
    logic                       alu_op_type;

    logic                       is_op_mul;
    logic                       is_op_div;
    logic                       is_op_alu;
    logic                       is_op_sldu;
    logic                       is_op_lsu;
    logic                       is_op_red;
    logic                       is_op_piped;
    logic   [DATA_WIDTH-1:0]    sldu_result;
    logic   [EXE_PIPE_B-1:0]    exe_pipe_cnt;

    logic                       mul_ready;
    logic                       alu_ready;

    logic   [ADDR_B-1:0]        vrf_vs1_addr;
    logic   [ADDR_B-1:0]        vrf_vs2_addr;
    logic   [ADDR_B-1:0]        vrf_vs3_addr;
    logic   [ADDR_B-1:0]        vrf_vd_addr;
    
    logic   [ELEM_B-1:0]        vrf_vs_elem_cnt;
    logic   [ELEM_B-1:0]        vrf_vd_elem_cnt;

    logic   [DATA_WIDTH-1:0]    vrf_vs1_rdata;
    logic   [DATA_WIDTH-1:0]    vrf_vs2_rdata;
    logic   [DATA_WIDTH-1:0]    vrf_vs3_rdata;
    logic   [DATA_WIDTH-1:0]    vrf_mask_rdata;
    logic   [DATA_WIDTH-1:0]    vrf_vd_wdata;
    logic                       vrf_vd_wr_en;


    logic                       ext_reg_wr_en;
    logic   [DATA_WIDTH-1:0]    ext_vs1_rdata_reg_q;
    logic   [DATA_WIDTH-1:0]    ext_vs2_rdata_reg_q;
    logic   [DATA_WIDTH-1:0]    ext_vs3_rdata_reg_q;

    logic                       vrf_wr_req;
    logic                       vrf_rd_req;
    logic                       is_c_used;
    logic                       vrf_wr_ready;
    logic                       vrf_rd_op_ready;
    

    logic   [DATA_WIDTH-1:0]    rs1_rdata_reg_q;

    logic   [DATA_WIDTH-1:0]    mask_wb;
    logic                       is_mask_used;
    

    logic [1:0]                 lane_vd_elem_cnt;
    logic [1:0]                 lane_vs_elem_cnt;


    enum logic [1:0] {ST_IDLE, ST_READ_ARG, ST_EXE, ST_WB} lane_this_state, lane_next_state;

  ///////////////////////
  // Instruction register          
  ///////////////////////
    
    always_ff @(posedge clk_i or negedge resetn_i) begin : instrFF
        if(!resetn_i)           instr_running   <=  '0;
        else if(instr_req_i)    instr_running   <=  instr_i;
    end


    assign mask_bits_o  =   vrf_mask_rdata;

    assign ready_o      =   ((lane_next_state == ST_IDLE) && (lane_this_state == ST_WB));

  ///////////////////////
  // Control signals          
  ///////////////////////
    
    assign is_op_mul    =   ((instr_running.funct6 inside {VSLL_VMUL, VMULH, VMULHU, VMULHSU}) && (instr_running.funct3 == OPMVV));
    assign is_op_div    =   ((instr_running.funct6 inside {VDIV, VDIVU, VREMU, VREM}) && (instr_running.funct3 == OPMVV));
    assign is_op_piped  =   is_op_mul || is_op_div ; // Wait for the completion of currently running instr!;
    assign is_op_alu    =   ~is_op_sldu && ~is_op_lsu;
    assign is_op_sldu   =   (instr_running.funct6 inside {VSLIDEUP, VSLIDEDOWN}) || 
                            ((instr_running.funct6 == VADC) && ((instr_running.funct3 == OPMVV) || (instr_running.funct3 == OPMVX)) ||
                            is_op_red);
    assign is_op_lsu    =   (instr_running.opcode inside {VLOAD, VSTORE});
    assign is_op_red    =   ((instr_running.funct6 inside {VADD_VREDSUM, VREDAND, VSUB_VREDOR, VRSUB_VREDXOR
                            , VMINU_VREDMINU, VMIN_VREDMIN, VMAXU_VREDMAXU, VMAX_VREDMAX}) && (instr_running.funct3 == OPMVV));
    assign is_c_used    =   (instr_running.funct6 inside {VSRA_VMADD, VSSRA_VNMSUB, VNSRA_VMACC, VNCLIP_VNMSAC} && (instr_running.funct3 == OPMVV));

    assign is_mask_used =   ~instr_running.vm;   

    assign alu_b        =   vrf_vs2_rdata;
    assign alu_c        =   vrf_vs3_rdata;
    assign alu_mask_en  =   ((mask_bits_i[vrf_vd_elem_cnt] && (~instr_running.vm)) || instr_running.vm);
    
    assign alu_valid    =   is_op_alu;
    //assign alu_valid    =   (lane_this_state == ST_EXE) && is_op_alu;

  ///////////////////////
  // Slide unit selection          
  ///////////////////////
 
  ///////////////////////
  // External registers          
  ///////////////////////

always_ff @(posedge clk_i or negedge resetn_i) begin : extArgPipe
    if(!resetn_i) begin
        ext_vs1_rdata_reg_q <= 0;
        ext_vs2_rdata_reg_q <= 0;
        ext_vs3_rdata_reg_q <= 0;
    end
    else if(ext_reg_wr_en) begin
        ext_vs1_rdata_reg_q <= vrf_vs1_rdata;
        ext_vs2_rdata_reg_q <= vrf_vs2_rdata;
        ext_vs3_rdata_reg_q <= vrf_vs3_rdata;
    end
end
    assign ext_reg_wr_en    =   is_op_lsu || is_op_sldu;
    assign ext_vs1_rdata_o  =   ext_vs1_rdata_reg_q;
    assign ext_vs2_rdata_o  =   ext_vs2_rdata_reg_q;
    assign ext_vs3_rdata_o  =   ext_vs3_rdata_reg_q;



always_ff @(posedge clk_i or negedge resetn_i) begin : rs1Pipe
    if(!resetn_i) begin
        rs1_rdata_reg_q <= 0;
    end
    else if(lane_this_state == ST_READ_ARG) begin
        rs1_rdata_reg_q <= rs1_rdata_i;
    end
end
    assign vrf_reg_wr_en    =   (lane_this_state == ST_WB);
    //assign vrf_rd_req       =   (lane_this_state == ST_READ_ARG);

    assign vrf_wr_req       =   ((lane_this_state == ST_EXE) && (lane_next_state == ST_WB));
    assign vrf_rd_req       =   instr_req_i;
    assign vrf_wr_ready     =   ((lane_this_state == ST_WB) && (lane_next_state == ST_IDLE));

  ///////////////////////
  // Address swap          
  ///////////////////////

always_comb begin : argAddr

    vrf_vs1_addr    =   (instr_running.funct3 inside {OPIVV, OPMVV}) ? instr_running.vs1_rs1_imm : 5'b00000;
    vrf_vd_addr     =   instr_running.vd_rd_vs3;
    if((instr_running.funct6 inside {VSRA_VMADD, VSSRA_VNMSUB}) && (alu_op_type == MULT)) begin
        //Change the order of VS3(C) and VS2(B)
        vrf_vs2_addr = instr_running.vd_rd_vs3; 
        vrf_vs3_addr = instr_running.vs2;
    end else begin
        vrf_vs2_addr = instr_running.vs2;
        vrf_vs3_addr = instr_running.vd_rd_vs3;
    end
end

  ///////////////////////
  // Vs1 selection          
  ///////////////////////

always_comb begin : argVectScalImm
    unique case (instr_running.funct3)
        OPIVV,OPMVV :   alu_a   =   vrf_vs1_rdata;
        OPIVX,OPMVX :   alu_a   =   rs1_rdata_i;
        OPIVI       :   alu_a   =   {{(DATA_WIDTH-5){1'b0}}, instr_running.vs1_rs1_imm};
        default     :   alu_a   =   vrf_vs1_rdata;
    endcase
end

  ///////////////////////
  // Operation type selection       
  ///////////////////////
always_comb begin : opTypeSel
    alu_op_type = (instr_running.funct3 inside {OPMVV, OPMVX}) ? MULT : INT;
end




  ///////////////////////
  // Writeback data selection          
  ///////////////////////
always_comb begin : wbDataSel
    if(is_op_sldu || is_op_lsu) vrf_vd_wdata =   ext_vd_wdata_i; //For slide operations, take wdata from SLIDE unit
    else                        vrf_vd_wdata =   alu_result; 
end

always_comb begin : elemCntSel
    if(is_op_sldu || is_op_lsu) begin
        vrf_vs_elem_cnt = ext_vs_elem_cnt_i;
        vrf_vd_elem_cnt = ext_vd_elem_cnt_i;
        vrf_vd_wr_en    = ext_vd_wr_en_i;
    end

    else begin
        vrf_vs_elem_cnt = lane_vs_elem_cnt;
        vrf_vd_elem_cnt = lane_vd_elem_cnt;
        vrf_vd_wr_en    = (alu_mask_en && (lane_this_state == ST_WB));
    end
end

  ///////////////////////
  // ALU          
  ///////////////////////

ALU #(
    .DATA_WIDTH(DATA_WIDTH),
    .PIPE_ST(PIPE_ST)
) valu(
    .clk_i(clk_i),
    .resetn_i(resetn_i),
    .valid_i(alu_valid && instr_valid_decoded),
    .mask_i(mask_bits_i[vrf_vd_elem_cnt]),
    .mask_en_i(alu_mask_en),
    .a_i(alu_a),
    .b_i(alu_b),
    .c_i(alu_c),
    .opcode_i({instr_running.funct6, alu_op_type}),
    .alu_q_o(alu_result),
    .alu_ready_o(alu_ready),
    .mul_ready_o(mul_ready)
);



  ///////////////////////
  // Register file          
  ///////////////////////
VRF_latch RF(

    .clk_i(clk_i),
    .resetn_i(resetn_i),
    .a_addr_i(vrf_vs1_addr),
    .b_addr_i(vrf_vs2_addr),
    .c_addr_i(vrf_vs3_addr),
    .wr_addr_i(vrf_vd_addr),     
    .rd_elem_cnt_i(vrf_vs_elem_cnt),
    .wr_elem_cnt_i(vrf_vd_elem_cnt),
    .wr_req_i(vrf_wr_req),
    .wr_en_i(vrf_vd_wr_en),
    .wr_ready_i(vrf_wr_ready),
    .wdata_i(vrf_vd_wdata),
    .rd_req_i(vrf_rd_req),
    .is_c_used_i(is_c_used),
    .rd_op_ready_o(vrf_rd_op_ready),
    .a_rdata_o(vrf_vs1_rdata),
    .b_rdata_o(vrf_vs2_rdata),
    .c_rdata_o(vrf_vs3_rdata),
    .is_mask_used_i(is_mask_used),
    .mask_rdata_o(vrf_mask_rdata)  
    
);



  ///////////////////////
  // State FSM          
  ///////////////////////



always_ff @(posedge clk_i or negedge resetn_i) begin : laneStateFF
    if(!resetn_i)   lane_this_state <=  ST_IDLE;
    else            lane_this_state <=  lane_next_state;
end

always_comb begin : laneStateLogic
    unique case(lane_this_state) 
        ST_IDLE     :   lane_next_state =   instr_req_i                     ?   ST_READ_ARG :   ST_IDLE;
        ST_READ_ARG :   lane_next_state =   vrf_rd_op_ready                 ?   ST_EXE      :   ST_READ_ARG;
        ST_EXE      :   lane_next_state =   (exe_pipe_cnt == 0)             ?   ST_WB       :   ST_EXE;
        ST_WB       :   lane_next_state =   (lane_vd_elem_cnt == LANES-1)   ?   ST_IDLE     :   ST_WB;
        default     :   lane_next_state =   ST_IDLE;

    endcase
end
    //ST_READ_ARG: goto exe when rd_ready is set
    //ST_EXE: goto wb when pipeline cnt is 0 
    //ST_WB: goto idle when all elements from write are ready(set wr_ready also)



  ///////////////////////
  // Element counter          
  ///////////////////////

  

always_ff @(posedge clk_i or negedge resetn_i) begin : elemCntFF
    if(!resetn_i) begin 
        lane_vs_elem_cnt    <=  0;
        lane_vd_elem_cnt    <=  0;
        exe_pipe_cnt        <=  0;
    end
    else begin
        unique case(lane_this_state)
            ST_IDLE      :   begin 
                lane_vs_elem_cnt    <=  0;
                lane_vd_elem_cnt    <=  0;
                //Wait one more if 
                exe_pipe_cnt        <=  0; 
                //2 cycles for argument readocalplocalparam EXE_PIPE_STAGES = 3
            end
            ST_READ_ARG  :   begin 
                lane_vs_elem_cnt    <=  0;
                lane_vd_elem_cnt    <=  lane_vd_elem_cnt;
                //Here - depending on the operation - either normal ALU or pipelined mul/div.
                exe_pipe_cnt        <=  is_op_piped ?   EXE_PIPE_STAGES-1   :   0; 
            end
            ST_EXE       :   begin 
                lane_vs_elem_cnt    <=  lane_vs_elem_cnt + 1;
                lane_vd_elem_cnt    <=  0;
                exe_pipe_cnt        <=  (exe_pipe_cnt > 0) ? exe_pipe_cnt-1 : exe_pipe_cnt; 
            end
            ST_WB        :   begin
                //Maybe here?
                lane_vs_elem_cnt    <=  lane_vs_elem_cnt + 1;
                lane_vd_elem_cnt    <=  lane_vd_elem_cnt + 1;
                exe_pipe_cnt        <=  exe_pipe_cnt;               
            end
            default         :   begin
                lane_vs_elem_cnt    <=  0;
                lane_vd_elem_cnt    <=  0;
                exe_pipe_cnt        <=  0; 
            end 
        endcase
    end
end

endmodule

