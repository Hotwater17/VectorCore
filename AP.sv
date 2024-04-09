


module AP #(
    parameter DATA_WIDTH = 32,
    parameter IQUEUE_DEPTH = 8,
    parameter LANES = 4,
    parameter REG_NUM = 32,
    
    localparam ADDR_B = $clog2(LANES),
    localparam ELEM_B = $clog2(LANES),
    localparam FU_WIDTH = DATA_WIDTH * LANES,
    localparam VECTOR_BURST_SIZE = FU_WIDTH/DATA_WIDTH
)(

    //COMMON SIGNALS
    input                   clk_i,
    input                   resetn_i,

    //QUEUE CONTROL
    input [DATA_WIDTH-1:0]  queue_instr_i,
    input                   queue_write_en_i,
    output reg              queue_full_o,
    output reg              ap_graduate_o,
    input                   ap_stall_i,

    //MEMORY SIGNALS
    input                   mem_ready_i,
    input                   mem_error_i,
    //FIFO SIGNALS
    output reg              mem_fifo_wdata_write_en_o,
    output reg              mem_fifo_rdata_read_en_o,
    input                   mem_fifo_wdata_full_i,
    input                   mem_fifo_rdata_empty_i,

    //REGISTERS INTERFACE
    input [DATA_WIDTH-1:0]  rs1_base_i,
    input [DATA_WIDTH-1:0]  rs2_stride_i,
    input [DATA_WIDTH-1:0]  vs2_offset_i    [0:LANES-1],   
     

    output reg [ELEM_B-1:0] vs_element_cnt_o    [0:LANES-1],
    output reg [ELEM_B-1:0] vd_element_cnt_o    [0:LANES-1],    
    /*
    output [ADDR_B-1:0]     rs1_addr_o  [0:LANES-1],
    output [ADDR_B-1:0]     rs2_addr_o  [0:LANES-1],
    output [ADDR_B-1:0]     vs2_addr_o  [0:LANES-1],
    output [ADDR_B-1:0]     vs3_addr_o  [0:LANES-1],
    output [ADDR_B-1:0]     vd_addr_o   [0:LANES-1],
    output reg              vd_wr_en_o  [0:LANES-1],
    output reg              vd_mask_en_o,
    */
    output                  rn_w_o,
    output [FU_WIDTH-1:0]   addr_o,
    output reg              vd_wr_en_o 

);




//INSTRUCTION DECODER
localparam STATE_IDLE = 2'b00;
localparam STATE_GENERATE = 2'b01;
localparam STATE_ACCESS = 2'b10;

logic [1:0] decoder_this_state;
logic [1:0] decoder_next_state;

logic [1:0] decoder_next_addr_cnt;
logic [1:0] decoder_this_addr_cnt;

logic [DATA_WIDTH-1:0]  instr_reg;


//Queue
logic queue_empty;
logic queue_read_en;

//Calculation control
logic [1:0] offset_term_sel;
logic       base_term_sel;   
logic       adder_reg_wen;

logic is_first_calc_cycle;

//Instruction fields
/*
logic [4:0] rs1_addr;
logic [4:0] rs2_addr;
logic [4:0] vs2_addr;
logic [4:0] vs3_addr;
logic [4:0] vd_addr;
logic       vector_mask;
*/
logic [2:0] mem_elem_width;
logic       ext_elem_width;
logic [1:0] mop_addr_mode;
logic [2:0] fields_num;
logic [4:0] lsumop;
logic [6:0] opcode;
logic       rn_w;

logic opcode_valid;

//Change this into common package definitions
/*
assign rs1_addr = instr_reg[19:15];
assign rs2_addr = instr_reg[24:20];
assign vs2_addr = instr_reg[24:20];
assign vs3_addr = instr_reg[11:7];
assign vd_addr = instr_reg[11:7];
assign vector_mask = instr_reg[25];*/
assign mem_elem_width = instr_reg[14:12];
assign ext_elem_width = instr_reg[28];
assign mop_addr_mode = instr_reg[27:26];
assign fields_num = instr_reg[31:29];
assign lsumop = instr_reg[24:20];
assign opcode = instr_reg[6:0];
assign rn_w = instr_reg[5];

/*
assign vd_addr_o = vd_addr;
assign vs2_addr_o = vs2_addr;
assign vs3_addr_o = vs3_addr;
assign vd_mask_en_o = vector_mask; 
*/
assign rn_w_o = rn_w;

