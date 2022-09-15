module Vector_Core import vect_pkg::*; #(
    parameter DATA_WIDTH = 32,
    parameter REG_NUM = 32,
    parameter LANES = 4,
    parameter VLEN = 512,

    localparam FU_WIDTH = LANES*DATA_WIDTH,
    localparam ADDR_B = $clog2(REG_NUM),
    localparam ELEM_B = $clog2(LANES),
    localparam VECTOR_BURST_SIZE = FU_WIDTH/DATA_WIDTH
)(
    input                           clk_i,
    input                           resetn_i,
    input   [DATA_WIDTH-1:0]        vinstr_i,
    input   [DATA_WIDTH-1:0]        rs1_i,
    input   [DATA_WIDTH-1:0]        rs2_i,
    input                           vreq_i,
    output  reg                     vready_o,
    output  [DATA_WIDTH-1:0]        rd_o,
    output                          rd_wr_en_o,

    output  reg [DATA_WIDTH-1:0]    haddr_o, 
    input       [DATA_WIDTH-1:0]    hrdata_i,
    output  reg [DATA_WIDTH-1:0]    hwdata_o,
    output  reg [2:0]               hsize_o,
    output  reg                     hwrite_o,
    input                           hready_i, 
    input       [1:0]               hresp_i 


);

    logic                       clk_lane                [0:LANES-1];
    logic                       resetn_lane             [0:LANES-1];

    logic   [ELEM_B-1:0]        lsu_vs_elem_sel_lane    [0:LANES-1];
    logic   [ELEM_B-1:0]        lsu_vd_elem_sel_lane    [0:LANES-1];
    logic   [DATA_WIDTH-1:0]    lsu_vs2_rdata_lane      [0:LANES-1];
    logic   [DATA_WIDTH-1:0]    lsu_vs3_rdata_lane      [0:LANES-1];
    logic   [DATA_WIDTH-1:0]    lsu_mask_rdata_lane     [0:LANES-1];
    logic   [DATA_WIDTH-1:0]    lsu_vd_wdata_lane       [0:LANES-1];
    logic                       lsu_vd_wr_en_lane       [0:LANES-1];
    logic                       lsu_ready;

    logic   [VECTOR_BURST_SIZE-1:0] mask_bits_i         [0:LANES-1];
    logic   [DATA_WIDTH-1:0]    mask_bits_o             [0:LANES-1];



    //Slide unit signals in lanes
    logic   [DATA_WIDTH-1:0]    sldu_vs1_rdata_lane     [0:LANES-1];
    logic   [DATA_WIDTH-1:0]    sldu_vd_wdata_lane      [0:LANES-1];
    logic                       sldu_vd_wr_en_lane      [0:LANES-1];
    logic   [ELEM_B-1:0]        sldu_vs1_elem_sel_lane  [0:LANES-1];
    logic   [ELEM_B-1:0]        sldu_vd_elem_sel_lane   [0:LANES-1];

    logic                       sldu_ready;
    logic   [DATA_WIDTH-1:0]    sldu_rd_wdata;
    logic                       sldu_rd_wr_en;


    logic   [DATA_WIDTH-1:0]    rs1_rdata_lane          [0:LANES-1];
    logic   [DATA_WIDTH-1:0]    rs2_rdata_lane          [0:LANES-1];
    logic   [DATA_WIDTH-1:0]    viq_instr_lane          [0:LANES-1];
    logic                       instr_req_lane          [0:LANES-1];
    logic                       lane_ready              [0:LANES-1];


    arithm_instr_t              instr_running;
     
    logic   [ELEM_B-1:0]        lane_vs_elem_sel    [0:LANES-1];
    logic   [ELEM_B-1:0]        lane_vd_elem_sel    [0:LANES-1];
    logic   [DATA_WIDTH-1:0]    lane_vs1_rdata      [0:LANES-1];
    logic   [DATA_WIDTH-1:0]    lane_vs2_rdata      [0:LANES-1];
    logic   [DATA_WIDTH-1:0]    lane_vs3_rdata      [0:LANES-1];
    logic   [DATA_WIDTH-1:0]    lane_vd_wdata       [0:LANES-1];
    logic                       lane_vd_wr_en       [0:LANES-1];


    logic is_op_lsu;
    logic is_op_sldu;
    logic is_op_red;


