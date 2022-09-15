


package vect_pkg;


typedef enum logic [6:0] {
    VLOAD   =   7'b0000111,
    VSTORE  =   7'b0100111,
    VARITH  =   7'b1010111
} opcode_e;


typedef enum logic [5:0] {
    VADD_VREDSUM    =   6'b000000,
    VREDAND         =   6'b000001,
    VSUB_VREDOR     =   6'b000010,
    VRSUB_VREDXOR   =   6'b000011,
    VMINU_VREDMINU  =   6'b000100,
    VMIN_VREDMIN    =   6'b000101,
    VMAXU_VREDMAXU  =   6'b000110,
    VMAX_VREDMAX    =   6'b000111,
    VAND            =   6'b001001,
    VOR             =   6'b001010,
    VXOR            =   6'b001011,
    VRGATHER        =   6'b001100,
    VINCGATHER      =   6'b001101,
    VSLIDEUP        =   6'b001110,
    VSLIDEDOWN      =   6'b001111,

    VADC            =   6'b010000,
    VMADC           =   6'b010001,
    VSBC            =   6'b010010,
    VMSBC           =   6'b010011,
    //VMERGE        =   6'b010111,
    VMSEQ_VMANDNOT  =   6'b011000,
    VMSNE_VMAND     =   6'b011001,
    VMSLTU_VMOR     =   6'b011010,
    VMSLT_VMXOR     =   6'b011011,
    VMSLEU_VMORNOT  =   6'b011100,
    VMSLE_VMNAND    =   6'b011101,
    VMSGTU_VMNOR    =   6'b011110,
    VMSGT_VMXNOR    =   6'b011111,

    VMERGE_VCOMPRESS=   6'b010111,
    //VMANDNOT      =   6'b011000,
    //VMAND         =   6'b011001,
    //VMOR          =   6'b011010,
    //VMXOR         =   6'b011011,
    //VMORNOT       =   6'b011100,
    //VMNAND        =   6'b011101,
    //VMNOR         =   6'b011110,
    //VMXNOR        =   6'b011111,
    VSLL_VMUL       =   6'b100101,
    VSRL            =   6'b101000,
    VSRA_VMADD      =   6'b101001,
    VSSRL           =   6'b101010,
    VSSRA_VNMSUB    =   6'b101011,
    VNSRL           =   6'b101100,
    VNSRA_VMACC     =   6'b101101,
    VNCLIPU         =   6'b101110,
    VNCLIP_VNMSAC   =   6'b101111,

    VDIVU           =   6'b100000,
    VDIV            =   6'b100001,
    VREMU           =   6'b100010,
    VREM            =   6'b100011,
    VMULHU          =   6'b100100,
    //VMUL          =   6'b100101,
    VMULHSU         =   6'b100110,
    VMULH           =   6'b100111

    //VMADD         =   6'b101001,
    //VNMSUB        =   6'b101011,
    //VMACC         =   6'b101101,
    //VNMSAC        =   6'b101111

} funct6_e;


