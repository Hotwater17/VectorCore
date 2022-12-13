module VLSU import vect_pkg::*; #(
 parameter DATA_WIDTH   =   32,
 parameter LANES        =   4,
 parameter VLEN         =   512,
 parameter ELEMS        =   VLEN/(DATA_WIDTH*LANES),
 
 localparam ELEM_B = $clog2(ELEMS),
 localparam FU_WIDTH = DATA_WIDTH * LANES,
 localparam VECTOR_BURST_SIZE = FU_WIDTH/DATA_WIDTH
)(
    //Common signals
    input                           clk_i,
    input                           resetn_i,
    input                           req_i,
    input       [DATA_WIDTH-1:0]    instr_i,
    output                          ready_o,

    //VRF element counter
    output      [ELEM_B-1:0]        vrf_vd_elem_cnt_o   [0:LANES-1],
    output      [ELEM_B-1:0]        vrf_vs_elem_cnt_o   [0:LANES-1],
    output reg                      vrf_vd_wr_en_o      [0:LANES-1],

    //VRF data lines
    input       [DATA_WIDTH-1:0]    rf_rs1_rdata_i,
    input       [DATA_WIDTH-1:0]    rf_rs2_rdata_i,
    input       [DATA_WIDTH-1:0]    vrf_vs2_rdata_i     [0:LANES-1],
    input       [DATA_WIDTH-1:0]    vrf_vs3_rdata_i     [0:LANES-1],
    input       [DATA_WIDTH-1:0]    vrf_mask_bit_i,
    output  reg [DATA_WIDTH-1:0]    vrf_vd_wdata_o      [0:LANES-1],

    output  reg [DATA_WIDTH-1:0]    haddr_o, 
    input       [DATA_WIDTH-1:0]    hrdata_i,
    output  reg [DATA_WIDTH-1:0]    hwdata_o,
    output  reg [2:0]               hsize_o,
    output  reg                     hwrite_o,
    input                           hready_i, 
    input       [1:0]               hresp_i 
    
);

logic   [DATA_WIDTH-1:0]    ap_addr     [0:LANES-1];
logic   [DATA_WIDTH-1:0]    rdata_reg_q [0:LANES-1];
logic                       rdata_reg_wr;


mem_instr_t instr_q;
logic       instr_pending;
logic       instr_valid;
logic       instr_rn_w;
logic       instr_is_masked;
assign instr_valid = (instr_q.opcode inside {VSTORE, VLOAD}); 
assign instr_rn_w = (instr_q.opcode == VSTORE);
assign instr_is_masked = !(instr_q.vm);



/*
    State machine
*/
typedef enum logic  [1:0] {LSU_IDLE = 2'h0, LSU_READ = 2'h1, LSU_STORE = 2'h2, LSU_LOAD = 2'h3} lsu_fsm_t;
lsu_fsm_t lsu_this_state, lsu_next_state;
logic [ELEM_B-1:0] lsu_vs_elem_this_cnt, lsu_vs_elem_next_cnt;
logic [ELEM_B-1:0] lsu_vd_elem_this_cnt, lsu_vd_elem_next_cnt;
logic [ELEM_B-1:0] lsu_lane_this_cnt, lsu_lane_next_cnt;
logic   new_addr_calc;
logic   is_base_addr;
logic   element_masked;
logic   mem_ready;
logic   is_first_elem;
//assign  new_addr_calc = (lsu_lane_this_cnt == LANES-1); 
assign  new_addr_calc = (lsu_this_state == LSU_READ); 
assign  is_base_addr = (lsu_vd_elem_this_cnt == 0) && ((lsu_this_state == LSU_IDLE) || (lsu_this_state == LSU_READ));
assign  ready_o = (mem_ready || element_masked) && (lsu_lane_this_cnt == LANES-1) && (lsu_vd_elem_this_cnt == ELEMS-1);
        //Should I just set ready when Idle?
//assign ready_o = lsu_next_state == LSU_IDLE;

always_ff @(posedge clk_i or negedge resetn_i) begin : lsuFSM
    if(~resetn_i) begin
        lsu_this_state <= LSU_IDLE;
        lsu_vs_elem_this_cnt <= 0;
        lsu_vd_elem_this_cnt <= 0;
        lsu_lane_this_cnt <= 0;
        is_first_elem <= 0;
    end
    else begin
        lsu_this_state <= lsu_next_state;
        lsu_vs_elem_this_cnt <= lsu_vs_elem_next_cnt;
        lsu_vd_elem_this_cnt <= lsu_vd_elem_next_cnt;
        lsu_lane_this_cnt   <= lsu_lane_next_cnt;
        is_first_elem       <= new_addr_calc;
    end
