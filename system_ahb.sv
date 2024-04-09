module system_ahb #(
 parameter DATA_WIDTH = 32,
 parameter RESET_VECTOR = 32'h01000000,
 parameter GPIO_N = 8,
 parameter AHB_SLAVE_N = 4,
 parameter APB_SLAVE_N = 3
)(
    input   clk_i,
    input   resetn_i,

    input   spi_miso_i,
    output  spi_mosi_o,
    output  spi_sck_o,
    output  spi_ssn_o,

    input   flash_miso_i,
    output  flash_mosi_o,
    output  flash_sck_o,
    output  flash_ssn_o,

    input   uart_rx_i,
    output  uart_tx_o,

    input   [GPIO_N-1:0]    gpio_i,
    output  [GPIO_N-1:0]    gpio_dir,
    output  [GPIO_N-1:0]    gpio_o
);


logic                       hclk;
logic                       hresetn;
logic   [DATA_WIDTH-1:0]    haddr; 
logic   [DATA_WIDTH-1:0]    hrdata;
logic   [DATA_WIDTH-1:0]    hwdata;
logic   [2:0]               hsize;
logic                       hwrite;
logic                       hready; 
logic   [1:0]               hresp;


logic   [DATA_WIDTH-1:0]    flash_hrdata;
logic                       flash_hready; 
logic   [1:0]               flash_hresp;
logic                       flash_hsel;

logic   [DATA_WIDTH-1:0]    main_sram_hrdata;
logic                       main_sram_hready; 
logic   [1:0]               main_sram_hresp;
logic                       main_sram_hsel;

logic   [DATA_WIDTH-1:0]    aux_sram_hrdata;
logic                       aux_sram_hready; 
logic   [1:0]               aux_sram_hresp;
logic                       aux_sram_hsel;

logic   [DATA_WIDTH-1:0]    periph_hrdata;
logic                       periph_hready; 
logic   [1:0]               periph_hresp;
logic                       periph_hsel;


logic                       pclk;
logic                       presetn;
logic                       psel        [0:APB_SLAVE_N-1];
logic   [DATA_WIDTH-1:0]    paddr;
logic                       penable;
logic                       pwrite;
logic   [DATA_WIDTH-1:0]    pwdata;
logic   [DATA_WIDTH-1:0]    prdata      [0:APB_SLAVE_N-1];
logic                       pready      [0:APB_SLAVE_N-1];
logic                       pslverr     [0:APB_SLAVE_N-1];





rvv_core #(
    .DATA_WIDTH(32),
    .RESET_VECTOR(32'h01000000)    
) VCORE(
    .clk_i(clk_i),
    .resetn_i(resetn_i),
    .hclk_o(hclk),
    .hresetn_o(hresetn),
    .haddr_o(haddr), 
    .hrdata_i(hrdata),
    .hwdata_o(hwdata),
    .hsize_o(hsize),
    .hwrite_o(hwrite),
    .hready_i(hready), 
    .hresp_i(hresp) 
);

ahbDecMux #(
    .DATA_WIDTH(DATA_WIDTH),
    .SLAVE_N(AHB_SLAVE_N)
    ) AHB_MUX(
    .haddr_i(haddr), 
    .hrdata_o(hrdata),
    .hready_o(hready), 
    .hresp_o(hresp),
    .flash_hrdata_i(flash_hrdata),
    .flash_hready_i(flash_hready),
    .flash_hresp_i(flash_hresp),
    .flash_hsel_o(flash_hsel),
    .main_sram_hrdata_i(main_sram_hrdata),
    .main_sram_hready_i(main_sram_hready),
    .main_sram_hresp_i(main_sram_hresp),
    .main_sram_hsel_o(main_sram_hsel),
    .periph_hrdata_i(periph_hrdata),
    .periph_hready_i(periph_hready),
    .periph_hresp_i(periph_hresp),
    .periph_hsel_o(periph_hsel),
    .aux_sram_hrdata_i(aux_sram_hrdata),
    .aux_sram_hready_i(aux_sram_hready),
    .aux_sram_hresp_i(aux_sram_hresp),
    .aux_sram_hsel_o(aux_sram_hsel)
);

