module controller #(
    parameter DATA_WIDTH = 32,
    parameter LANES = 4,
    parameter VLEN = 512

)(
    input                   clk_i,
    input                   resetn_i,
    input [DATA_WIDTH-1:0]  instr_i,
    input [DATA_WIDTH-1:0]  rs1_i,
    input [DATA_WIDTH-1:0]  rs2_i,

    input                   vreq_i,
    input                   instr_queue_empty_i,
    output reg              instr_queue_read_o,
    output reg              vready_o,

    output                  vlsu_stall_o,
    output                  vfu_stall_o,
    
    input                   vlsu_queue_full_i,
    input                   vlsu_ready_i,
    output                  vlsu_req_o,
    output                  vlsu_write_o,
    output [7:0]            vlsu_stride_o,

    output [5:0]            op_sel_o,

    output                  chime_ready_o,

    output [4:0]            vd1_addr_o,
    output [4:0]            vs1_addr_o, 
    output [4:0]            vs2_addr_o, 
    output [4:0]            vs3_addr_o,    
    output                  vd1_wr_en_o,
    output                  fu_scal_vectn_sel_o,

    output [1:0]            vrf_element_sel_o, 
    output                  vrf_mux_sel_o,
    output                  vlsu_mux_sel_o
);


localparam CTRL_IDLE = 1'b0;
localparam CTRL_RUN = 1'b1;

logic           ctrl_this_state;
logic           ctrl_next_state;

localparam TOTAL_WIDTH = LANES*DATA_WIDTH;
localparam VL_CYCLES = VLEN/DATA_WIDTH;
localparam VL_CNT_WIDTH = $clog2(VL_CYCLES);

logic   [VL_CNT_WIDTH-1:0]   vl_cycle_cnt;
logic   [2:0]   SEW_reg;
logic   [2:0]   VLMUL_reg;
logic           fetch_stall;


//TEST VALUES !!! CHECK
assign vd1_wr_en_o = 1;
assign vd1_addr_o = instr_i[11:7];
assign vs1_addr_o = instr_i[19:15];
assign vs2_addr_o = instr_i[24:20];
assign vs3_addr_o = instr_i[11:7];
assign op_sel_o = instr_i[31:26]; //In reality, 31:26
assign vlsu_mux_sel_o = 1;
assign vrf_mux_sel_o = 0;
assign vlsu_req_o = 1;

//assign vlsu_stall_o = ;
//assing vfu_stall_o = ;

//Add decoding of fu_scal_vectn_sel_o for vector-scalar (1) and (0) for other ops
//Add decoding for selecting between scalar and immediate

assign vrf_element_sel_o = vl_cycle_cnt;


always_ff @( posedge clk_i or negedge resetn_i ) begin : ctrlFSM
    if(~resetn_i) begin
        ctrl_this_state <= CTRL_IDLE;
    end
    else ctrl_this_state <= ctrl_next_state;
end

always_comb begin : ctrlLogic
    if(ctrl_this_state == CTRL_IDLE) begin 
        ctrl_next_state = (~instr_queue_empty_i) ? CTRL_RUN : CTRL_IDLE;
        vready_o = 1'b0;
        instr_queue_read_o = ~instr_queue_empty_i;
    end
    else if(ctrl_this_state == CTRL_RUN) begin
        ctrl_next_state = (vl_cycle_cnt == VL_CYCLES) ? ((vreq_i) ? CTRL_RUN : CTRL_IDLE) : CTRL_RUN;
        vready_o = (vl_cycle_cnt == VL_CYCLES); 
        instr_queue_read_o = (~instr_queue_empty_i && ~fetch_stall); //Don't read fifo when it's empty or when fetch_stall condition is present
    end
end

always_ff @( posedge clk_i or negedge resetn_i ) begin : vcycleCnt
    if(~resetn_i) begin
        vl_cycle_cnt <= 0;
    end
    else begin
        if(ctrl_this_state == CTRL_RUN) vl_cycle_cnt <= vl_cycle_cnt + 1;
        else vl_cycle_cnt <= 0;
    end
end





endmodule