end

always_comb begin : lsuStateLogic
    unique case(lsu_this_state)
        LSU_IDLE    :   lsu_next_state = (instr_pending && instr_valid) ? LSU_READ : LSU_IDLE;
        LSU_READ    :   lsu_next_state = instr_rn_w ? LSU_STORE : LSU_LOAD;
        LSU_STORE   :   lsu_next_state = (mem_ready || element_masked) && (lsu_lane_this_cnt == LANES-1) 
                                        ? ((lsu_vd_elem_this_cnt == ELEMS-1) ? LSU_IDLE : LSU_READ) : LSU_STORE; 
        LSU_LOAD    :   lsu_next_state = (mem_ready || element_masked) && (lsu_lane_this_cnt == LANES-1) 
                                        ? ((lsu_vd_elem_this_cnt == ELEMS-1) ? LSU_IDLE : LSU_READ) : LSU_LOAD;
        default     :   lsu_next_state = LSU_IDLE;

    endcase
end

always_comb begin : lsuVsCntLogic
    unique case(lsu_this_state)
        //###### Count from 0
        LSU_IDLE    : lsu_vs_elem_next_cnt = 0;
        LSU_READ    : lsu_vs_elem_next_cnt = lsu_vs_elem_this_cnt; //But should I read new address already?
        LSU_STORE   : lsu_vs_elem_next_cnt = (mem_ready || element_masked) && (lsu_lane_this_cnt == LANES-1)
                                            ? (lsu_vs_elem_this_cnt + 1) : lsu_vs_elem_this_cnt;
        LSU_LOAD    : lsu_vs_elem_next_cnt = (mem_ready || element_masked) && (lsu_lane_this_cnt == LANES-1) 
                                            ? (lsu_vs_elem_this_cnt + 1) : lsu_vs_elem_this_cnt;
        default     : lsu_vs_elem_next_cnt = 0;
    endcase
end

always_comb begin : lsuVdCntLogic
    unique case(lsu_this_state)
        //###### Count from 0
        LSU_IDLE    : lsu_vd_elem_next_cnt = 0;
        LSU_READ    : lsu_vd_elem_next_cnt = lsu_vd_elem_this_cnt;
        LSU_STORE   : lsu_vd_elem_next_cnt = (mem_ready || element_masked) && (lsu_lane_this_cnt == LANES-1) 
                                            ? (lsu_vd_elem_this_cnt + 1) : lsu_vd_elem_this_cnt;
        LSU_LOAD    : lsu_vd_elem_next_cnt = (mem_ready || element_masked) && (lsu_lane_this_cnt == LANES-1)
                                            ? (lsu_vd_elem_this_cnt + 1) : lsu_vd_elem_this_cnt;
        default     : lsu_vd_elem_next_cnt = 0;
    endcase
end

always_comb begin : lsuLaneCntLogic
    unique case(lsu_this_state)
        //###### Count from 0
        LSU_IDLE    : lsu_lane_next_cnt = 0;
        LSU_READ    : lsu_lane_next_cnt = 0; //Also take care of masking
        LSU_STORE   : lsu_lane_next_cnt = ((!is_first_elem && mem_ready) || element_masked) 
                                        ? (lsu_lane_this_cnt + 1) : lsu_lane_this_cnt;
        LSU_LOAD    : lsu_lane_next_cnt = ((!is_first_elem && mem_ready) || element_masked)
                                        ? (lsu_lane_this_cnt + 1) : lsu_lane_this_cnt;
        default     : lsu_lane_next_cnt = 0;
    endcase
end

genvar iElem;
generate
    for(iElem = 0; iElem < LANES; iElem = iElem + 1) begin
        assign vrf_vd_elem_cnt_o[iElem] = lsu_vd_elem_this_cnt;
        assign vrf_vs_elem_cnt_o[iElem] = lsu_vs_elem_this_cnt;
    end
endgenerate

/*
    Instruction decoder
*/

always_ff @(posedge clk_i or negedge resetn_i) begin : instrFF
    if(!resetn_i) begin 
        instr_q <= 0;
        instr_pending <= 1'b0;
    end
    else if(req_i) begin 
        instr_q <= instr_i;
        //Set instr pending flag if there was an instruction request
        instr_pending <= 1'b1;
    end
    else if(lsu_this_state == LSU_READ) instr_pending <= 1'b0; 
end

always_comb begin : decoder
    //if()