sram_ahb  SRAM_AHB(
    .clk_i(clk_i),
    .resetn_i(resetn_i),
    .hclk_i(hclk),
    .hresetn_i(hresetn),
    .haddr_i(haddr), 
    .hrdata_o(main_sram_hrdata),
    .hwdata_i(hwdata),
    .hsize_i(hsize),
    .hwrite_i(hwrite),
    .hready_o(main_sram_hready), 
    .hresp_o(main_sram_hresp),
    .hsel_i(main_sram_hsel)
);

mem_reg_ahb AUX_SRAM_AHB(
    .clk_i(clk_i),
    .resetn_i(resetn_i),
    .hclk_i(hclk),
    .hresetn_i(hresetn),
    .haddr_i(haddr), 
    .hrdata_o(aux_sram_hrdata),
    .hwdata_i(hwdata),
    .hsize_i(hsize),
    .hwrite_i(hwrite),
    .hready_o(aux_sram_hready), 
    .hresp_o(aux_sram_hresp),
    .hsel_i(aux_sram_hsel)    
);

flash_ahb FLASH(

    .clk_i(clk_i),
    .reset_i(resetn_i),
    //AHB interface
    .hclk_i(hclk),
    .hresetn_i(hresetn),
    .haddr_i(haddr), 
    .hrdata_o(flash_hrdata),
    .hwdata_i(hwdata),
    .hsize_i(hsize),
    .hwrite_i(hwrite),
    .hready_o(flash_hready), 
    .hresp_o(flash_hresp),
    .hsel_i(flash_hsel),
	.miso_i(flash_miso_i),
	.mosi_o(flash_mosi_o),
	.sck_o(flash_sck_o),
	.ssn_o(flash_ssn_o)
);

AHB_APB_Bridge PeripheralBridge(
    .hclk_i(hclk),
    .hresetn_i(hresetn),
    .haddr_i(haddr), 
    .hrdata_o(periph_hrdata),
    .hwdata_i(hwdata),
    .hsize_i(hsize),
    .hwrite_i(hwrite),
    .hready_o(periph_hready), 
    .hresp_o(periph_hresp),
    .hsel_i(periph_hsel),
    .pclk_o(pclk),
    .presetn_o(presetn),
    .psel_o(psel),
    .paddr_o(paddr),
    .penable_o(penable),
    .pwrite_o(pwrite),
    .pwdata_o(pwdata),
    .prdata_i(prdata),
    .pready_i(pready),
    .pslverr_i(pslverr) 
);


//Slave 0
apb_gpio GPIO0(
  .clk_i(clk_i),
  .reset_i(resetn_i),
  .pclk(pclk),
  .presetn(presetn),
  .paddr(paddr[4:0]),
  .psel(psel[0]),
  .penable(penable),
  .pwrite(pwrite),
  .pwdata(pwdata),
  .prdata(prdata[0]),
  .pready(pready[0]),
  .pslverr(pslverr[0]),
  .gpio_i(gpio_i),
  .gpio_o(gpio_o),
  .gpio_oe(gpio_dir)
);

//Slave 1
apb_uart UART0(
  .clk_i(clk_i),
  .reset_i(resetn_i),
  .pclk(pclk),
  .presetn(presetn),
  .paddr(paddr[3:0]),
  .psel(psel[1]),
  .penable(penable),
  .pwrite(pwrite),
  .pwdata(pwdata),
  .prdata(prdata[1]),
  .pready(pready[1]),
  .pslverr(pslverr[1]),
  .uart_rx(uart_rx_i),
  .uart_tx(uart_tx_o)
);

//Slave 2
apb_spi SPI0(

  .clk_i(clk_i),
  .reset_i(resetn_i),
  .pclk(pclk),
  .presetn(presetn),
  .paddr(paddr[2:0]),
  .psel(psel[2]),
  .penable(penable),
  .pwrite(pwrite),
  .pwdata(pwdata),
  .pready(pready[2]),
  .prdata(prdata[2]),
  .pslverr(pslverr[2]),
  .miso_i(spi_miso_i),
  .mosi_o(spi_mosi_o),
  .sck_o(spi_sck_o),
  .ssn_o(spi_ssn_o)

);


endmodule