assign  rd_wr_en_o = sldu_rd_wr_en;
assign  rd_o = sldu_rd_wdata;

always_ff @(posedge clk_i or negedge resetn_i) begin : instrFF
        if(!resetn_i) instr_running <= 0;
        else if(vreq_i) instr_running <= vinstr_i;
end


always_comb begin : readyLogic

    if((instr_running.funct6 inside {VSLIDEUP, VSLIDEDOWN}) || 
        ((instr_running.funct6 == VADC) && ((instr_running.funct3 == OPMVV) 
        || (instr_running.funct3 == OPMVX)))) vready_o = sldu_ready;
    else if(instr_running.opcode inside {VLOAD, VSTORE}) vready_o = lsu_ready;
    else if(instr_running.opcode == VARITH) vready_o = lane_ready[0];
    else vready_o = 1'b1;
    
end


assign is_op_sldu = (instr_running.funct6 inside {VSLIDEUP, VSLIDEDOWN}) || 
                        ((instr_running.funct6 == VADC) && ((instr_running.funct3 == OPMVV) || (instr_running.funct3 == OPMVX)) ||
                        is_op_red);
assign is_op_lsu = (instr_running.opcode inside {VLOAD, VSTORE});
assign is_op_red = ((instr_running.funct6 inside {VADD_VREDSUM, VREDAND, VSUB_VREDOR, VRSUB_VREDXOR
                        , VMINU_VREDMINU, VMIN_VREDMIN, VMAXU_VREDMAXU, VMAX_VREDMAX}) && (instr_running.funct3 == OPMVV));
    

genvar iLanes;
generate
    for(iLanes = 0; iLanes < LANES; iLanes = iLanes + 1) begin
            //No wait, it is not supposed to be 0,1,2,3...
            //But rather 0,4,8,12...
        for (genvar iLanes2 = 0; iLanes2 < LANES ; iLanes2 = iLanes2 + 1) begin
            //assign mask_bits_i[iLanes2][iLanes] = mask_bits_o[(iLanes2*LANES)+iLanes][0];
            assign mask_bits_i[iLanes2][iLanes] = mask_bits_o[0][(iLanes2*LANES)+iLanes];
        end

        always_comb begin
            
        
        if(is_op_lsu) begin
            lane_vs_elem_sel[iLanes] = lsu_vs_elem_sel_lane[iLanes];
            lane_vd_elem_sel[iLanes] = lsu_vd_elem_sel_lane[iLanes];
            lane_vd_wdata[iLanes] =  lsu_vd_wdata_lane[iLanes];
            lane_vd_wr_en[iLanes] =  lsu_vd_wr_en_lane[iLanes];
        end
        else begin
            lane_vs_elem_sel[iLanes] = sldu_vs1_elem_sel_lane[iLanes];
            lane_vd_elem_sel[iLanes] = sldu_vd_elem_sel_lane[iLanes];
            lane_vd_wdata[iLanes] =   sldu_vd_wdata_lane[iLanes];
            lane_vd_wr_en[iLanes] =   sldu_vd_wr_en_lane[iLanes];
        end
       
        end
        

        /*lane #(
            .DATA_WIDTH(DATA_WIDTH),
            .LANES(LANES),
            .REG_NUM(REG_NUM),
            .VLEN(VLEN)
        ) LANE(
            .clk_i(clk_i),
            .resetn_i(resetn_i),
            .lane_number_i(iLanes[1:0]),
            .instr_valid_i(),
            .instr_req_i(vreq_i),
            .instr_i(vinstr_i),   
            .ready_o(lane_ready[iLanes]),
            .mask_bits_i(mask_bits_i[iLanes]),
            .mask_bits_o(mask_bits_o[iLanes]),
            .rs1_rdata_i(rs1_i),
            .rd_wdata_o(),
            .ext_vs_elem_cnt_i(lane_vs_elem_sel[iLanes]),
            .ext_vd_elem_cnt_i(lane_vd_elem_sel[iLanes]),
            .ext_vd_wr_en_i(lane_vd_wr_en[iLanes]),
            .ext_vd_wdata_i(lane_vd_wdata[iLanes]),
            .ext_vs1_rdata_o(lane_vs1_rdata[iLanes]),
            .ext_vs2_rdata_o(lane_vs2_rdata[iLanes]),
            .ext_vs3_rdata_o(lane_vs3_rdata[iLanes])

        );
*/
        lane LANE(
            .clk_i(clk_i),
            .resetn_i(resetn_i),
            .lane_number_i(iLanes[1:0]),
            .instr_valid_i(),
            .instr_req_i(vreq_i),
            .instr_i(vinstr_i),   
            .ready_o(lane_ready[iLanes]),
            .mask_bits_i(mask_bits_i[iLanes]),
            .mask_bits_o(mask_bits_o[iLanes]),
            .rs1_rdata_i(rs1_i),
            .rd_wdata_o(),
            .ext_vs_elem_cnt_i(lane_vs_elem_sel[iLanes]),
            .ext_vd_elem_cnt_i(lane_vd_elem_sel[iLanes]),
            .ext_vd_wr_en_i(lane_vd_wr_en[iLanes]),
            .ext_vd_wdata_i(lane_vd_wdata[iLanes]),
            .ext_vs1_rdata_o(lane_vs1_rdata[iLanes]),
            .ext_vs2_rdata_o(lane_vs2_rdata[iLanes]),
            .ext_vs3_rdata_o(lane_vs3_rdata[iLanes])

        );


    end