/*
    if(instr_q.funct6 inside {VSLIDEUP, VSLIDEDOWN, VSLIDEDOWN}) begin
        if(instr_q.funct6 == VSLIDEUP) operation = OP_SLIDE_UP;
        else if(instr_q.funct6 == VSLIDEDOWN) operation =  OP_SLIDE_DN;
        else operation = OP_SCALAR_MOVE;

        unique case(instr_q.funct3)
            //OPIVV   :   offset_type = OFF_VECTOR; //VECTOR CURRENTLY NOT SUPPORTED
            OPIVV   :   offset_type = OFF_UNIT;
            OPIVI   :   offset_type = OFF_IMM;
            OPIVX   :   offset_type = OFF_SCALAR;
            OPMVV,
            OPMVX   :   offset_type = OFF_UNIT;
            default :   offset_type = OFF_UNIT;
        endcase
    end
    else begin
        operation = OP_INVALID;
        offset_type = OFF_UNIT;
    end
    */
end


/*
    Masking 
*/
    //???
    //Skip this element
assign element_masked = (instr_is_masked && ~vrf_mask_bit_i[{lsu_vd_elem_this_cnt, lsu_lane_this_cnt}]);
 

//If currently selected lane is masked off, skip it - increment to next lane immediately

/*
    AHB master 
*/
    





    assign mem_ready    =   hready_i;


    always_ff @(posedge clk_i or negedge resetn_i) begin : rdataWrFF
        if(!resetn_i)   rdata_reg_wr    <=  '0;
        else            rdata_reg_wr    <=  ((mem_ready || element_masked) && (lsu_lane_this_cnt == LANES-1) && !instr_rn_w);        
    end
    
    genvar iDemux;
    generate

        for(iDemux = 0; iDemux < LANES; iDemux = iDemux + 1) begin
            always_comb begin : vrfDemux
                vrf_vd_wdata_o[iDemux] = (iDemux == lsu_lane_this_cnt) ? hrdata_i : '0;
                //vrf_vd_wdata_o[iDemux] = rdata_reg_q[iDemux];
                vrf_vd_wr_en_o[iDemux] = ((iDemux == lsu_lane_this_cnt) && !instr_rn_w 
                                        && (lsu_this_state == LSU_LOAD) && !element_masked && mem_ready);
                //vrf_vd_wr_en_o[iDemux] = rdata_reg_wr /*&& ((vrf_mask_bit_i[{lsu_vd_elem_this_cnt, iDemux}]) || !instr_is_masked)*/;
            end



            always_ff @(posedge clk_i or negedge resetn_i) begin : rdataFF
                if(!resetn_i) begin
                    rdata_reg_q[iDemux]             <=  '0;
                end
                else if((iDemux == lsu_lane_this_cnt) && !instr_rn_w && (lsu_this_state == LSU_LOAD) && !element_masked && mem_ready) begin
                    rdata_reg_q[iDemux]  <=  hrdata_i;
                end
            end
        end

    


    endgenerate


    

    typedef enum logic [1:0] {AHB_IDLE, AHB_READ, AHB_WRITE} ahb_fsm_t;
    ahb_fsm_t ahb_this_state, ahb_next_state;

    logic  ahb_req;
    assign ahb_req = (!element_masked) && (!is_first_elem) && (ahb_this_state == AHB_IDLE) && 
                    ((lsu_this_state == LSU_STORE) || (lsu_this_state == LSU_LOAD)); 

    always_comb begin : ahbLogic
        unique case(ahb_this_state)
            AHB_IDLE        :   begin
                ahb_next_state = ahb_req ? (instr_rn_w ? AHB_WRITE : AHB_READ) : AHB_IDLE;
                //haddr_o = (ahb_next_state != AHB_IDLE) ? ap_addr[lsu_lane_this_cnt] : '0; 
                haddr_o = ahb_req ? ap_addr[lsu_lane_this_cnt] : 32'hFFFFFFFF; 
                hwdata_o = '0;
                hsize_o = 3'b011;
                hwrite_o = (ahb_next_state != AHB_IDLE) ? instr_rn_w : '0;   
            end
            AHB_READ    :   begin
                ahb_next_state = mem_ready ? AHB_IDLE : AHB_READ;
                haddr_o = ap_addr[lsu_lane_this_cnt];
                hwdata_o = '0;
                hsize_o = 3'b011;
                hwrite_o = instr_rn_w;                
            end
            AHB_WRITE    :   begin
                ahb_next_state = mem_ready ? AHB_IDLE : AHB_WRITE;
                haddr_o = ap_addr[lsu_lane_this_cnt];
                hwdata_o = vrf_vs3_rdata_i[lsu_lane_this_cnt];
                hsize_o = 3'b011;
                hwrite_o = instr_rn_w;             
            end
            default         :   begin
                ahb_next_state = AHB_IDLE;
                haddr_o = '0;
                hwdata_o = '0;
                hsize_o = 3'b011;
                hwrite_o = '0;
            end

        endcase
    end

    always_ff @(posedge clk_i or negedge resetn_i) begin : ahbFSM
        if(!resetn_i) begin
            ahb_this_state <= AHB_IDLE;
        end
        else begin
            ahb_this_state <= ahb_next_state;
        end
    end
