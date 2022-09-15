module VRF #(
    parameter DATA_WIDTH = 32,
    parameter REG_NUM = 32,
    parameter LANES = 4,
    parameter VLEN = 512,

    localparam PARTITION_B = VLEN/LANES,
    localparam ADDR_B = $clog2(REG_NUM),
    localparam ELEM_B = $clog2(LANES)
)(
    //Common signals
    input                           clk_i,
    input                           resetn_i,

    //VRF ports    
    input       [ADDR_B-1:0]        a_addr_i,
    input       [ADDR_B-1:0]        b_addr_i,
    input       [ADDR_B-1:0]        c_addr_i,
    input       [ADDR_B-1:0]        wr_addr_i,

                 
    input       [ELEM_B-1:0]        rd_elem_cnt_i,
    input       [ELEM_B-1:0]        wr_elem_cnt_i,

    input                           wr_req_i,
    input                           wr_en_i,
    input                           wr_ready_i,
    input       [DATA_WIDTH-1:0]    wdata_i,

    input                           rd_req_i,
    input                           is_c_used_i,
    output                          rd_op_ready_o,

    output  reg [DATA_WIDTH-1:0]    a_rdata_o,
    output  reg [DATA_WIDTH-1:0]    b_rdata_o,
    output  reg [DATA_WIDTH-1:0]    c_rdata_o,

    output      [DATA_WIDTH-1:0]    mask_rdata_o

);


logic   [DATA_WIDTH-1:0]    a_reg       [0:LANES-1];
logic   [DATA_WIDTH-1:0]    b_reg       [0:LANES-1];
logic   [DATA_WIDTH-1:0]    c_reg       [0:LANES-1];

logic                       a_rd_en;
logic                       b_rd_en;
logic                       c_rd_en;


logic   [DATA_WIDTH-1:0]    rf_rdata    [0:LANES-1];
logic                       rf_wr_en    [0:LANES-1];
logic                       rf_rd_en;

logic   [ADDR_B-1:0]        rf_rd_addr;

enum logic [1:0]    {RD_IDLE, RD_A, RD_B, RD_C} rd_this_state, rd_next_state;                      
enum logic          {WR_IDLE, WR_EN}            wr_this_state, wr_next_state;  

assign  a_rdata_o   =   a_reg[rd_elem_cnt_i];
assign  b_rdata_o   =   b_reg[rd_elem_cnt_i];
assign  c_rdata_o   =   c_reg[rd_elem_cnt_i];

assign  a_rd_en     =   (rd_this_state == RD_A);
assign  b_rd_en     =   (rd_this_state == RD_B);
assign  c_rd_en     =   (rd_this_state == RD_C);

assign  rf_rd_en    =   !(((rd_this_state == RD_IDLE) && rd_req_i) || (rd_this_state == RD_A) || (rd_this_state == RD_B));
    

//Maybe also one cycle LATER?
//Or, in case of independent writes, when next/this state is RD_IDLE
assign  rd_op_ready_o   =   (rd_next_state == RD_IDLE); 

always_comb begin : addrSel
    
    case (rd_this_state)
        RD_IDLE  :   rf_rd_addr  =   a_addr_i;
        RD_A     :   rf_rd_addr  =   b_addr_i;
        RD_B     :   rf_rd_addr  =   is_c_used_i ? c_addr_i : a_addr_i;
        RD_C     :   rf_rd_addr  =   a_addr_i;
        default  :   rf_rd_addr  =   a_addr_i; 
    endcase

end

always_comb begin : rdLogic
    case (rd_this_state)
        RD_IDLE :   rd_next_state   =   rd_req_i ? RD_A     :   RD_IDLE;
        RD_A    :   rd_next_state   =   RD_B;
        RD_B    :   rd_next_state   =   is_c_used_i ? RD_C  :   RD_IDLE;
        RD_C    :   rd_next_state   =   RD_IDLE;
        default :   rd_next_state   =   RD_IDLE; 
    endcase
end

always_ff @(posedge clk_i or negedge resetn_i) begin : rdFSM
    if(!resetn_i)   rd_this_state   <=  RD_IDLE;
    else            rd_this_state   <=  rd_next_state;
end

always_comb begin : wrLogic
    case (wr_this_state)
        WR_IDLE :   wr_next_state   =   wr_req_i    ?   WR_EN   :   WR_IDLE;
        WR_EN   :   wr_next_state   =   wr_ready_i  ?   WR_IDLE :   WR_EN;
        default :   wr_next_state   =   WR_IDLE; 
    endcase
end

always_ff @(posedge clk_i or negedge resetn_i) begin : wrFSM
    if(!resetn_i)   begin 
        wr_this_state   <=  WR_IDLE;
    end
    else            begin
        wr_this_state   <=  wr_next_state;
    end
end

//Mask??

genvar iBank;

generate
    for(iBank = 0; iBank < LANES; iBank = iBank + 1) begin : BANK
        TS6N65LPLLA32X32M4F RF_BLOCK
        (
            .AA(wr_addr_i),
            .D(wdata_i),
            .BWEB(0), //Bit-write enable
            .WEB(rf_wr_en[iBank]),
            .CLKW(clk_i),
            .AB(rf_rd_addr),
            .REB(rf_rd_en),
            .CLKR(clk_i),
            //BIST 
            .AMA(5'b0),
            .DM(32'b1),
            .BWEBM(32'b1),
            .WEBM(1'b1),
            .AMB(5'b0),
            .REBM(1'b1),
            .BIST(1'b0),
            .Q(rf_rdata[iBank])
        );


    always_ff @(posedge clk_i or negedge resetn_i) begin : reg_FF
        if(!resetn_i) begin
            a_reg[iBank]  <=  '0;
            b_reg[iBank]  <=  '0;
            c_reg[iBank]  <=  '0;
        end
        else begin
            if(a_rd_en)   a_reg[iBank]  <=  rf_rdata[iBank];
            if(b_rd_en)   b_reg[iBank]  <=  rf_rdata[iBank];
            if(c_rd_en)   c_reg[iBank]  <=  rf_rdata[iBank];
        end
    end

    always_comb begin : wr_en
        rf_wr_en[iBank]   =   !(wr_en_i && (wr_elem_cnt_i == iBank) && (wr_this_state == WR_EN));
    end

    end
endgenerate




endmodule