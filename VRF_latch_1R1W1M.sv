module VRF_latch #(
    parameter DATA_WIDTH    =   32,
    parameter REG_NUM       =   32,
    parameter LANES         =   4,
    parameter VLEN          =   512,
    parameter ELEMS         =   VLEN/(LANES*DATA_WIDTH),

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

    input                           is_mask_used_i,
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

logic   [DATA_WIDTH-1:0]    v_reg       [0:REG_NUM-1][0:LANES-1];
logic   [DATA_WIDTH-1:0]    m_reg;

logic                       mask_wr_en;

enum logic [1:0]    {RD_IDLE, RD_A, RD_B, RD_C} rd_this_state, rd_next_state;                      
enum logic          {WR_IDLE, WR_EN}            wr_this_state, wr_next_state;  

assign  a_rdata_o   =   a_reg[rd_elem_cnt_i];
assign  b_rdata_o   =   b_reg[rd_elem_cnt_i];
assign  c_rdata_o   =   c_reg[rd_elem_cnt_i];

assign  a_rd_en     =   (rd_this_state == RD_A);
assign  b_rd_en     =   (rd_this_state == RD_B);
assign  c_rd_en     =   (rd_this_state == RD_C);

assign  rf_rd_en    =   !(((rd_this_state == RD_IDLE) && rd_req_i) || (rd_this_state == RD_A) || (rd_this_state == RD_B));
    
assign  mask_wr_en  =   ((wr_addr_i == 0) && (wr_elem_cnt_i == 0));
assign  mask_rdata_o =  is_mask_used_i ? m_reg : '0;

//Maybe also one cycle LATER?
//Or, in case of independent writes, when next/this state is RD_IDLE
assign  rd_op_ready_o   =   ((rd_next_state == RD_IDLE) && (rd_this_state != RD_IDLE)); 

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

//Mask

always_latch begin : maskLatch
    if(!resetn_i) m_reg <= '0;
    else if(mask_wr_en) m_reg <= wdata_i;
end