/*
localparam  VADD_VREDSUM        = 6'b000000;
localparam  VSUB        = 6'b000010;
localparam  VRSUB       = 6'b000011;
localparam  VMINU       = 6'b000100;
localparam  VMIN        = 6'b000101;
localparam  VMAXU       = 6'b000110;
localparam  VMAX        = 6'b000111;
localparam  VAND        = 6'b001001;
localparam  VOR         = 6'b001010;
localparam  VXOR        = 6'b001011;
localparam  VRGATHER    = 6'b001100;
localparam  VSLIDEUP    = 6'b001110;
localparam  VSLIDEDOWN  = 6'b001111;
localparam  VADC        = 6'b010000;
localparam  VMADC       = 6'b010001;
localparam  VSBC        = 6'b010010;
localparam  VMSBC       = 6'b010011;
localparam  VMERGE      = 6'b010111;
localparam  VMSEQ_VMANDNOT       = 6'b011000;
localparam  VMSNE       = 6'b011001;
localparam  VMSLTU      = 6'b011010;
localparam  VMSLT       = 6'b011011;
localparam  VMSLEU      = 6'b011100;
localparam  VMSLE       = 6'b011101;
localparam  VMSGTU      = 6'b011110;
localparam  VMSGT       = 6'b011111;
localparam  VCOMPRESS   = 6'b010111;
localparam  VMANDNOT    = 6'b011000;
localparam  VMAND       = 6'b011001;
localparam  VMOR        = 6'b011010;
localparam  VMXOR       = 6'b011011;
localparam  VMORNOT     = 6'b011100;
localparam  VMNAND      = 6'b011101;
localparam  VMNOR       = 6'b011110;
localparam  VMXNOR      = 6'b011111;
localparam  VSLL        = 6'b100101;
localparam  VSRL        = 6'b101000;
localparam  VSRA        = 6'b101001;
localparam  VSSRL       = 6'b101010;
localparam  VSSRA       = 6'b101011;
localparam  VNSRL       = 6'b101100;
localparam  VNSRA       = 6'b101101;
localparam  VNCLIPU     = 6'b101110;
localparam  VNCLIP      = 6'b101111;
localparam  VDIVU       = 6'b100000;
localparam  VDIV        = 6'b100001;
localparam  VREMU       = 6'b100010;
localparam  VREM        = 6'b100011;
localparam  VMULHU      = 6'b100100;
localparam  VMUL        = 6'b100101;
localparam  VMULHSU     = 6'b100110;
localparam  VMULH       = 6'b100111;
localparam  VMADD       = 6'b101001;
localparam  VNMSUB      = 6'b101011;
localparam  VMACC       = 6'b101101;
localparam  VNMSAC      = 6'b101111;
*/
localparam  INT     = 1'b0;
localparam  MULT  = 1'b1;       



typedef enum logic [2:0] {
    OPIVV = 3'b000,
    OPFVV = 3'b001,
    OPMVV = 3'b010,
    OPIVI = 3'b011,
    OPIVX = 3'b100,
    OPFVF = 3'b101,
    OPMVX = 3'b110,
    OPCFG = 3'b111
  } funct3_e;


typedef enum logic [1:0] {
    OFF_UNIT        =   2'b00,
    OFF_INDEX_UNORD =   2'b01,
    OFF_STRIDE      =   2'b10,
    OFF_INDEX_ORD   =   2'b11
} mop_e;


//Arithmetic instruction
typedef struct packed {
    funct6_e            funct6; //31:26
    logic               vm; //[25]
    logic       [24:20] vs2; //[24:20]
    logic       [19:15] vs1_rs1_imm; //[19:15]
    funct3_e            funct3; //[14:12]
    logic       [11:7]  vd_rd_vs3; //[11:7]
    opcode_e            opcode; //[6:0]

} arithm_instr_t;


//Memory instruction
typedef struct packed {
    logic       [31:29] nf; //[31:20]
    logic               mew;
    mop_e               mop;
    logic               vm; //[25]
    logic       [24:20] vs2_rs2_lumop; //[24:20]
    logic       [19:15] rs1; //[19:15]
    logic       [14:12] width; //[14:12]
    logic       [11:7]  vd_vs3; //[11:7]
    opcode_e            opcode; //[6:0]

} mem_instr_t;

typedef struct packed {
    logic               funct1;
    logic       [30:20] zimm11;
    logic       [19:15] rs1;
    funct3_e            funct3;
    logic       [11:7]  rd;
    opcode_e            opcode;

} setvlvi_instr_t;

typedef struct packed {
    logic               funct2;
    logic       [29:20] zimm10;
    logic       [19:15] uimm5;
    funct3_e            funct3;
    logic       [11:7]  rd;
    opcode_e            opcode;

} setivlvi_instr_t;


endpackage : vect_pkg