//TODO: Change this into proper opcode 
assign opcode_valid = (opcode == 7'b0000111) | (opcode == 7'b0100111);

//FIFO here

    FIFO #(
    .FIFO_WIDTH(DATA_WIDTH),
    .FIFO_DEPTH(IQUEUE_DEPTH)
    ) instr_queue(
    .clk_i(clk_i),
    .resetn_i(resetn_i),
    .write_en_i(queue_write_en_i),
    .wdata_i(queue_instr_i),
    .wfull_o(queue_full_o),
    .read_en_i(queue_read_en),
    .rdata_o(instr_reg),
    .rempty_o(queue_empty)
    );


assign is_first_calc_cycle = ((decoder_this_state == STATE_IDLE) && (decoder_next_state == STATE_GENERATE)); 
always_comb begin : calculation_mux
    base_term_sel = is_first_calc_cycle;
    offset_term_sel = mop_addr_mode;
end


always_ff @(posedge clk_i or negedge resetn_i) begin : decode_FSM
    if(~resetn_i) begin
        decoder_this_state <= STATE_IDLE;
        decoder_this_addr_cnt <= 0;
    end
    else begin
        decoder_this_state <= decoder_next_state;
        decoder_this_addr_cnt <= decoder_next_addr_cnt;
    end
end

always_comb begin : decode_comb
    case (decoder_this_state)
        STATE_IDLE : begin
            decoder_next_state = (queue_empty || ap_stall_i) ? STATE_IDLE : STATE_GENERATE;
            decoder_next_addr_cnt = VECTOR_BURST_SIZE-1;
            adder_reg_wen = (decoder_next_state == STATE_GENERATE);  
            mem_fifo_wdata_write_en_o = 1'b0;
            mem_fifo_rdata_read_en_o = 1'b0;
            vs_element_cnt_o = 0;
            vd_element_cnt_o = 0;
            vd_wr_en_o = 1'b0;
            ap_graduate_o = 1'b0;
            queue_read_en = (~queue_empty && ~ap_stall_i);
        end

        STATE_GENERATE : begin
            //ALSO NOTE THAT YOU NEED FOR FIFO TO NOT BE FULL. GO TO IDLE IF OPCODE IS INVALID
            decoder_next_state = (opcode_valid) ? (((decoder_this_addr_cnt == 0) && ~mem_fifo_wdata_full_i) ? STATE_ACCESS : STATE_GENERATE) : STATE_IDLE; 
            //Do not write new address if counter is 0 - all addresses generated
            adder_reg_wen = !(decoder_this_addr_cnt == 0); 
            //Stalling counter in case of full fifo
            decoder_next_addr_cnt = (decoder_next_state == STATE_ACCESS) ? VECTOR_BURST_SIZE-1 : (~mem_fifo_wdata_full_i) ? decoder_this_addr_cnt-1 : decoder_this_addr_cnt;
            mem_fifo_wdata_write_en_o = ~mem_fifo_wdata_full_i;
            mem_fifo_rdata_read_en_o = 1'b0;
            vs_element_cnt_o = (VECTOR_BURST_SIZE-1)-decoder_this_addr_cnt;
            vd_element_cnt_o = 0;
            vd_wr_en_o = 1'b0;
            ap_graduate_o = ~(opcode_valid);
            queue_read_en = 1'b0;
        end

        STATE_ACCESS : begin
            //Look at ready from memory
            //Think if you really need ready from memory, or rather just look at fifo empty signal
            //Add error reading for re-trying transfer
            //Error would loop back to generate state, without graduate high
            decoder_next_state = ((decoder_this_addr_cnt == 0) && mem_ready_i && ~mem_fifo_rdata_empty_i) ? STATE_IDLE : STATE_ACCESS;
            adder_reg_wen = 1'b0;
            //Stall counter if fifo is empty (no new data ready from cache)
            decoder_next_addr_cnt = ((decoder_this_addr_cnt != 0) && mem_ready_i && ~mem_fifo_rdata_empty_i) ? (decoder_this_addr_cnt - 1) : decoder_this_addr_cnt;
            mem_fifo_wdata_write_en_o = 1'b0;
            mem_fifo_rdata_read_en_o = ~mem_fifo_rdata_empty_i && ~rn_w; //Read fifo if its not empty and the instruction is load
            vs_element_cnt_o = (VECTOR_BURST_SIZE-1)-decoder_this_addr_cnt;
            vd_element_cnt_o = (~rn_w) ? ((VECTOR_BURST_SIZE-1)-decoder_this_addr_cnt) : 0;
            vd_wr_en_o = ~mem_fifo_rdata_empty_i && ~rn_w; //!!!wait, there has to be one delay cycle between first fifo read and first reg write
            ap_graduate_o = ((decoder_next_state == STATE_IDLE) && ~mem_error_i); 
            queue_read_en = ((decoder_this_addr_cnt == 0) && mem_ready_i && ~mem_fifo_rdata_empty_i);
        end

        default: begin
            decoder_next_state = STATE_IDLE; 
            adder_reg_wen = 1'b0;
            decoder_next_addr_cnt = 0;
            mem_fifo_wdata_write_en_o = 1'b0;
            mem_fifo_rdata_read_en_o = 1'b0;
            vs_element_cnt_o = 0;
            vd_element_cnt_o = 0;
            vd_wr_en_o = 1'b0;
            ap_graduate_o = 1'b0;
            queue_read_en = 1'b0;
        end 
    endcase