always_latch begin : rfLatch
    if(!resetn_i) begin
        v_reg[0][0] <= 0;   v_reg[0][1] <= 0;   v_reg[0][2] <= 0;   v_reg[0][3] <= 0;
        v_reg[1][0] <= 0;   v_reg[1][1] <= 0;   v_reg[1][2] <= 0;   v_reg[1][3] <= 0;
        v_reg[2][0] <= 0;   v_reg[2][1] <= 0;   v_reg[2][2] <= 0;   v_reg[2][3] <= 0;
        v_reg[3][0] <= 0;   v_reg[3][1] <= 0;   v_reg[3][2] <= 0;   v_reg[3][3] <= 0;
        v_reg[4][0] <= 0;   v_reg[4][1] <= 0;   v_reg[4][2] <= 0;   v_reg[4][3] <= 0;
        v_reg[5][0] <= 0;   v_reg[5][1] <= 0;   v_reg[5][2] <= 0;   v_reg[5][3] <= 0;
        v_reg[6][0] <= 0;   v_reg[6][1] <= 0;   v_reg[6][2] <= 0;   v_reg[6][3] <= 0;
        v_reg[7][0] <= 0;   v_reg[7][1] <= 0;   v_reg[7][2] <= 0;   v_reg[7][3] <= 0;
        v_reg[8][0] <= 0;   v_reg[8][1] <= 0;   v_reg[8][2] <= 0;   v_reg[8][3] <= 0;
        v_reg[9][0] <= 0;   v_reg[9][1] <= 0;   v_reg[9][2] <= 0;   v_reg[9][3] <= 0;
        v_reg[10][0] <= 0;  v_reg[10][1] <= 0;  v_reg[10][2] <= 0;  v_reg[10][3] <= 0;
        v_reg[11][0] <= 0;  v_reg[11][1] <= 0;  v_reg[11][2] <= 0;  v_reg[11][3] <= 0;
        v_reg[12][0] <= 0;  v_reg[12][1] <= 0;  v_reg[12][2] <= 0;  v_reg[12][3] <= 0;
        v_reg[13][0] <= 0;  v_reg[13][1] <= 0;  v_reg[13][2] <= 0;  v_reg[13][3] <= 0;
        v_reg[14][0] <= 0;  v_reg[14][1] <= 0;  v_reg[14][2] <= 0;  v_reg[14][3] <= 0;
        v_reg[15][0] <= 0;  v_reg[15][1] <= 0;  v_reg[15][2] <= 0;  v_reg[15][3] <= 0;
        v_reg[16][0] <= 0;  v_reg[16][1] <= 0;  v_reg[16][2] <= 0;  v_reg[16][3] <= 0;
        v_reg[17][0] <= 0;  v_reg[17][1] <= 0;  v_reg[17][2] <= 0;  v_reg[17][3] <= 0;
        v_reg[18][0] <= 0;  v_reg[18][1] <= 0;  v_reg[18][2] <= 0;  v_reg[18][3] <= 0;
        v_reg[19][0] <= 0;  v_reg[19][1] <= 0;  v_reg[19][2] <= 0;  v_reg[19][3] <= 0;
        v_reg[20][0] <= 0;  v_reg[20][1] <= 0;  v_reg[20][2] <= 0;  v_reg[20][3] <= 0;
        v_reg[21][0] <= 0;  v_reg[21][1] <= 0;  v_reg[21][2] <= 0;  v_reg[21][3] <= 0;
        v_reg[22][0] <= 0;  v_reg[22][1] <= 0;  v_reg[22][2] <= 0;  v_reg[22][3] <= 0;
        v_reg[23][0] <= 0;  v_reg[23][1] <= 0;  v_reg[23][2] <= 0;  v_reg[23][3] <= 0;
        v_reg[24][0] <= 0;  v_reg[24][1] <= 0;  v_reg[24][2] <= 0;  v_reg[24][3] <= 0;
        v_reg[25][0] <= 0;  v_reg[25][1] <= 0;  v_reg[25][2] <= 0;  v_reg[25][3] <= 0;
        v_reg[26][0] <= 0;  v_reg[26][1] <= 0;  v_reg[26][2] <= 0;  v_reg[26][3] <= 0;
        v_reg[27][0] <= 0;  v_reg[27][1] <= 0;  v_reg[27][2] <= 0;  v_reg[27][3] <= 0;
        v_reg[28][0] <= 0;  v_reg[28][1] <= 0;  v_reg[28][2] <= 0;  v_reg[28][3] <= 0;
        v_reg[29][0] <= 0;  v_reg[29][1] <= 0;  v_reg[29][2] <= 0;  v_reg[29][3] <= 0;
        v_reg[30][0] <= 0;  v_reg[30][1] <= 0;  v_reg[30][2] <= 0;  v_reg[30][3] <= 0;
        v_reg[31][0] <= 0;  v_reg[31][1] <= 0;  v_reg[31][2] <= 0;  v_reg[31][3] <= 0;

    end
    else if(wr_en_i) v_reg[wr_addr_i][wr_elem_cnt_i] <= wdata_i;
end
    
genvar iBank;

generate
    for(iBank = 0; iBank < LANES; iBank = iBank + 1) begin : BANK


    always_latch  begin : regLatch
        if(!resetn_i) begin
            a_reg[iBank]  <=  '0;
            b_reg[iBank]  <=  '0;
            c_reg[iBank]  <=  '0;
        end
        else begin
            if(a_rd_en)   a_reg[iBank]  <=  v_reg[a_addr_i][iBank];
            if(b_rd_en)   b_reg[iBank]  <=  v_reg[b_addr_i][iBank];
            if(c_rd_en)   c_reg[iBank]  <=  v_reg[c_addr_i][iBank];
        end

    end

    always_comb begin : wr_en
        //Try changing this to also include next state == WR_EN
        rf_wr_en[iBank]   =   !(wr_en_i && (wr_elem_cnt_i == iBank) && (wr_this_state == WR_EN));
    end

    end
endgenerate

task show;   //{ USAGE: inst.show (low, high);
   input [31:0] low, high;
   integer i;
   integer e;
   begin //{
   $display ("\n%m: RF content dump");
   if (low < 0 || low > high || high >= REG_NUM)
      $display ("Error! Invalid address range (%0d, %0d).", low, high,
                "\nUsage: %m (low, high);",
                "\n       where low >= 0 and high <= %0d.", REG_NUM-1);
   else
      begin
      $display ("VREG \t E0 \t E1 \t E2 \t E3");
      for (i = low ; i <= high ; i = i + 1) begin
        //$display ("%d\t%b", i, mem[i]);
        $write("\n V%d \t", i);
         for(e = 0; e < ELEMS; e = e + 1)
            $write("%d \t", v_reg[i][e]);
      end

      end
      $write("\n");
   end //}
endtask //}


endmodule