/*
    Address calculator
*/

genvar iAP;
generate
    for(iAP = 0; iAP < LANES; iAP = iAP + 1) begin
        Address_Calculator #(
            .DATA_WIDTH(DATA_WIDTH),
            .LANES(LANES),
            .ELEMS(ELEMS)
        ) AP(
            .clk_i(clk_i),
            .resetn_i(resetn_i),
            .rs1_base_i(rf_rs1_rdata_i),
            .rs2_stride_i(rf_rs2_rdata_i),
            .vs2_offset_i(vrf_vs2_rdata_i[iAP]),
            .lane_offset_i(iAP[ELEM_B-1:0]),
            .elem_cnt_i(lsu_vd_elem_this_cnt),
            .offset_sel_i(instr_q.mop),//from instruction
            .base_sel_i(is_base_addr), //is first cycle 
            .adder_reg_wen_i(is_first_elem), //is memory ready for next request
            .addr_o(ap_addr[iAP]) //output
        );

    end
endgenerate


endmodule


module Address_Calculator import vect_pkg::*; #(
    parameter DATA_WIDTH = 32,
    parameter LANES = 4,
    parameter ELEMS = 4,
    parameter ELEM_B = $clog2(ELEMS),
    parameter FU_WIDTH = DATA_WIDTH * LANES,
    parameter VECTOR_BURST_SIZE = FU_WIDTH/DATA_WIDTH
)(

    input                   clk_i,
    input                   resetn_i,
    //ADDRESS CALCULATION UNIT
    input [DATA_WIDTH-1:0]  rs1_base_i,
    input [DATA_WIDTH-1:0]  rs2_stride_i,
    input [DATA_WIDTH-1:0]  vs2_offset_i,
    input [ELEM_B-1:0]      lane_offset_i,
    input [ELEM_B-1:0]      elem_cnt_i,    
    mop_e                   offset_sel_i,
    input                   base_sel_i,
    input                   adder_reg_wen_i,

    output [DATA_WIDTH-1:0] addr_o
);



logic [DATA_WIDTH-1:0]  offset_mux;
logic [DATA_WIDTH-1:0]  base_mux;
logic [DATA_WIDTH-1:0]  adder_sum;

logic [DATA_WIDTH-1:0]  adder_reg_q;

assign addr_o = adder_reg_q;
//assign addr_o = adder_sum;
always_comb begin : calculation_adder

    /*
    base_mux = base_sel_i ? (rs1_base_i + lane_offset_i) : adder_reg_q;

    case (offset_sel_i)
        OFF_UNIT : offset_mux = 1 * LANES; 
        OFF_INDEX_UNORD : offset_mux = vs2_offset_i;
        OFF_STRIDE : offset_mux = rs2_stride_i * LANES;
        OFF_INDEX_ORD : offset_mux = vs2_offset_i;
        default: offset_mux = 1 * LANES;
    endcase
*/

    //base_mux = base_sel_i ? (rs1_base_i + lane_offset_i) : adder_reg_q;

    case (offset_sel_i)
        OFF_UNIT : offset_mux = (lane_offset_i + (elem_cnt_i*LANES)) * 4; //4, because memory is word addressed 
        OFF_INDEX_UNORD : offset_mux = vs2_offset_i;
        OFF_STRIDE : offset_mux = (lane_offset_i + (elem_cnt_i*LANES)) * rs2_stride_i;
        OFF_INDEX_ORD : offset_mux = vs2_offset_i;
        default: offset_mux = lane_offset_i + (elem_cnt_i*LANES); 
    endcase
    adder_sum = rs1_base_i + offset_mux;
end

always_ff @(posedge clk_i or negedge resetn_i) begin : adder_reg
    if(~resetn_i) adder_reg_q <= 0;
    //else if(adder_reg_wen_i) adder_reg_q <= base_sel_i ? base_mux : adder_sum; 
    else if(adder_reg_wen_i) adder_reg_q <= adder_sum; 
end

endmodule
