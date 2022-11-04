module instr_issue #(
    parameter   DATA_WIDTH  =   32,
    parameter   INSTR_WIDTH =   32,
    parameter   FIFO_DEPTH  =   4
)(

    input                       clk_i,
    input                       resetn_i,


    //Scalar interface
    input   [INSTR_WIDTH-1:0]   instr_i,
    input                       buf_write_i,
    output                      buf_full_o,
    output                      vect_ready_o,

    //Vector interface
    output  [INSTR_WIDTH-1:0]   instr_o,
    output                      buf_empty_o,
    input                       buf_read_i

);


//FIFO




//Lane signals enable 


endmodule
