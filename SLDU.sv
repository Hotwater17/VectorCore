module SLDU import vect_pkg::*; #(
    parameter DATA_WIDTH    =   32,
    parameter LANES         =   4,
    parameter VLEN          =   512,
    parameter ELEMS         =   VLEN/(DATA_WIDTH*LANES),

    localparam ELEM_N = VLEN/DATA_WIDTH, //16
    localparam ELEM_B = $clog2(ELEMS),
    localparam FU_WIDTH = DATA_WIDTH * LANES,
    localparam VECTOR_BURST_SIZE = FU_WIDTH/DATA_WIDTH

)(

    input                       clk_i,
    input                       resetn_i,
    input                       req_i,
    input  [DATA_WIDTH-1:0]     instr_i,
    output                      ready_o,

    //Element calculator    
    input  [DATA_WIDTH-1:0]     rs1_rdata_i, //Also used for scalar argument
    output reg [DATA_WIDTH-1:0] rd_wdata_o, //Scalar output
    output reg                  rd_wr_en_o,

    //Lane interface  
    input  [DATA_WIDTH-1:0]     lane_vs1_rdata_i    [0:LANES-1],
    input  [DATA_WIDTH-1:0]     lane_vs2_rdata_i    [0:LANES-1],
    input  [DATA_WIDTH-1:0]     lane_mask_rdata_i,
    output [DATA_WIDTH-1:0]     lane_vd_wdata_o     [0:LANES-1],
    output                      lane_vd_wr_en_o     [0:LANES-1],
    output [ELEM_B-1:0]         lane_vs1_elem_sel_o [0:LANES-1],  
    output [ELEM_B-1:0]         lane_vs2_elem_sel_o [0:LANES-1], //This is to chose element from lanes 
    output [ELEM_B-1:0]         lane_vd_elem_sel_o  [0:LANES-1]
);


logic [ELEM_B-1:0]      lane_vs1_elem_sel_vcom  [0:LANES-1];
logic [ELEM_B-1:0]      lane_vs2_elem_sel_vcom  [0:LANES-1];
logic [ELEM_B-1:0]      lane_vd_elem_sel_vcom   [0:LANES-1];

logic [DATA_WIDTH-1:0]  lane_vs1_rdata_vcom     [0:LANES-1];
logic [DATA_WIDTH-1:0]  lane_vs2_rdata_vcom     [0:LANES-1];
logic [DATA_WIDTH-1:0]  lane_vd_wdata_vcom      [0:LANES-1];
logic                   lane_vd_scalar_move;


logic lane_vd_wr_en_vcom [0:LANES-1];

logic [ELEM_B-1:0]      bus_mux     [0:LANES-1];
logic [DATA_WIDTH-1:0]  bus_vcom    [0:LANES-1];
logic [DATA_WIDTH-1:0]  rd_el0_reg;

arithm_instr_t instr_q;
logic   instr_pending;    

logic                       is_op_red;
logic   [DATA_WIDTH-1:0]    red_result_d;
logic   [DATA_WIDTH-1:0]    red_result_q;
logic                       instr_is_masked;
logic   [ELEMS-1:0]         elem_masked;
logic   [DATA_WIDTH-1:0]    mask_q;



typedef enum logic [2:0] {OP_SCALAR_MOVE, OP_SLIDE_UP, OP_SLIDE_DN, OP_GATHER, OP_RED /*OP_COMPRESS*/, OP_VMV, OP_INVALID} operation_t;
typedef enum logic  [1:0] {SLIDE_IDLE = 2'h0, SLIDE_READ = 2'h1, SLIDE_WRITE = 2'h2, SLIDE_NOP = 2'h3} slide_fsm_t;
operation_t operation;
slide_fsm_t slide_this_state, slide_next_state;
logic [ELEM_B-1:0] slide_elem_this_cnt, slide_elem_next_cnt;



assign lane_vs1_rdata_vcom  =   lane_vs1_rdata_i;
assign lane_vs2_rdata_vcom  =   lane_vs2_rdata_i;
assign lane_vd_wr_en_o      =   lane_vd_wr_en_vcom;
assign lane_vs1_elem_sel_o  =   lane_vs1_elem_sel_vcom;
assign lane_vs2_elem_sel_o  =   lane_vs2_elem_sel_vcom;
assign lane_vd_elem_sel_o   =   lane_vd_elem_sel_vcom;
assign instr_is_masked = !(instr_q.vm);






