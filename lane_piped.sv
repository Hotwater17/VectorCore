/*
###########################################
# Title:  lane_piped.sv
# Author: Michal Gorywoda
# Date:   29.02.2024
###########################################
*/
module lane import vect_pkg::*; #(
    parameter DATA_WIDTH    =   32,
    parameter REG_NUM       =   32,
    parameter VLEN          =   512,
    parameter LANES         =   4,
    parameter ELEMS         =   VLEN/(DATA_WIDTH*LANES),
    parameter PIPE_ST       =   4,

    localparam ELEM_B               =   $clog2(ELEMS),
    localparam ADDR_B               =   $clog2(REG_NUM),

    localparam EX_PIPE_STAGES      =   PIPE_ST,
    localparam EX_PIPE_B           =   $clog2(EX_PIPE_STAGES),
    localparam SBIT_CNT_B          =   $clog2(DATA_WIDTH),

    localparam MASK_LANE_B          =   ELEMS
)(

    input                       clk_i,
    input                       resetn_i,

    //Change to parameter
    
    input                       instr_valid_i,
    input                       instr_req_i,
    arithm_instr_t              instr_i,

    output                      ready_o,
    output                      idle_o,


    //Mask interface
    input   [MASK_LANE_B-1:0]   mask_bits_i,
    output  [DATA_WIDTH-1:0]    mask_bits_o,
    //Scalar interface
    input   [DATA_WIDTH-1:0]    rs1_rdata_i,

    //Writeback set bits output
    output  [SBIT_CNT_B:0]      sbit_cnt_o,

    //Ext interface
    input                       lsu_ready_i,
    input                       sldu_ready_i,
    output                      lsu_req_o,
    output                      sldu_req_o,
    output                      ext_instr_save_o,
    input   [ELEM_B-1:0]        ext_vs_elem_cnt_i,
    input   [ELEM_B-1:0]        ext_vd_elem_cnt_i,
    input                       ext_vd_wr_en_i,
    input   [DATA_WIDTH-1:0]    ext_vd_wdata_i,
    output  [DATA_WIDTH-1:0]    ext_vs1_rdata_o,
    output  [DATA_WIDTH-1:0]    ext_vs2_rdata_o,
    output  [DATA_WIDTH-1:0]    ext_vs3_rdata_o


);

    arithm_instr_t              instr_running;




    logic                       ext_reg_wr_en;
    logic   [DATA_WIDTH-1:0]    ext_vs1_rdata_reg_q;
    logic   [DATA_WIDTH-1:0]    ext_vs2_rdata_reg_q;
    logic   [DATA_WIDTH-1:0]    ext_vs3_rdata_reg_q;
    logic                       ext_ready;
    

    logic [1:0]                 lane_vd_elem_cnt;
    logic [1:0]                 lane_vs_elem_cnt;





  ///////////////////////
  // RD stage logic     
  ///////////////////////
    logic                       rd_pipe_en;
    logic                       rd_pipe_ready;
    logic                       rd_busy;                                                         
    arithm_instr_t              rd_instr_d;
    arithm_instr_t              rd_instr_q;
    logic                       rd_stall;
    logic                       rd_stall_ready;

    logic                       rd_vs1_addr;
    logic                       rd_vs2_addr;
    logic                       rd_vs3_addr;
    logic                       rd_is_c_used;
    logic                       rd_is_op_mul;  
    logic                       rd_is_op_div;      
    logic                       rd_is_op_piped;
    logic                       rd_alu_op_type;
    logic                       rd_is_op_sldu;
    logic                       rd_is_op_lsu;
    logic                       rd_is_op_red;
    logic                       rd_is_ext; 

    logic   [DATA_WIDTH-1:0]    vrf_vs1_rdata;
    logic   [DATA_WIDTH-1:0]    vrf_vs2_rdata;
    logic   [DATA_WIDTH-1:0]    vrf_vs3_rdata;
    logic   [DATA_WIDTH-1:0]    vrf_mask_rdata;
    logic   [ADDR_B-1:0]        vrf_vs1_addr;
    logic   [ADDR_B-1:0]        vrf_vs2_addr;
    logic   [ADDR_B-1:0]        vrf_vs3_addr;
    logic                       vrf_rd_req;

    logic   [ELEM_B-1:0]        vrf_vs_elem_cnt;
    logic                       vrf_rd_op_ready;

    logic   [DATA_WIDTH-1:0]    rs1_rdata_reg_q;
    logic                       rd_is_mask_used;    


  ///////////////////////
  // EX stage logic     
  ///////////////////////

    logic                       ex_pipe_en;
    logic                       ex_pipe_ready;
    arithm_instr_t              ex_instr_d;
    arithm_instr_t              ex_instr_q;
    logic                       ex_alu_ready;
    logic                       ex_busy;

    logic   [DATA_WIDTH-1:0]    alu_a;
    logic   [DATA_WIDTH-1:0]    alu_b;
    logic   [DATA_WIDTH-1:0]    alu_c;
    logic   [DATA_WIDTH-1:0]    alu_result;
    logic                       alu_mask_en;
    logic                       alu_valid;
    

    logic                       ex_alu_op_type;
    logic                       ex_is_op_mul;
    logic                       ex_is_op_div;
    logic                       ex_is_op_alu;
    logic                       ex_is_op_sldu;
    logic                       ex_is_op_lsu;
    logic                       ex_is_op_red;
    logic                       ex_is_op_piped;
    logic                       ex_is_ext;


    typedef enum logic  [1:0]   {EXT_IDLE = 2'h0, EXT_REQ = 2'h1, EXT_WAIT = 2'h2} ext_fsm_t;
    ext_fsm_t                   ext_this_state, ext_next_state;

    
    logic   [EX_PIPE_B-1:0]     ex_pipe_cnt;
    logic   [ELEM_B-1:0]        ex_mask_bits;

    logic   [DATA_WIDTH-1:0]    sldu_result;
    

  ///////////////////////
  // WB stage logic     
  ///////////////////////

    logic                       wb_pipe_en;
    logic                       wb_pipe_ready;
    arithm_instr_t              wb_instr_d;
    arithm_instr_t              wb_instr_q;
    logic                       wb_busy;
    logic   [ELEM_B-1:0]        wb_mask_bits;
    logic                       wb_mask_en;
    logic                       wb_is_op_piped;
    

    logic   [ADDR_B-1:0]        vrf_vd_addr;
    logic                       vrf_wr_req;
    

    logic                       vrf_wr_ready;
    

    logic   [ELEM_B-1:0]        vrf_vd_elem_cnt;


    logic   [DATA_WIDTH-1:0]    vrf_vd_wdata;
    logic                       vrf_vd_wr_en;

               




    
    assign ready_o      =   (rd_pipe_ready && ~rd_stall && ~ex_is_ext) /*|| (rd_stall && vrf_wr_ready && ~ex_is_ext)*/ || (/*~rd_stall &&*/ ex_is_ext && ext_ready);
                                                                        //This condition is confusing the design. Add another stall signal for ex
    assign idle_o       =   wb_pipe_ready; //But something else should be here. Like ALU ready, rd_pipe ready
    assign ext_ready    =   (ex_is_op_lsu && lsu_ready_i) || (ex_is_op_sldu && sldu_ready_i);
    assign ex_is_ext    =   ex_is_op_lsu || ex_is_op_sldu;
    assign lsu_req_o    =   ex_is_op_lsu && (ext_this_state == EXT_REQ);
    assign sldu_req_o   =   ex_is_op_sldu && (ext_this_state == EXT_REQ);
    assign ext_instr_save_o = rd_is_ext && ex_pipe_en;
    //assign lsu_req_o    =   ex_is_op_lsu && ex_busy;
    //assign sldu_req_o   =   ex_is_op_sldu && ex_busy;

    
//########################################################################
  ///////////////////////
  // RD stage     
  ///////////////////////

    always_ff @(posedge clk_i or negedge resetn_i) begin : vs_cnt_FF
        if(~resetn_i)                       lane_vs_elem_cnt <=  '0;
        else begin
            if(rd_busy)  lane_vs_elem_cnt <=  ((lane_vs_elem_cnt < (ELEMS-1)) && ~rd_stall) ? lane_vs_elem_cnt + 1 : lane_vs_elem_cnt;
            else         lane_vs_elem_cnt <=  '0;
        end
    end


  ///////////////////////
  // Address swap          
  ///////////////////////

    always_comb begin : argAddr
        //What is this condition???
        vrf_vs1_addr    =   (rd_instr_q.funct3 inside {OPIVV, OPMVV}) ? rd_instr_q.vs1_rs1_imm : 5'b00000;
        
        if((rd_instr_q.funct6 inside {VSRA_VMADD, VSSRA_VNMSUB}) && (rd_alu_op_type == MULT)) begin
            //Change the order of VS3(C) and VS2(B)
            vrf_vs2_addr = rd_instr_q.vd_rd_vs3; 
            vrf_vs3_addr = rd_instr_q.vs2;
        end else begin
            vrf_vs2_addr = rd_instr_q.vs2;
            vrf_vs3_addr = rd_instr_q.vd_rd_vs3;
        end
    end


    assign  rd_alu_op_type  =   (rd_instr_q.funct3 inside {OPMVV, OPMVX}) ? MULT : INT;
    assign  rd_pipe_ready   =   rd_busy && (lane_vs_elem_cnt == (ELEMS-1)); //Or only lane_vs_elem_cnt == (ELEMS-1)
    assign  vrf_rd_req      =   instr_req_i; //No, this happens to early vs rd_pipe_en. No valid address is present in rd_pipe
    assign  rd_instr_d      =   instr_i;
    assign  rd_pipe_en      =   instr_req_i;
    assign  rd_stall        =   ((~rd_is_op_piped && ex_is_op_piped) || (ex_is_ext && ~ext_ready && (ex_instr_q == rd_instr_q)));
    assign  rd_stall_ready  =  ex_alu_ready;

    assign  rd_is_op_mul    =   ((rd_instr_q.funct6 inside {VSLL_VMUL, VMULH, VMULHU, VMULHSU, VSSRA_VNMSUB
                                , VNSRA_VMACC, VNCLIP_VNMSAC ,VSRA_VMADD}) && (rd_instr_q.funct3 == OPMVV));
    assign  rd_is_op_div    =   ((rd_instr_q.funct6 inside {VDIV, VDIVU, VREMU, VREM}) && (rd_instr_q.funct3 == OPMVV));
    assign  rd_is_op_piped  =   rd_is_op_mul || rd_is_op_div ;
    assign  rd_is_c_used    =   (rd_instr_q.opcode == VSTORE) || (rd_instr_q.funct6 inside {VSRA_VMADD, VSSRA_VNMSUB, VNSRA_VMACC, VNCLIP_VNMSAC} && (rd_instr_q.funct3 == OPMVV));

    assign  rd_is_op_sldu   =   (rd_instr_q.funct6 inside {VSLIDEUP, VSLIDEDOWN}) || 
                            ((rd_instr_q.funct6 == VADC) && ((rd_instr_q.funct3 == OPMVV) || (rd_instr_q.funct3 == OPMVX)) ||
                            rd_is_op_red);
    assign  rd_is_op_lsu    =   (rd_instr_q.opcode inside {VLOAD, VSTORE});
    assign  rd_is_op_red    =   ((rd_instr_q.funct6 inside {VADD_VREDSUM, VREDAND, VSUB_VREDOR, VRSUB_VREDXOR
                            , VMINU_VREDMINU, VMIN_VREDMIN, VMAXU_VREDMAXU, VMAX_VREDMAX}) && (rd_instr_q.funct3 == OPMVV));
    assign  rd_is_ext       =   rd_is_op_lsu || rd_is_op_sldu;

    assign  rd_is_mask_used =   ~rd_instr_q.vm;  

    assign  vrf_vs_elem_cnt = (rd_is_ext) ? ext_vs_elem_cnt_i : lane_vs_elem_cnt;

    always_ff @(posedge clk_i or negedge resetn_i) begin : rd_busy_FF
        if(~resetn_i)               rd_busy <=  1'b0;
        else if(vrf_rd_op_ready)    rd_busy <=  1'b1;
        //else if(rd_pipe_en)     rd_busy <=  1'b1;
        else if(rd_pipe_ready)      rd_busy <=  1'b0;
    end

    always_ff @(posedge clk_i or negedge resetn_i) begin : RD_FF
        if(~resetn_i) begin
            rd_instr_q  <=  '0;
        end
        else if(rd_pipe_en) begin
            rd_instr_q  <=  rd_instr_d;
        end
    end

//########################################################################
  ///////////////////////
  // EX stage     
  ///////////////////////

    assign ex_alu_op_type  =   (ex_instr_q.funct3 inside {OPMVV, OPMVX}) ? MULT : INT;
    assign ex_is_op_mul    =   ((ex_instr_q.funct6 inside {VSLL_VMUL, VMULH, VMULHU, VMULHSU, VSSRA_VNMSUB
                                , VNSRA_VMACC, VNCLIP_VNMSAC ,VSRA_VMADD}) && (ex_instr_q.funct3 == OPMVV));
    assign ex_is_op_div    =   ((ex_instr_q.funct6 inside {VDIV, VDIVU, VREMU, VREM}) && (ex_instr_q.funct3 == OPMVV));
    assign ex_is_op_piped  =   ex_is_op_mul || ex_is_op_div ; // Wait for the completion of currently running instr!;
    assign ex_is_op_alu    =   ~ex_is_op_sldu && ~ex_is_op_lsu;
    assign ex_is_op_sldu   =   (ex_instr_q.funct6 inside {VSLIDEUP, VSLIDEDOWN}) || 
                            ((ex_instr_q.funct6 == VADC) && ((ex_instr_q.funct3 == OPMVV) || (ex_instr_q.funct3 == OPMVX)) ||
                            ex_is_op_red);
    assign ex_is_op_lsu    =   (ex_instr_q.opcode inside {VLOAD, VSTORE});
    assign ex_is_op_red    =   ((ex_instr_q.funct6 inside {VADD_VREDSUM, VREDAND, VSUB_VREDOR, VRSUB_VREDXOR
                            , VMINU_VREDMINU, VMIN_VREDMIN, VMAXU_VREDMAXU, VMAX_VREDMAX}) && (ex_instr_q.funct3 == OPMVV));
    
     

    assign alu_b        =   vrf_vs2_rdata;
    assign alu_c        =   vrf_vs3_rdata;
    assign alu_mask_en  =   ((mask_bits_i[vrf_vs_elem_cnt] && (~ex_instr_q.vm)) || ex_instr_q.vm);
    
    assign alu_valid    =   ex_is_op_alu;

    assign ex_instr_d   =   rd_instr_q;

    assign ex_alu_ready =   (((~ex_is_op_piped && ex_busy) || ((ex_pipe_cnt == 1) && ex_is_op_piped) || (ex_is_ext && ext_ready)) );
    
    assign ex_pipe_en   =   ((vrf_rd_op_ready && ~rd_stall && ~ex_is_ext) || (~ex_is_ext && rd_stall && vrf_wr_ready) || (ex_is_ext && vrf_rd_op_ready/*ext_ready*/));
                                                                                //Why is it like this?

    ///////////////////////
    // Exe pipe counter          
    ///////////////////////

    always_ff @(posedge clk_i or negedge resetn_i) begin : exe_cnt_FF
        if(~resetn_i)                   ex_pipe_cnt <=  '0;
        else begin
            //if(rd_pipe_ready)       ex_pipe_cnt <=  EX_PIPE_STAGES-1;
            if(ex_pipe_en)              ex_pipe_cnt <=  EX_PIPE_STAGES-1;
            else if(ex_is_op_piped)     ex_pipe_cnt <=  (ex_pipe_cnt > 0)  ?   (ex_pipe_cnt - 1) : ex_pipe_cnt;
        end
    end

    ///////////////////////
    // Vs1 selection          
    ///////////////////////

    always_comb begin : argVectScalImm
        unique case (ex_instr_q.funct3)
            OPIVV,OPMVV :   alu_a   =   vrf_vs1_rdata;
            OPIVX,OPMVX :   alu_a   =   rs1_rdata_i;
            OPIVI       :   alu_a   =   {{(DATA_WIDTH-5){1'b0}}, ex_instr_q.vs1_rs1_imm};
            default     :   alu_a   =   vrf_vs1_rdata;
        endcase
    end


    ///////////////////////
    // Ext FSM for request and wait        
    ///////////////////////

    always_comb begin : ext_logic
        case (ext_this_state)
            EXT_IDLE    :   ext_next_state  =   (ex_is_ext && ex_busy)  ?   EXT_REQ :   EXT_IDLE;
            EXT_REQ     :   ext_next_state  =   EXT_WAIT;
            EXT_WAIT    :   ext_next_state  =   ext_ready   ?   EXT_IDLE    :   EXT_WAIT;  
            default     :   ext_next_state  =   EXT_IDLE; 
        endcase
    end

    always_ff @( posedge clk_i or negedge resetn_i ) begin : ext_FSM
        if(~resetn_i) begin
            ext_this_state  <=  EXT_IDLE;
        end
        else begin
            ext_this_state  <=  ext_next_state;
        end
    end



    always_ff @(posedge clk_i or negedge resetn_i) begin : ex_busy_FF
        if(~resetn_i)                           ex_busy <=  1'b0;
        else begin
            if(ex_pipe_en && ~ex_busy)          ex_busy <=  1'b1;
            else if(((ex_alu_ready && ~ex_is_ext) || (ext_ready && ex_is_ext)) && ex_busy)    ex_busy <=  1'b0;       
        end 

    end
    
    always_ff @(posedge clk_i or negedge resetn_i) begin : EX_FF
        if(~resetn_i) begin
            ex_instr_q  <=  '0;
        end
        else if(ex_pipe_en) begin
            ex_instr_q  <=  ex_instr_d;
        end
    end

//########################################################################
  ///////////////////////
  // WB stage     
  ///////////////////////




    assign  vrf_wr_req      =   (ex_alu_ready && ~ex_is_ext) || ext_ready; //Set when ALU is ready - but one cycle later!
    assign  vrf_wr_ready    =   wb_pipe_ready; //Set at the last element
    
    assign  vrf_vd_addr     =   wb_instr_d.vd_rd_vs3;

    assign  wb_instr_d      =   ex_instr_q;
    assign  wb_is_op_piped  =   ex_is_op_mul || ex_is_op_div ;

    //This (wb_pipe_en) is only for one cycle - not 4!
    //Create ALU ready signal. This will also set the wb_busy.
    //wb_busy is reset when wb_pipe_ready is set
    assign  wb_pipe_en      =   ((ex_alu_ready && ex_is_op_alu && ~rd_stall && ~ex_is_ext) || (ex_is_ext && (ext_this_state == EXT_REQ)));
    assign  wb_pipe_ready   =   (wb_busy && (lane_vd_elem_cnt == ELEMS-1)) || ext_ready;

  ///////////////////////
  // Writeback data selection          
  ///////////////////////
    always_comb begin : wbDataSel
        if(ex_is_ext)   vrf_vd_wdata    =   ext_vd_wdata_i; //For slide operations, take wdata from SLIDE unit
        else            vrf_vd_wdata    =   alu_result; 
    end

  ///////////////////////
  // Writeback data bit counting          
  ///////////////////////

    bit_counter #(
        .DATA_WIDTH(DATA_WIDTH),
        .SBIT_CNT_B(SBIT_CNT_B)
    ) VRF_BITS_CNT(
        .clk_i(clk_i),
        .resetn_i(resetn_i),
        .data_i(vrf_vd_wdata),
        .enable_i(vrf_vd_wr_en),
        .sbit_cnt_o(sbit_cnt_o)
    );

    always_comb begin : elemCntSel
        if(ex_is_ext) begin
            //vrf_vs_elem_cnt =ext_vs_elem_cnt_i;
            vrf_vd_elem_cnt =   ext_vd_elem_cnt_i;
            vrf_vd_wr_en    =   ext_vd_wr_en_i;
        end

        else begin
            //vrf_vs_elem_cnt = lane_vs_elem_cnt;
            vrf_vd_elem_cnt =   lane_vd_elem_cnt;
            //vrf_vd_wr_en    = ((mask_bits_i[vrf_vd_elem_cnt]  && (~wb_instr_q.vm)) || wb_instr_q.vm) && wb_busy;
            vrf_vd_wr_en    =   alu_mask_en && (wb_busy || wb_pipe_en);
        end
    end

    always_ff @(posedge clk_i or negedge resetn_i) begin : wb_busy_FF
        if(~resetn_i)           wb_busy <=  1'b0;
        else if((ex_alu_ready) || (ex_is_ext && (ext_this_state == EXT_REQ)))   wb_busy <=  1'b1;
        //else if(wb_pipe_en)     wb_busy <=  1'b1;
        else if(wb_pipe_ready)  wb_busy <=  1'b0; //But what happens if wb_pipe_ready is set but ex_alu_ready is also set?
    end

    always_ff @(posedge clk_i or negedge resetn_i) begin : vd_cnt_FF
        if(~resetn_i)           lane_vd_elem_cnt <=  '0;
        else begin
            if(wb_busy || (wb_pipe_en && ~ex_is_op_piped))   lane_vd_elem_cnt <=  (lane_vd_elem_cnt < (ELEMS-1)) ? lane_vd_elem_cnt + 1 : lane_vd_elem_cnt;
            else                        lane_vd_elem_cnt <=  '0;
        end
    end

    
    always_ff @(posedge clk_i or negedge resetn_i) begin : WB_FF
        if(~resetn_i) begin
            wb_instr_q  <=  '0;
        end
        else if(wb_pipe_en) begin
            wb_instr_q  <=  wb_instr_d;
        end
    end


  ///////////////////////
  // Instruction register          
  ///////////////////////
    
    always_ff @(posedge clk_i or negedge resetn_i) begin : instrFF
        if(!resetn_i)           instr_running   <=  '0;
        else if(instr_req_i)    instr_running   <=  instr_i;
    end


    assign mask_bits_o  =   vrf_mask_rdata;



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
    assign ext_reg_wr_en    =   rd_is_ext && ex_pipe_en;
    assign ext_vs1_rdata_o  =   vrf_vs1_rdata;//ext_vs1_rdata_reg_q;
    assign ext_vs2_rdata_o  =   vrf_vs2_rdata;//ext_vs2_rdata_reg_q;
    assign ext_vs3_rdata_o  =   vrf_vs3_rdata;//ext_vs3_rdata_reg_q;



always_ff @(posedge clk_i or negedge resetn_i) begin : rs1Pipe
    if(!resetn_i) begin
        rs1_rdata_reg_q <= 0;
    end
    else if(instr_req_i) begin
        rs1_rdata_reg_q <= rs1_rdata_i;
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
    .valid_i(alu_valid),
    .mask_e_i(alu_mask_en),
    .a_i(alu_a),
    .b_i(alu_b),
    .c_i(alu_c),
    .ocode_i({ex_instr_q.funct6, ex_alu_op_type}),
    .alu_q_o(alu_result)
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
    .is_c_used_i(rd_is_c_used),
    .rd_op_ready_o(vrf_rd_op_ready),
    .a_rdata_o(vrf_vs1_rdata),
    .b_rdata_o(vrf_vs2_rdata),
    .c_rdata_o(vrf_vs3_rdata),
    .is_mask_used_i(rd_is_mask_used),
    .mask_rdata_o(vrf_mask_rdata)  
    
);



endmodule

