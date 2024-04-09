module Vector_Core import vect_pkg::*; #(
    parameter DATA_WIDTH    =   32,
    parameter REG_NUM       =   32,
    parameter LANES         =   4,
    parameter VLEN          =   512,
    parameter ELEMS         =   VLEN/(DATA_WIDTH*LANES),
    parameter IQ_DEPTH      =   8,

    localparam FU_WIDTH = LANES*DATA_WIDTH,
    localparam ADDR_B = $clog2(REG_NUM),
    localparam ELEM_B = $clog2(ELEMS),
    localparam SBIT_CNT_B = $clog2(DATA_WIDTH),
    localparam VECT_BURST = FU_WIDTH/DATA_WIDTH
)(
    input                           clk_i,
    input                           resetn_i,
    input       [DATA_WIDTH-1:0]    vinstr_i,
    input       [DATA_WIDTH-1:0]    rs1_i,
    input       [DATA_WIDTH-1:0]    rs2_i,
    input                           vreq_i,
    output  reg                     vready_o,
    output                          v_iq_ack_o,
    output                          v_iq_full_o,
    output  reg                     v_lsu_active_o,
    output      [DATA_WIDTH-1:0]    rd_o,
    output                          rd_wr_en_o,
    output      [SBIT_CNT_B:0]      sbit_cnt_o      [LANES-2:0],

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

    logic   [VECT_BURST-1:0]    mask_bits_i             [0:LANES-1];
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



    logic                       instr_req_lane          [0:LANES-1];
    logic                       lane_ready              [0:LANES-1];
    logic                       lane_idle               [0:LANES-1];
    logic                       lane_ready_pending;


    arithm_instr_t              instr_running;
    arithm_instr_t              instr_in;
    logic   [3:0]               instr_imm5;
     
    logic   [ELEM_B-1:0]        lane_vs_elem_sel    [0:LANES-1];
    logic   [ELEM_B-1:0]        lane_vd_elem_sel    [0:LANES-1];
    logic   [DATA_WIDTH-1:0]    lane_vs1_rdata      [0:LANES-1];
    logic   [DATA_WIDTH-1:0]    lane_vs2_rdata      [0:LANES-1];
    logic   [DATA_WIDTH-1:0]    lane_vs3_rdata      [0:LANES-1];
    logic   [DATA_WIDTH-1:0]    lane_vd_wdata       [0:LANES-1];
    logic                       lane_vd_wr_en       [0:LANES-1];
    logic                       lane_lsu_ready;
    logic                       lane_sldu_ready;


    logic                       is_op_lsu;
    logic                       is_op_sldu;
    logic                       is_op_red;

    logic                       ext_lsu_req         [0:LANES-1];
    logic                       ext_sldu_req        [0:LANES-1];
    logic                       ext_instr_save      [0:LANES-1];

    logic   [SBIT_CNT_B:0]      lane_sbit_cnt       [0:LANES-1];
    

    //Scalar operands registers

    logic                       is_rs1_used;
    logic                       is_rs2_used;
    logic                       is_imm5_used;
    logic   [DATA_WIDTH-1:0]    rs1_reg_q;
    logic   [DATA_WIDTH-1:0]    rs2_reg_q;

    logic   [DATA_WIDTH-1:0]    iq_instr_wr;
    arithm_instr_t              iq_instr_rd;
    logic                       iq_rd_en;
    logic                       iq_wr_en;
    logic                       iq_full;
    logic                       iq_empty;
    logic                       iq_error;
    logic                       iq_wr_done;
    logic                       iq_rd_done;

    logic                       rs1q_full;
    logic                       rs1q_empty;
    logic                       rs1q_error;
    logic   [DATA_WIDTH-1:0]    rs1q_rdata;
    

    logic                       rs2q_full;
    logic                       rs2q_empty;
    logic                       rs2q_error;
    logic   [DATA_WIDTH-1:0]    rs2q_rdata;

assign rd_wr_en_o   =   sldu_rd_wr_en;
assign rd_o         =   sldu_rd_wdata;
assign instr_in     =   vinstr_i;
assign instr_imm5   =   instr_running.vs1_rs1_imm;


/*
always_comb begin : readyLogic

    if((instr_running.funct6 inside {VSLIDEUP, VSLIDEDOWN}) || 
        ((instr_running.funct6 == VADC) && ((instr_running.funct3 == OPMVV) 
        || (instr_running.funct3 == OPMVX)))) vready_o = sldu_ready;
    else if(instr_running.opcode inside {VLOAD, VSTORE}) vready_o = lsu_ready;
    else if(instr_running.opcode == VARITH) vready_o = lane_ready[0];
    else vready_o = 1'b1;
    
end
*/
assign vready_o   = lane_ready[0];
assign is_op_sldu = (instr_running.funct6 inside {VSLIDEUP, VSLIDEDOWN}) || 
                        ((instr_running.funct6 == VADC) && ((instr_running.funct3 == OPMVV) || (instr_running.funct3 == OPMVX)) ||
                        is_op_red);
assign is_op_lsu = (instr_running.opcode inside {VLOAD, VSTORE});
assign is_op_red = ((instr_running.funct6 inside {VADD_VREDSUM, VREDAND, VSUB_VREDOR, VRSUB_VREDXOR
                        , VMINU_VREDMINU, VMIN_VREDMIN, VMAXU_VREDMAXU, VMAX_VREDMAX}) && (instr_running.funct3 == OPMVV));
    
  ///////////////////////
  // Lane set bits comparison         
  ///////////////////////

  /*
    This module calculates the difference between the number of set bits in each lane.
    lane_sbit_diff[0] - difference between lane 0 and lane 1
    lane_sbit_diff[1] - difference between lane 1 and lane 2
    lane_sbit_diff[2] - difference between lane 2 and lane 3
  */

  
    balance_ctrl #(
    .DATA_WIDTH(DATA_WIDTH),
    .SBIT_CNT_B(SBIT_CNT_B),
    .LANES(LANES)
    )   BALANCE_CTRL(
    .lane_sbit_cnt_i(lane_sbit_cnt),
    .balance_cnt_o(sbit_cnt_o)
);

  ///////////////////////
  // Instruction issue          
  ///////////////////////

   //FIFO?
    always_ff @(posedge clk_i or negedge resetn_i) begin : readyPendingFF
        if(!resetn_i)                   lane_ready_pending  <=  1'b1;
        else if(!lane_ready_pending)    lane_ready_pending  <=  lane_ready[0];
        else if(lane_ready_pending)     lane_ready_pending  <=  iq_rd_en;
    end

    always_ff @(posedge clk_i or negedge resetn_i) begin : ackFF
        if(!resetn_i)      begin 
            iq_wr_done  <=  0;
            iq_rd_done  <=  0;
        end
        else begin
            iq_rd_done  <=  !iq_rd_en;
            iq_wr_done  <=  !iq_wr_en;
        end 
    end

    assign  v_iq_ack_o      =   iq_wr_done && !iq_error;
    assign  iq_wr_en        =   !(vreq_i && !iq_full);
    assign  iq_rd_en        =   !(!iq_empty && lane_ready_pending); 
    assign  v_iq_full_o     =   iq_full;
    assign  iq_instr_wr     =   vinstr_i;


   DW_fifo_s1_sf #(
        .width(DATA_WIDTH), 
        .depth(IQ_DEPTH),
        .ae_level(1), 
        .af_level(IQ_DEPTH-1), 
        .err_mode(0), 
        .rst_mode(0)
    ) IQ(
        .clk(clk_i), 
        .rst_n(resetn_i), 
        .push_req_n(iq_wr_en),
        .pop_req_n(iq_rd_en),
        .diag_n(1'b1),
        .data_in(iq_instr_wr), 
        .empty(iq_empty),
        //.almost_empty(almost_empty_inst),
        //.half_full(half_full_inst),
        //.almost_full(almost_full_inst),
        .full(iq_full),
        .error(iq_error),
        .data_out(iq_instr_rd) 
    );

    always_ff @(posedge clk_i or negedge resetn_i) begin : instrFF
        if(!resetn_i)   instr_running <= 0;
        //else if(vreq_i) instr_running <= vinstr_i;
        else if(!iq_rd_en) instr_running <= iq_instr_rd;
    end


  ///////////////////////
  // Scalar input registers (FIFO)          
  ///////////////////////

    assign is_rs1_used  =   (iq_instr_rd.funct3 inside {OPIVX, OPFVF, OPMVV}) || (iq_instr_rd.opcode inside {VLOAD, VSTORE});
    assign is_rs2_used  =   (iq_instr_rd.opcode inside {VLOAD, VSTORE}) && (iq_instr_rd[27:26] == OFF_STRIDE);
    assign is_imm5_used =   (iq_instr_rd.funct3 == OPIVI);
    

  always_ff @(posedge clk_i or negedge resetn_i) begin : rs_reg
    if(!resetn_i) begin
        rs1_reg_q                           <=  '0;
        rs2_reg_q                           <=  '0;
    end
    else begin
        //if(is_rs1_used)         rs1_reg_q   <=  rs1q_rdata;
        if(!iq_rd_en)           rs1_reg_q   <=  rs1q_rdata;
        else if(is_imm5_used)   rs1_reg_q   <=  instr_imm5;
        //if(is_rs2_used)         rs2_reg_q   <=  rs2q_rdata;
        if(!iq_rd_en)           rs2_reg_q   <=  rs2q_rdata;
    end
  end

   DW_fifo_s1_sf #(
        .width(DATA_WIDTH), 
        .depth(IQ_DEPTH),
        .ae_level(1), 
        .af_level(IQ_DEPTH-1), 
        .err_mode(0), 
        .rst_mode(0)
    ) RS1_BUFFER(
        .clk(clk_i), 
        .rst_n(resetn_i), 
        .push_req_n(iq_wr_en),
        .pop_req_n(iq_rd_en),
        .diag_n(1'b1),
        .data_in(rs1_i), 
        .empty(rs1q_empty),
        //.almost_empty(almost_empty_inst),
        //.half_full(half_full_inst),
        //.almost_full(almost_full_inst),
        .full(rs1q_full),
        .error(rs1q_error),
        .data_out(rs1q_rdata) 
    );

   DW_fifo_s1_sf #(
        .width(DATA_WIDTH), 
        .depth(IQ_DEPTH),
        .ae_level(1), 
        .af_level(IQ_DEPTH-1), 
        .err_mode(0), 
        .rst_mode(0)
    ) RS2_BUFFER(
        .clk(clk_i), 
        .rst_n(resetn_i), 
        .push_req_n(iq_wr_en),
        .pop_req_n(iq_rd_en),
        .diag_n(1'b1),
        .data_in(rs2_i), 
        .empty(rs2q_empty),
        //.almost_empty(almost_empty_inst),
        //.half_full(half_full_inst),
        //.almost_full(almost_full_inst),
        .full(rs2q_full),
        .error(rs2q_error),
        .data_out(rs2q_rdata) 
    );
  ///////////////////////
  // Lanes  
  ///////////////////////
genvar iLanes;
generate 
    for(iLanes = 0; iLanes < LANES; iLanes = iLanes + 1) begin : genLane
            //No wait, it is not supposed to be 0,1,2,3...
            //But rather 0,4,8,12...
        for (genvar iLanes2 = 0; iLanes2 < LANES ; iLanes2 = iLanes2 + 1) begin
            //assign mask_bits_i[iLanes2][iLanes] = mask_bits_o[(iLanes2*LANES)+iLanes][0];
            assign mask_bits_i[iLanes2][iLanes] = mask_bits_o[0][(iLanes2*LANES)+iLanes];
        end

        always_comb begin
            
        
        if(is_op_lsu) begin
            lane_vs_elem_sel[iLanes]    =   lsu_vs_elem_sel_lane[iLanes];
            lane_vd_elem_sel[iLanes]    =   lsu_vd_elem_sel_lane[iLanes];
            lane_vd_wdata[iLanes]       =   lsu_vd_wdata_lane[iLanes];
            lane_vd_wr_en[iLanes]       =   lsu_vd_wr_en_lane[iLanes];
        end
        else begin
            lane_vs_elem_sel[iLanes]    =   sldu_vs1_elem_sel_lane[iLanes];
            lane_vd_elem_sel[iLanes]    =   sldu_vd_elem_sel_lane[iLanes];
            lane_vd_wdata[iLanes]       =   sldu_vd_wdata_lane[iLanes];
            lane_vd_wr_en[iLanes]       =   sldu_vd_wr_en_lane[iLanes];
        end
       
        end
        

          lane LANE(
            .clk_i(clk_i),
            .resetn_i(resetn_i),
            .instr_req_i(!iq_rd_en),
            .instr_i(iq_instr_rd),
            .ready_o(lane_ready[iLanes]),
            .idle_o(lane_idle[iLanes]),
            .mask_bits_i(mask_bits_i[iLanes]),
            .mask_bits_o(mask_bits_o[iLanes]),
            .rs1_rdata_i(rs1_reg_q),
            .sbit_cnt_o(lane_sbit_cnt[iLanes]),
            .lsu_ready_i(lsu_ready),
            .sldu_ready_i(sldu_ready),
            .lsu_req_o(ext_lsu_req[iLanes]),
            .sldu_req_o(ext_sldu_req[iLanes]),
            .ext_instr_save_o(ext_instr_save[iLanes]),
            .ext_vs_elem_cnt_i(lane_vs_elem_sel[iLanes]),
            .ext_vd_elem_cnt_i(lane_vd_elem_sel[iLanes]),
            .ext_vd_wr_en_i(lane_vd_wr_en[iLanes]),
            .ext_vd_wdata_i(lane_vd_wdata[iLanes]),
            .ext_vs1_rdata_o(lane_vs1_rdata[iLanes]),
            .ext_vs2_rdata_o(lane_vs2_rdata[iLanes]),
            .ext_vs3_rdata_o(lane_vs3_rdata[iLanes])

        );
  
/*
`else 

        lane #(
            .DATA_WIDTH(32),
            .REG_NUM(32),   
            .VLEN(512),
            .LANE_NUM(iLanes),     
            .LANES(4),      
            .PIPE_ST(4)    
            )LANE(
            .clk_i(clk_i),
            .resetn_i(resetn_i),
            .instr_req_i(!iq_rd_en),
            .instr_i(iq_instr_rd),
            .ready_o(lane_ready[iLanes]),
            .idle_o(lane_idle[iLanes]),
            .mask_bits_i(mask_bits_i[iLanes]),
            .mask_bits_o(mask_bits_o[iLanes]),
            .rs1_rdata_i(rs1_reg_q),
            .lsu_ready_i(lsu_ready),
            .sldu_ready_i(sldu_ready),
            .lsu_req_o(ext_lsu_req[iLanes]),
            .sldu_req_o(ext_sldu_req[iLanes]),
            .ext_instr_save_o(ext_instr_save[iLanes]),
            .ext_vs_elem_cnt_i(lane_vs_elem_sel[iLanes]),
            .ext_vd_elem_cnt_i(lane_vd_elem_sel[iLanes]),
            .ext_vd_wr_en_i(lane_vd_wr_en[iLanes]),
            .ext_vd_wdata_i(lane_vd_wdata[iLanes]),
            .ext_vs1_rdata_o(lane_vs1_rdata[iLanes]),
            .ext_vs2_rdata_o(lane_vs2_rdata[iLanes]),
            .ext_vs3_rdata_o(lane_vs3_rdata[iLanes])

        );

*/

    end

endgenerate

  ///////////////////////
  // EXT Instruction buffer          
  ///////////////////////

  logic                     ext_is_new;
  logic [DATA_WIDTH-1:0]    ext_instr_buf_q;
  logic                     ext_buf_req;
  
  
  assign    ext_buf_req =   (is_op_lsu || is_op_sldu) && ext_is_new; 

    //Determine if LSU is running for arbitering purpose. 
    //Set when new LSU op is received. Clear when LSU is ready.
    always_ff @(posedge clk_i or negedge resetn_i) begin : lsu_active_FF
        if(!resetn_i)                           v_lsu_active_o  <=  1'b0;
        else if(ext_is_new && is_op_lsu)        v_lsu_active_o  <=  1'b1;
        else if(v_lsu_active_o && lsu_ready)    v_lsu_active_o  <=  1'b0;
    end


  always_ff @(posedge clk_i or negedge resetn_i) begin : instr_buf
    if(~resetn_i)           begin
        ext_instr_buf_q <=  '0;
        ext_is_new      <=  '0;    
    end 
    else if(ext_instr_save[0])    begin
        ext_instr_buf_q <=  instr_running;
        ext_is_new      <=  '0;
    end 
    //else if(vreq_i) begin
    else if(iq_rd_done) begin
        ext_is_new      <=  1'b1;
    end 
  end

  ///////////////////////
  // SLDU          
  ///////////////////////

SLDU #(
    .DATA_WIDTH(DATA_WIDTH),
    .LANES(LANES),
    .VLEN(VLEN)
) sldu(

    .clk_i(clk_i),
    .resetn_i(resetn_i),
    .req_i(ext_sldu_req[0]),
    .instr_i(ext_instr_buf_q),
    .ready_o(sldu_ready),
    .rs1_rdata_i(rs1_reg_q), //Also used for scalar argument
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

  ///////////////////////
  // VLSU          
  ///////////////////////

VLSU  #(
    .DATA_WIDTH(DATA_WIDTH),
    .LANES(LANES),
    .VLEN(VLEN)
) vlsu(

    .clk_i(clk_i),
    .resetn_i(resetn_i),
    .req_i(ext_lsu_req[0]),
    .instr_i(ext_instr_buf_q),
    .ready_o(lsu_ready),
    .vrf_vd_elem_cnt_o(lsu_vd_elem_sel_lane),  
    .vrf_vs_elem_cnt_o(lsu_vs_elem_sel_lane),  
    .vrf_vd_wr_en_o(lsu_vd_wr_en_lane),     
    .rf_rs1_rdata_i(rs1_reg_q),
    .rf_rs2_rdata_i(rs2_reg_q),
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


//If synthesis is being done, ignore
`ifdef SIM_TASKS
task showRF;   //{ USAGE: inst.show (low, high);
   input [31:0] low, high;
   integer i;
   integer e;
   integer l;
   begin //{
   $display ("\n%m: RF content dump");
   if (low < 0 || low > high || high >= REG_NUM)
      $display ("Error! Invalid address range (%0d, %0d).", low, high,
                "\nUsage: %m (low, high);",
                "\n       where low >= 0 and high <= %0d.", REG_NUM-1);
   else
      begin
      $write ("VREG");
      for(l = 0; l < LANES*ELEMS; l = l + 1) 
        $write("E%d ", l);

      for (i = low ; i <= high ; i = i + 1) begin
        //$display ("%d\t%b", i, mem[i]);
        $write("\n V%d", i);
         for(e = 0; e < ELEMS; e = e + 1) begin
            //for(l = 0; l < LANES; l = l + 1) begin
            $write(" %h ", genLane[0].LANE.RF.v_reg[i][e]);
            $write(" %h ", genLane[1].LANE.RF.v_reg[i][e]);
            $write(" %h ", genLane[2].LANE.RF.v_reg[i][e]);
            $write(" %h ", genLane[3].LANE.RF.v_reg[i][e]);
                //$write("a");      
         end

      end

      end
      $write("\n");
   end //}
endtask //}
`endif


`ifdef SIM_TASKS_DW
task showRF;   //{ USAGE: inst.show (low, high);
   input [31:0] low, high;
   integer i;
   integer e;
   integer l;
   begin //{
   $display ("\n%m: RF content dump");
   if (low < 0 || low > high || high >= REG_NUM)
      $display ("Error! Invalid address range (%0d, %0d).", low, high,
                "\nUsage: %m (low, high);",
                "\n       where low >= 0 and high <= %0d.", REG_NUM-1);
   else
      begin
      $write ("VREG");
      for(l = 0; l < LANES*ELEMS; l = l + 1) 
        $write("E%d ", l);

      for (i = low ; i <= high ; i = i + 1) begin
        //$display ("%d\t%b", i, mem[i]);
        $write("\n V%d", i);

            $write(" %h ", genLane[0].LANE.RF.BANK[0].RAM_DW.mem[i]);
            $write(" %h ", genLane[0].LANE.RF.BANK[1].RAM_DW.mem[i]);
            $write(" %h ", genLane[0].LANE.RF.BANK[2].RAM_DW.mem[i]);
            $write(" %h ", genLane[0].LANE.RF.BANK[3].RAM_DW.mem[i]);


            $write(" %h ", genLane[1].LANE.RF.BANK[0].RAM_DW.mem[i]);
            $write(" %h ", genLane[1].LANE.RF.BANK[1].RAM_DW.mem[i]);
            $write(" %h ", genLane[1].LANE.RF.BANK[2].RAM_DW.mem[i]);
            $write(" %h ", genLane[1].LANE.RF.BANK[3].RAM_DW.mem[i]);

            $write(" %h ", genLane[2].LANE.RF.BANK[0].RAM_DW.mem[i]);
            $write(" %h ", genLane[2].LANE.RF.BANK[1].RAM_DW.mem[i]);
            $write(" %h ", genLane[2].LANE.RF.BANK[2].RAM_DW.mem[i]);
            $write(" %h ", genLane[2].LANE.RF.BANK[3].RAM_DW.mem[i]);

            $write(" %h ", genLane[3].LANE.RF.BANK[0].RAM_DW.mem[i]);
            $write(" %h ", genLane[3].LANE.RF.BANK[1].RAM_DW.mem[i]);
            $write(" %h ", genLane[3].LANE.RF.BANK[2].RAM_DW.mem[i]);
            $write(" %h ", genLane[3].LANE.RF.BANK[3].RAM_DW.mem[i]);
            //$write(" %h ", genLane[1].LANE.RF.BANK[e].RAM_DW.mem[i]);
            //$write(" %h ", genLane[2].LANE.RF.BANK[e].RAM_DW.mem[i]);
            //$write(" %h ", genLane[3].LANE.RF.BANK[e].RAM_DW.mem[i]);


      end

      end
      $write("\n");
   end //}
endtask //}
`endif 
endmodule