//Element calculator

enum logic [1:0]  {SLDU_OFF_UNIT, SLDU_OFF_SCALAR, SLDU_OFF_VECTOR, SLDU_OFF_IMM} offset_type;
logic [VECTOR_BURST_SIZE-1:0] elem_adder    [0:LANES-1];
logic [VECTOR_BURST_SIZE-1:0] elem_ff       [0:LANES-1];
logic [VECTOR_BURST_SIZE-1:0] elem_base;
logic [VECTOR_BURST_SIZE-1:0] elem_offset   [0:LANES-1];
logic [VECTOR_BURST_SIZE-1:0] lane_offset   [0:LANES-1];



genvar iCalc;
generate
        for(iCalc = 0; iCalc < LANES; iCalc = iCalc + 1) begin
            always_ff @(posedge clk_i or negedge resetn_i) begin : elemFF
                if(!resetn_i) elem_ff[iCalc] <= 0;
                else begin 
                    case(slide_this_state) 
                    /*
                        SLIDE_IDLE  :   elem_ff[iCalc] <= lane_offset[iCalc];
                        //SLIDE_IDLE  : elem_ff[iCalc] <=  (slide_next_state == SLIDE_READ) ?   lane_offset[iCalc]
                        //                                                                  :   lane_offset[iCalc] + elem_offset[iCalc];    
                        //SLIDE_READ  :   elem_ff[iCalc] <= elem_adder[iCalc];
                        SLIDE_READ  :   elem_ff[iCalc] <= lane_offset[iCalc];
                        SLIDE_WRITE :   elem_ff[iCalc] <= elem_adder[iCalc];
                        default     :   elem_ff[iCalc] <= lane_offset[iCalc]; 
                        */

                        SLIDE_IDLE  :   elem_ff[iCalc] <= 0;
                        SLIDE_READ,
                        SLIDE_WRITE :   elem_ff[iCalc] <= slide_elem_this_cnt;
                        default     :   elem_ff[iCalc] <= 0;   
                    endcase
                end
            end

            assign lane_offset[iCalc] = iCalc[1:0];
            //Be careful about element calculation. For even offsets the result can be shifted right 2 places (from 16 to 4).
            //But for vector offsets(gather, scatter) the offsets might be different for each element!
            //The elemenets need to be reordered.

            //###### SKIP VECTOR OFFSETS FOR NOW ######
            //###### SLIDE UP OR DOWN - ELEM OFFSET MUST BE POSITIVE OR NEGATIVE
            //###### PROBLEM: lane offset is accumulated. It should be added only once
            //###### SEEMS SOLVED ######
            //assign elem_adder[iCalc] = elem_offset[iCalc] + lane_offset[iCalc] + elem_ff[iCalc];

            /*assign elem_adder[iCalc] = (operation == OP_SLIDE_DN)   ? (lane_offset[iCalc] - elem_offset[iCalc] + (elem_ff[iCalc] * LANES)) 
                                                                    : (lane_offset[iCalc] + elem_offset[iCalc] + (elem_ff[iCalc] * LANES));
            */
            always_comb begin : adderLogic
                unique case(operation)
                    OP_SLIDE_DN : elem_adder[iCalc] = (lane_offset[iCalc] - elem_offset[iCalc] + (elem_ff[iCalc] * LANES));
                    OP_SLIDE_UP : elem_adder[iCalc] = (lane_offset[iCalc] + elem_offset[iCalc] + (elem_ff[iCalc] * LANES));
                    default : elem_adder[iCalc] = iCalc;
                endcase
            end

            assign lane_vs1_elem_sel_vcom[iCalc] = slide_elem_this_cnt;
            assign lane_vs2_elem_sel_vcom[iCalc] = slide_elem_this_cnt;

            //assign lane_vd_elem_sel_vcom[iCalc] = elem_adder[iCalc][VECTOR_BURST_SIZE-1:ELEM_B];
            //###### No, it should be bits 1:0 for lane select and 3:2 for element select  
            //assign lane_vd_elem_sel_vcom[iCalc] = elem_ff[iCalc][VECTOR_BURST_SIZE-1:ELEM_B];
            always_comb begin : offsetLogic
                unique case(offset_type)
                    SLDU_OFF_UNIT    :   elem_offset[iCalc] = 4'h1;
                    SLDU_OFF_SCALAR  :   elem_offset[iCalc] = rs1_rdata_i;
                    SLDU_OFF_VECTOR  :   elem_offset[iCalc] = lane_vs1_rdata_vcom[iCalc]; //Remember, you need to permutate the elements!
                    SLDU_OFF_IMM     :   elem_offset[iCalc] = {{27{1'b0}}, instr_q.vs1_rs1_imm};
                    default     :   elem_offset[iCalc] = 4'h1;
                endcase
            end
        end


endgenerate


//Decoder
    //Decode operation type
    //Decode offset type
    //Decode masking




always_ff @(posedge clk_i or negedge resetn_i) begin : instrFF
    if(!resetn_i) begin 
        instr_q <= '0;
        instr_pending <= 1'b0;
        mask_q <= '0;
    end
    else if(req_i) begin 
        instr_q <= instr_i;
        //Set instr pending flag if there was an instruction request
        instr_pending <= 1'b1;
    end
    else if(slide_this_state == SLIDE_READ) begin
         instr_pending <= 1'b0; 
         mask_q <= lane_mask_rdata_i;
    end
    //if(slide_this_state == SLIDE_READ) mask_q <= lane_mask_rdata_i; 
    //Clear instr pending flag when valid instruction is decoded and being executed 

end


always_comb begin : decoder
    if((instr_q.funct6 inside {VSLIDEUP, VSLIDEDOWN, VADC}) || is_op_red) begin
        if(instr_q.funct6 == VSLIDEUP) operation = OP_SLIDE_UP;
        else if(instr_q.funct6 == VSLIDEDOWN) operation =  OP_SLIDE_DN;
        else if(is_op_red) operation = OP_RED;
        else operation = OP_SCALAR_MOVE;

        unique case(instr_q.funct3)
            //OPIVV   :   offset_type = SLDU_OFF_VECTOR; //VECTOR CURRENTLY NOT SUPPORTED
            OPIVV   :   offset_type = SLDU_OFF_UNIT;
            OPIVI   :   offset_type = SLDU_OFF_IMM;
            OPIVX   :   offset_type = SLDU_OFF_SCALAR;
            OPMVV,
            OPMVX   :   offset_type = SLDU_OFF_UNIT;
            default :   offset_type = SLDU_OFF_UNIT;
        endcase
    end
    else begin
        operation = OP_INVALID;
        offset_type = SLDU_OFF_UNIT;
    end
end

//Controller
    //10010110001000001010001001010111 //vmul.vv v10,v2,v1 unmasked

    
    //Slide vreg elem_sel will only be used to read from Vs2.
    //For writes, there will be a separate element select, based on element calculation

    //Which lane? depending on vector/scalar, only some of lanes may be written to

    //Either all of them for vector or lane 0 for scalar

    //Modify here for reduction
    assign lane_vd_wr_en_vcom[0] = ((slide_this_state == SLIDE_WRITE) && 
                                    !((operation == OP_SCALAR_MOVE) && (instr_q.funct3 == OPMVV)) &&
                                    !(is_op_red && (slide_elem_this_cnt != 0)));
    genvar iWren;
    generate
        for(iWren = 1; iWren < LANES; iWren = iWren + 1) begin
            //###### Possibly not in read
            //Disable when there is a scalar write to rd
            //Also, enable in scalar read to vd only for 1st element
            assign lane_vd_wr_en_vcom[iWren] = ((slide_this_state == SLIDE_WRITE) && !(operation == OP_SCALAR_MOVE) && !(operation == OP_RED));
            //assign lane_vd_wr_en_vcom[iWren] = ((slide_this_state == SLIDE_WRITE) || (slide_this_state == SLIDE_READ));
        end
    endgenerate

    assign ready_o = ((slide_this_state == SLIDE_WRITE) && (slide_elem_this_cnt == 0));

    
    //FSM
    /*
    if(operation == OP_SCALAR_MOVE) begin
        //Select 
        //Select what?
    end
*/
    always_comb begin : slideStateLogic
        unique case(slide_this_state)
            //###### Change here - after A NEW slide instruction is DECODED PROPERLY, go to read
            SLIDE_IDLE : slide_next_state = ((operation != OP_INVALID) && (instr_pending)) ? SLIDE_READ : SLIDE_IDLE;
            //SLIDE_READ : slide_next_state = (slide_elem_this_cnt == 0) ? SLIDE_WRITE : SLIDE_READ;
            //SLIDE_READ : slide_next_state = (slide_elem_this_cnt == (LANES-1)) ? SLIDE_IDLE : SLIDE_READ;
            //Modify here for reduction - wait for reduction to be completed 
            SLIDE_READ  : slide_next_state = SLIDE_WRITE;
            //SLIDE_WRITE : slide_next_state = (slide_elem_this_cnt == (LANES-1)) ? SLIDE_IDLE : SLIDE_WRITE;
            SLIDE_WRITE : slide_next_state = (slide_elem_this_cnt == 0) ? SLIDE_IDLE : SLIDE_WRITE;
            default : slide_next_state = SLIDE_IDLE;
            
        endcase
    end

    always_comb begin : slideCntLogic
        unique case(slide_this_state)
            //###### Count from 0
            //SLIDE_IDLE : slide_elem_next_cnt = (operation == OP_SCALAR_MOVE) ? 0 : LANES-1;
            SLIDE_IDLE : slide_elem_next_cnt = 0;
            SLIDE_READ : slide_elem_next_cnt = slide_elem_this_cnt + 1; //Scalar move will have less cycles
            //SLIDE_WRITE : slide_elem_next_cnt = (operation == OP_SCALAR_MOVE) ? (LANES-1) : slide_elem_this_cnt + 1;
            SLIDE_WRITE : slide_elem_next_cnt = (operation == OP_SCALAR_MOVE) ? 0 : slide_elem_this_cnt + 1;
            default : slide_elem_next_cnt = 0;
        endcase
    end

    always_ff @(posedge clk_i or negedge resetn_i) begin : slideFSM
        if(!resetn_i) begin 
            slide_this_state <= SLIDE_IDLE; 
            slide_elem_this_cnt <= 0;
        end
        else begin 
            slide_this_state <= slide_next_state; 
            slide_elem_this_cnt <= slide_elem_next_cnt;
        end
    end


//Element control MUX
//This multiplexer selects SOURCE LANE to a specific DESTINATION LANE. 
//This means that every DESTINATION LANE can get an element from ANY SOURCE LANE.
//A specific element in that lane will be selected using ELEMENT COUNTER.






genvar iMux;
generate
    for(iMux = 0; iMux < LANES; iMux = iMux + 1) begin
            //But this has to be controlled independently !!!
            //This means that index of vreg_array(which is irrelevant btw, should be bus),
            //...should be independent based on lane number calculated in element calculator
            //0,4,8,12 - Lane 0
            //1,5,9,13 - Lane 1
            //2,6,10,14 - Lane 2
            //3,7,11,15 - Lane 3
            //Take note 
        assign bus_mux[iMux] = elem_adder[iMux][ELEM_B-1:0];    

        //assign lane_vd_wdata_vcom[iMux] = bus_vcom[bus_mux[iMux]];
        
    end
endgenerate

/*
    I really wish I didn't need to do this.
    But I haven't had any better idea, nothing else worked. 
*/
always_comb begin : mux
    case({bus_mux[0], bus_mux[1], bus_mux[2], bus_mux[3]}) 
    {2'h0,2'h1,2'h2,2'h3}   :   begin
        lane_vd_wdata_vcom[0] = bus_vcom[0];
        lane_vd_wdata_vcom[1] = bus_vcom[1];
        lane_vd_wdata_vcom[2] = bus_vcom[2];
        lane_vd_wdata_vcom[3] = bus_vcom[3];

        lane_vd_elem_sel_vcom[0] = elem_adder[0][VECTOR_BURST_SIZE-1:ELEM_B];
        lane_vd_elem_sel_vcom[1] = elem_adder[1][VECTOR_BURST_SIZE-1:ELEM_B];
        lane_vd_elem_sel_vcom[2] = elem_adder[2][VECTOR_BURST_SIZE-1:ELEM_B];
        lane_vd_elem_sel_vcom[3] = elem_adder[3][VECTOR_BURST_SIZE-1:ELEM_B];

    end
    {2'h1,2'h2,2'h3,2'h0}   :   begin
        /*
        lane_vd_wdata_vcom[0] = bus_vcom[3];
        lane_vd_wdata_vcom[1] = bus_vcom[0];
        lane_vd_wdata_vcom[2] = bus_vcom[2];
        lane_vd_wdata_vcom[3] = bus_vcom[1];

        lane_vd_elem_sel_vcom[0] = elem_adder[3][VECTOR_BURST_SIZE-1:ELEM_B];
        lane_vd_elem_sel_vcom[1] = elem_adder[0][VECTOR_BURST_SIZE-1:ELEM_B];
        lane_vd_elem_sel_vcom[2] = elem_adder[2][VECTOR_BURST_SIZE-1:ELEM_B];
        lane_vd_elem_sel_vcom[3] = elem_adder[1][VECTOR_BURST_SIZE-1:ELEM_B];
        */

        //Seems that here it should be 3012 not 3021
        lane_vd_wdata_vcom[0] = bus_vcom[3];
        lane_vd_wdata_vcom[1] = bus_vcom[0];
        lane_vd_wdata_vcom[2] = bus_vcom[1];
        lane_vd_wdata_vcom[3] = bus_vcom[2];

        lane_vd_elem_sel_vcom[0] = elem_adder[3][VECTOR_BURST_SIZE-1:ELEM_B];
        lane_vd_elem_sel_vcom[1] = elem_adder[0][VECTOR_BURST_SIZE-1:ELEM_B];
        lane_vd_elem_sel_vcom[2] = elem_adder[1][VECTOR_BURST_SIZE-1:ELEM_B];
        lane_vd_elem_sel_vcom[3] = elem_adder[2][VECTOR_BURST_SIZE-1:ELEM_B];
    end
    {2'h2,2'h3,2'h0,2'h1}   :   begin
        lane_vd_wdata_vcom[0] = bus_vcom[2];
        lane_vd_wdata_vcom[1] = bus_vcom[3];
        lane_vd_wdata_vcom[2] = bus_vcom[0];
        lane_vd_wdata_vcom[3] = bus_vcom[1];

        lane_vd_elem_sel_vcom[0] = elem_adder[2][VECTOR_BURST_SIZE-1:ELEM_B];
        lane_vd_elem_sel_vcom[1] = elem_adder[3][VECTOR_BURST_SIZE-1:ELEM_B];
        lane_vd_elem_sel_vcom[2] = elem_adder[0][VECTOR_BURST_SIZE-1:ELEM_B];
        lane_vd_elem_sel_vcom[3] = elem_adder[1][VECTOR_BURST_SIZE-1:ELEM_B];
    end
    {2'h3,2'h0,2'h1,2'h2}   :   begin
        lane_vd_wdata_vcom[0] = bus_vcom[1];
        lane_vd_wdata_vcom[1] = bus_vcom[2];
        lane_vd_wdata_vcom[2] = bus_vcom[3];
        lane_vd_wdata_vcom[3] = bus_vcom[0];

        lane_vd_elem_sel_vcom[0] = elem_adder[1][VECTOR_BURST_SIZE-1:ELEM_B];
        lane_vd_elem_sel_vcom[1] = elem_adder[2][VECTOR_BURST_SIZE-1:ELEM_B];
        lane_vd_elem_sel_vcom[2] = elem_adder[3][VECTOR_BURST_SIZE-1:ELEM_B];
        lane_vd_elem_sel_vcom[3] = elem_adder[0][VECTOR_BURST_SIZE-1:ELEM_B];
    end 
    default     :   begin
        lane_vd_wdata_vcom[0] = bus_vcom[0];
        lane_vd_wdata_vcom[1] = bus_vcom[1];
        lane_vd_wdata_vcom[2] = bus_vcom[2];
        lane_vd_wdata_vcom[3] = bus_vcom[3];

        lane_vd_elem_sel_vcom[0] = elem_adder[0][VECTOR_BURST_SIZE-1:ELEM_B];
        lane_vd_elem_sel_vcom[1] = elem_adder[1][VECTOR_BURST_SIZE-1:ELEM_B];
        lane_vd_elem_sel_vcom[2] = elem_adder[2][VECTOR_BURST_SIZE-1:ELEM_B];
        lane_vd_elem_sel_vcom[3] = elem_adder[3][VECTOR_BURST_SIZE-1:ELEM_B];
    end
    endcase
end

genvar iBus;
generate
    for(iBus = 0; iBus < LANES; iBus = iBus + 1) begin
        assign bus_vcom[iBus] = lane_vs2_rdata_vcom[iBus];
    end
endgenerate


//Scalar path
always_comb begin : scalarCtrl
    //Write scalar operand to scalar RF during READ - vmv.x.s
    rd_wr_en_o = (((operation == OP_SCALAR_MOVE) && (instr_q.funct3 == OPMVV)) && 
                (slide_elem_this_cnt == 0) && (slide_this_state == SLIDE_WRITE));
    rd_wdata_o = rd_el0_reg;
    //Switch between RS1(scalar operand) and data from lane 0 during WRITE - vmv.s.x
    //bus_lane_0_scal_vect_mux = ((operation == OP_SCALAR_MOVE) && (instr_q.funct3 == OPMVX)) ? rs1_rdata_i : lane_vs2_rdata_vcom[0];
    lane_vd_scalar_move = ((operation == OP_SCALAR_MOVE) && (instr_q.funct3 == OPMVX));
end

always_ff @(posedge clk_i or negedge resetn_i) begin : el0Reg
    if(!resetn_i) rd_el0_reg <= '0;
    //Modify here for reduction
    else if((operation == OP_SCALAR_MOVE) && (instr_q.funct3 == OPMVV) && (slide_elem_this_cnt == 0)) rd_el0_reg <= bus_vcom[0];
end


genvar iVD;
generate
    for(iVD = 1; iVD < LANES; iVD = iVD + 1) begin
        assign lane_vd_wdata_o[iVD]      =   lane_vd_wdata_vcom[iVD];
    end
endgenerate
//Modify here for reduction
assign lane_vd_wdata_o[0] = lane_vd_scalar_move ? rs1_rdata_i : is_op_red ? red_result_d : lane_vd_wdata_vcom[0];


assign is_op_red = ((instr_q.funct6 inside {VADD_VREDSUM, VREDAND, VSUB_VREDOR, VRSUB_VREDXOR, 
                        VMINU_VREDMINU, VMIN_VREDMIN, VMAXU_VREDMAXU, VMAX_VREDMAX}) && (instr_q.funct3 == OPMVV));

genvar iMask;
generate 
    for(iMask = 0; iMask < LANES; iMask = iMask + 1) assign elem_masked[iMask] = (instr_is_masked && ~mask_q[{slide_elem_this_cnt, iMask[1:0]}]);
endgenerate
always_comb begin : redLogic
    unique case (instr_q.funct6)
       VADD_VREDSUM     :   red_result_d = (red_result_q + (elem_masked[0] ? '0 : bus_vcom[0]) + (elem_masked[1] ? '0 : bus_vcom[1]) + (elem_masked[2] ? '0 : bus_vcom[2]) + (elem_masked[3] ? '0 : bus_vcom[3]));  
       VREDAND          :   red_result_d = (red_result_q & bus_vcom[0] & bus_vcom[1] & bus_vcom[2] & bus_vcom[3]);
       VSUB_VREDOR      :   red_result_d = (red_result_q | bus_vcom[0] | bus_vcom[1] | bus_vcom[2] | bus_vcom[3]);
       VRSUB_VREDXOR    :   red_result_d = (red_result_q ^ bus_vcom[0] ^ bus_vcom[1] ^ bus_vcom[2] ^ bus_vcom[3]);
       //VMINU_VREDMINU   :   red_result_d  = (red_result_q + bus_vcom[0] + bus_vcom[1] + bus_vcom[2] + bus_vcom[3]);
       //VMIN_VREDMIN     :   red_result_d  = 
       //VMAXU_VREDMAXU   :   red_result_d  = 
       //VMAX_VREDMAX     :   red_result_d  = 
       default          :   red_result_d = '0;
    endcase      
end

always_ff @(posedge clk_i or negedge resetn_i) begin : redFSM
    if(!resetn_i) red_result_q <= '0;
    else if(is_op_red) begin
        if(slide_this_state == SLIDE_READ) red_result_q <= '0;
        else if(slide_this_state == SLIDE_WRITE) red_result_q <= red_result_d;
    end
end

endmodule

