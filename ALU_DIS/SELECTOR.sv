module SELECTO #(
    parameter DATA_WIDTH = 32
)(
    input                           addsub_sel_i,
    input                           shift_sel_i,
    input                           logic_sel_i,
    input                           mul_sel_hi_i,
    input                           mul_sel_low_i,
    input                           com_sel_i,
    input                           mac_sel_i,

    input   [DATA_WIDTH-1:0]        addsub_data_i,
    input   [DATA_WIDTH-1:0]        shift_data_i,
    input   [DATA_WIDTH-1:0]        logic_data_i,
    input   [DATA_WIDTH-1:0]        mul_low_data_i,
    input   [DATA_WIDTH-1:0]        mul_hi_data_i,
    input   [DATA_WIDTH-1:0]        com_data_i,
    input   [DATA_WIDTH-1:0]        mac_data_i,

    output  [DATA_WIDTH-1:0]        data_o
);

logic [6:0] sel;

always_comb begin : MUX_LOGIC
    sel =   {addsub_sel_i, shift_sel_i, logic_sel_i, mul_sel_hi_i, mul_sel_low_i, com_sel_i, mac_sel_i};
    case (sel)
        7': data_o  = addsub_data_i; 
        7': data_o  = shift_data_i;
        7': data_o  = logic_data_i;
        7': data_o  = mul_hi_data_i;
        7': data_o  = mul_low_data_i;
        7': data_o  = com_data_i;
        7': data_o  = mac_data_i;
        default: 
    endcase
end

endmodule
