
module rvv_core #(
    parameter DATA_WIDTH = 32,
    parameter RESET_VECTOR = 32'h00000000
)(
    
input               clk_i,
input               resetn_i,

output                          hclk_o,
output                          hresetn_o,
output reg  [DATA_WIDTH-1:0]    haddr_o, 
input       [DATA_WIDTH-1:0]    hrdata_i,
output reg  [DATA_WIDTH-1:0]    hwdata_o,
output reg  [2:0]               hsize_o,
output reg                      hwrite_o,
input                           hready_i, 
input       [1:0]               hresp_i 


);

typedef enum logic [2:0] {HSIZE_BYTE = 3'b000, HSIZE_HALFWORD = 3'b001, HSIZE_WORD = 3'b010} hsize_t;

logic [DATA_WIDTH-1:0]  vect_rs1_rdata;
logic [DATA_WIDTH-1:0]  vect_rs2_rdata;
logic [DATA_WIDTH-1:0]  vect_rd_wdata;
logic [DATA_WIDTH-1:0]  vect_instr;
logic                   vect_iq_full;
logic                   vect_ack;
logic                   vect_lsu_active;
logic                   vect_rf_wr_en;
logic                   vect_ready;
logic                   vect_req;


typedef enum logic {BUS_SCALAR, BUS_VECTOR} bus_arb_e;
bus_arb_e               bus_select;




assign hclk_o = clk_i;
assign hresetn_o = resetn_i;

logic   [DATA_WIDTH-1:0]    v_haddr; 
logic   [DATA_WIDTH-1:0]    v_hrdata;
logic   [DATA_WIDTH-1:0]    v_hwdata;
hsize_t                     v_hsize; 
logic                       v_hwrite;
logic                       v_hready;
logic   [1:0]               v_hresp; 


logic   [DATA_WIDTH-1:0]    s_haddr; 
logic   [DATA_WIDTH-1:0]    s_hrdata;
logic   [DATA_WIDTH-1:0]    s_hwdata;
hsize_t                     s_hsize; 
logic                       s_hwrite;
logic                       s_hready;
logic   [1:0]               s_hresp; 


core_ahb #(
    .DATA_WIDTH(32),
    .RESET_VECTOR(RESET_VECTOR)
) SCALAR(
.clk_i(clk_i),
.reset_i(resetn_i),
.vect_req_o(vect_req),
.vect_ack_i(vect_ack),
.vect_ready_i(vect_ready),
.vect_iq_full_i(vect_iq_full),
.vect_lsu_active_i(vect_lsu_active),
.vect_instr_o(vect_instr),
.vect_rf_wr_en_i(vect_rf_wr_en),
.vect_rd_wdata_i(vect_rd_wdata),
.vect_rs1_rdata_o(vect_rs1_rdata),
.vect_rs2_rdata_o(vect_rs2_rdata),
.haddr_o(s_haddr), 
.hrdata_i(s_hrdata),
.hwdata_o(s_hwdata),
.hsize_o(s_hsize),
.hwrite_o(s_hwrite),
.hready_i(s_hready), 
.hresp_i(s_hresp) 
    
);

Vector_Core #(
    .DATA_WIDTH(32),
    .REG_NUM(32)
) VECTOR(
.clk_i(clk_i),
.resetn_i(resetn_i),
.vinstr_i(vect_instr),
.rs1_i(vect_rs1_rdata),
.rs2_i(vect_rs2_rdata),
.vreq_i(vect_req),
.v_iq_ack_o(vect_ack),
.vready_o(vect_ready),
.v_iq_full_o(vect_iq_full),
.v_lsu_active_o(vect_lsu_active),
.rd_o(vect_rd_wdata),
.rd_wr_en_o(vect_rf_wr_en),
.haddr_o(v_haddr), 
.hrdata_i(v_hrdata),
.hwdata_o(v_hwdata),
.hsize_o(v_hsize),
.hwrite_o(v_hwrite),
.hready_i(v_hready), 
.hresp_i(v_hresp) 
);



//AHB arbiter
always_ff @(posedge clk_i) begin : arbiterFSM
    if(!resetn_i) bus_select <= BUS_SCALAR;
    else begin
        //Give control over bus to vector ahb if vector request
        if(vect_req) bus_select <= BUS_VECTOR; 
        //Give control back to scalar if vector instruction finished
        else if(vect_ready) bus_select <= BUS_SCALAR;
    end
end

always_comb begin : arbiterLogic
    if(bus_select == BUS_SCALAR) begin
        haddr_o   =   s_haddr;
        hwdata_o  =   s_hwdata;
        hsize_o   =   s_hsize;
        hwrite_o  =   s_hwrite;
    end
    else begin //Vector
        haddr_o   =   v_haddr;
        hwdata_o  =   v_hwdata;
        hsize_o   =   v_hsize;
        hwrite_o  =   v_hwrite;
    end
end

assign  s_hrdata =   hrdata_i;
assign  s_hready =   hready_i;
assign  s_hresp  =   hresp_i;

assign  v_hrdata =   hrdata_i;
assign  v_hready =   hready_i;
assign  v_hresp  =   hresp_i;

endmodule
