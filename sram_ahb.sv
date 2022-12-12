module sram_ahb #(
    parameter DATA_WIDTH = 32
)(
    input           clk_i,
    input           resetn_i,

input                           hclk_i,
input                           hresetn_i,
input       [DATA_WIDTH-1:0]    haddr_i, 
output reg  [DATA_WIDTH-1:0]    hrdata_o,
input       [DATA_WIDTH-1:0]    hwdata_i,
input       [2:0]               hsize_i,
input                           hwrite_i,
output reg                      hready_o, 
output reg  [1:0]               hresp_o,
input                           hsel_i 
);


logic   [1:0]   sram_fsm;
logic           is_write;

logic   [DATA_WIDTH-1:0]    sram_rdata;
logic   [DATA_WIDTH-1:0]    sram_wdata;
logic   [DATA_WIDTH-1:0]    sram_addr;

logic   sram_wen;   
logic   sram_cen;

always_ff @(negedge hclk_i or negedge hresetn_i) begin : memFSM
    if(!hresetn_i) begin
        sram_fsm <= 2'b00;
        is_write <= 1'b0;
        sram_addr <= '0;
    end
    else begin
        //Incomplete
        if(sram_fsm != 2'b11 && hsel_i) sram_fsm <= sram_fsm + 1;
        else sram_fsm <= 2'b00;

        if(sram_fsm == 2'b01) sram_addr <= haddr_i;
        //or can be: if(hsel_i && (sram_fsm == 2'b00)) sram_addr <= haddr_i; 
        is_write <= (sram_fsm == 2'b01) && hwrite_i; 

    end
end

always_ff @(posedge hclk_i or negedge hresetn_i) begin : readyFSM
    if(!hresetn_i) hready_o <= 1'b0;
    else hready_o <= (sram_fsm == 2'b11);
        
end

always_comb begin : memLogic
    //hready_o = (sram_fsm == 2'b11);

    sram_cen = ~(sram_fsm == 2'b10);
    sram_wen = ~((sram_fsm == 2'b10) && is_write);

end


//assign sram_addr = haddr_i;
assign sram_wdata = hwdata_i;
assign hrdata_o = sram_rdata; 

TSDN65LPLLA4096X32M8M SRAM(
.AA(sram_addr[13:2]),
.DA(sram_wdata),
.BWEBA('0),
.WEBA(sram_wen),
.CEBA(sram_cen),
.CLKA(clk_i),
.AB('0),
.DB('0),
.BWEBB('1),
.WEBB(1'b1),
.CEBB(1'b1),
.CLKB(1'b0),
.QA(sram_rdata),
.QB()
);

/*
sram32k SRAM(
    .Q(sram_rdata), 
    .CLK(clk_i), 
    .CEN(sram_cen), 
    .WEN(sram_wen), 
    .A(sram_addr[14:2]), 
    .D(sram_wdata), 
    .EMA(3'b000), 
    .RETN(hresetn_i)
);
*/
/*
	assign hresp_o = 1'b0;
    //Change to use when cache is miss/hit

	always_ff @(posedge hclk_i or negedge hresetn_i) begin : romFSM
	
		if(FSM != 2'b11 && hsel_i) FSM <= FSM+2'b01;
		else FSM <= 2'b00;
		
        if(hsel_i && hwrite_i) is_write <= 1'b1;
        else if(FSM == 2'b11) is_write <= 1'b0;

	end
	
	always_comb begin : romComb
	
		if(FSM == 2'b11) hready_o = 1'b1;
		else hready_o = 1'b0;

        cs = ~((FSM == 2'b10));
        wen = ~(~cs && hwrite_i);  
		oen = ~(hready_o);
	end
*/
endmodule