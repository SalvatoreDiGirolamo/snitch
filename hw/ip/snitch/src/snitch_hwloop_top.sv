module snitch_hwloop_top #(
    parameter NumHWLoops     = 2,
    /* do not override */
    parameter N_REG_BITS = $clog2(NumHWLoops)
) (
    input  logic                     clk_i,
    input  logic                     rst_i,

    // registers
    input  logic           [31:0]    hwlp_start_data_i,
    input  logic           [31:0]    hwlp_end_data_i,
    input  logic           [31:0]    hwlp_cnt_data_i,
    input  logic            [2:0]    hwlp_we_i,
    input  logic [N_REG_BITS-1:0]    hwlp_regid_i,         // selects the register set

    // instruction valid
    input  logic                     hwloop_valid_i,

    // current PC
    input  logic [31:0]              current_pc_i,

    // to id stage
    output logic                     hwlp_jump_o,
    output logic [31:0]              hwlp_targ_addr_o
);

    logic [NumHWLoops-1:0] [31:0] hwlp_start;
    logic [NumHWLoops-1:0] [31:0] hwlp_end;
    logic [NumHWLoops-1:0] [31:0] hwlp_cnt;
    logic [NumHWLoops-1:0]        hwlp_dec_cnt;

    snitch_hwloop_regs #(
        .N_REGS ( NumHWLoops )
    ) hwloop_regs_i (
        .clk                   ( clk_i             ),
        .rst_n                 ( ~rst_i            ),

        // from ID
        .hwlp_start_data_i     ( hwlp_start_data_i ),
        .hwlp_end_data_i       ( hwlp_end_data_i   ),
        .hwlp_cnt_data_i       ( hwlp_cnt_data_i   ),
        .hwlp_we_i             ( hwlp_we_i         ),
        .hwlp_regid_i          ( hwlp_regid_i      ),

        // from controller
        .valid_i               ( hwloop_valid_i    ),

        // to hwloop controller
        .hwlp_start_addr_o     ( hwlp_start        ),
        .hwlp_end_addr_o       ( hwlp_end          ),
        .hwlp_counter_o        ( hwlp_cnt          ),

        // from hwloop controller
        .hwlp_dec_cnt_i        ( hwlp_dec_cnt      )
    );

    snitch_hwloop_controller #(
        .N_REGS ( NumHWLoops )
    ) hwloop_controller_i (
        .current_pc_i          ( current_pc_i      ),

        .hwlp_jump_o           ( hwlp_jump_o       ),
        .hwlp_targ_addr_o      ( hwlp_targ_addr_o  ),

        // from hwloop_regs
        .hwlp_start_addr_i     ( hwlp_start        ),
        .hwlp_end_addr_i       ( hwlp_end          ),
        .hwlp_counter_i        ( hwlp_cnt          ),

        // to hwloop_regs
        .hwlp_dec_cnt_o        ( hwlp_dec_cnt      )
        //.hwlp_dec_cnt_id_i     ( hwlp_dec_cnt_id & {NumHWLoops{hwloop_valid_i}} )
    );

endmodule