endgenerate



SLDU #(
    .DATA_WIDTH(DATA_WIDTH),
    .LANES(LANES),
    .VLEN(VLEN)
) sldu(

    .clk_i(clk_i),
    .resetn_i(resetn_i),
    .req_i(vreq_i),
    .instr_i(vinstr_i),
    .ready_o(sldu_ready),
    .rs1_rdata_i(rs1_i), //Also used for scalar argument
    .rd_wdata_o(sldu_rd_wdata), //Scalar output
    .rd_wr_en_o(sldu_rd_wr_en),
    .lane_vs1_rdata_i(lane_vs1_rdata),
    .lane_vs2_rdata_i(lane_vs2_rdata),
    .lane_mask_rdata_i(mask_bits_o[0]),
    .lane_vd_wdata_o(sldu_vd_wdata_lane),
    .lane_vd_wr_en_o(sldu_vd_wr_en_lane),
    .lane_vs2_elem_sel_o(sldu_vs1_elem_sel_lane), //This is to chose element from lanes 
    .lane_vd_elem_sel_o(sldu_vd_elem_sel_lane)
);



VLSU  #(
    .DATA_WIDTH(DATA_WIDTH),
    .LANES(LANES),
    .VLEN(VLEN)
) vlsu(

    .clk_i(clk_i),
    .resetn_i(resetn_i),
    .req_i(vreq_i),
    .instr_i(vinstr_i),
    .ready_o(lsu_ready),
    .vrf_vd_elem_cnt_o(lsu_vd_elem_sel_lane),  
    .vrf_vs_elem_cnt_o(lsu_vs_elem_sel_lane),  
    .vrf_vd_wr_en_o(lsu_vd_wr_en_lane),     
    .rf_rs1_rdata_i(rs1_i),
    .rf_rs2_rdata_i(rs2_i),
    .vrf_vs2_rdata_i(lane_vs2_rdata), 
    .vrf_vs3_rdata_i(lane_vs3_rdata),
    .vrf_mask_bit_i(mask_bits_o[0]), //Wait, masking in VLSU is treated as single 32 bit data.
    .vrf_vd_wdata_o(lsu_vd_wdata_lane),
    .haddr_o(haddr_o), 
    .hrdata_i(hrdata_i),
    .hwdata_o(hwdata_o),
    .hsize_o(hsize_o),
    .hwrite_o(hwrite_o),
    .hready_i(hready_i), 
    .hresp_i(hresp_i) 
);

endmodule