end


genvar n;
generate
    for(n = 0; n < LANES; n = n + 1) begin
        Address_Calculator #(
            .DATA_WIDTH(32),
            .IQUEUE_DEPTH(8),
            .LANES(4),
            .LANE_OFFSET(n)
            ) AC(
            .clk_i(clk_i),
            .resetn_i(resetn_i),
            .rs1_base_i(rs1_base_i),
            .rs2_stride_i(rs2_stride_i),
            .vs2_offset_i(vs2_offset_i[(DATA_WIDTH*(n+1))-1:(DATA_WIDTH*n)]),     
            .offset_term_sel_i(offset_term_sel),
            .base_term_sel_i(base_term_sel),
            .adder_reg_wen_i(adder_reg_wen),
            .addr_o(addr_o[(DATA_WIDTH*(n+1))-1:(DATA_WIDTH*n)])  
        );
    end
endgenerate


endmodule



module Address_Calculator #(
    parameter DATA_WIDTH = 32,
    parameter IQUEUE_DEPTH = 8,
    parameter LANES = 4,
    parameter LANE_OFFSET = 0,
    parameter ELEM_B = $clog2(LANES),
    parameter FU_WIDTH = DATA_WIDTH * LANES,
    parameter VECTOR_BURST_SIZE = FU_WIDTH/DATA_WIDTH
)(

    input                   clk_i,
    input                   resetn_i,
    //ADDRESS CALCULATION UNIT
    input [DATA_WIDTH-1:0]  rs1_base_i,
    input [DATA_WIDTH-1:0]  rs2_stride_i,
    input [DATA_WIDTH-1:0]  vs2_offset_i,     

    input [1:0]             offset_term_sel_i,
    input                   base_term_sel_i,
    input                   adder_reg_wen_i,

    output [DATA_WIDTH-1:0] addr_o
);

localparam MOP_UNIT = 2'b00;
localparam MOP_INDEX_UNORD = 2'b01;
localparam MOP_STRIDE = 2'b10;
localparam MOP_INDEX_ORD = 2'b11;

logic [DATA_WIDTH-1:0]  offset_term_mux;
logic [DATA_WIDTH-1:0]  base_term_mux;
logic [DATA_WIDTH-1:0]  adder_sum;

logic [DATA_WIDTH-1:0]  adder_reg_q;

assign addr_o = adder_reg_q;

always_comb begin : calculation_adder

    
    base_term_mux = offset_term_sel_i ? rs1_base_i : adder_reg_q;

    case (offset_term_sel_i)
        MOP_UNIT : offset_term_mux = 1<<2; //Word, so shifted by 2 bits left.
        MOP_INDEX_UNORD : offset_term_mux = vs2_offset_i;
        MOP_STRIDE : offset_term_mux = rs2_stride_i;
        MOP_INDEX_ORD : offset_term_mux = vs2_offset_i;
        default: offset_term_mux = 1;
    endcase

    adder_sum = base_term_mux + offset_term_mux + LANE_OFFSET;
end

always_ff @(posedge clk_i or negedge resetn_i) begin : adder_reg
    if(~resetn_i) adder_reg_q <= 0;
    else if(adder_reg_wen_i) adder_reg_q <= adder_sum;
end

endmodule


