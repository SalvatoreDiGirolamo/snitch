// Copyright (c) 2020 ETH Zurich and University of Bologna
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// Thomas Benz <tbenz@ethz.ch>
// Salvatore Di Girolamo <digirols@inf.ethz.ch>

/// replaces the mchan in the pulp cluster if the new AXI DMA should be used
/// strictly 32 bit on the TCDM side.
module snitch_cluster_dma_frontend #(
    /// number of cores in the cluster
    parameter int unsigned NumCores       = -1,
    /// id width of the DMA AXI Master port
    parameter int unsigned DmaAxiIdWidth  = -1,
    /// data width of the DMA AXI Master port
    parameter int unsigned DmaDataWidth   = -1,
    /// address width of the DMA AXI Master port
    parameter int unsigned DmaAddrWidth   = -1,
    /// number of AX requests in-flight
    parameter int unsigned AxiAxReqDepth  = -1,
    /// number of 1D transfers buffered in backend
    parameter int unsigned TfReqFifoDepth = -1,
    /// data request type
    parameter type axi_req_t      = logic,
    /// data response type
    parameter type axi_res_t      = logic,
    /// transfer descriptor for hw access to DMA
    parameter type transf_descr_t = logic
)(
    input  logic                         clk_i,
    input  logic                         rst_ni,
    input  logic [31:0]                  cluster_id_i,
    /// direct hw port
    input  logic [NumCores-1:0]          dma_req_valid_i,
    output logic [NumCores-1:0]          dma_req_ready_o,
    input  transf_descr_t [NumCores-1:0] dma_req_i,
    output logic [NumCores-1:0]          dma_rsp_valid_o,
    /// wide AXI port
    output axi_req_t                     axi_dma_req_o,
    input  axi_res_t                     axi_dma_res_i,
    /// status signal
    output logic                         busy_o,
    /// no pending requests signal
    output logic [NumCores-1:0]          no_req_pending_o
);

    // number of register sets in fe
    localparam int unsigned NumRegs  = NumCores;

    // arbitration index width
    localparam int unsigned IdxWidth = unsigned'($clog2(NumRegs));

    // buffer depth
    localparam int unsigned BufferDepth = 3; // + 64;

    localparam int unsigned TfFifoDepth = TfReqFifoDepth + AxiAxReqDepth + BufferDepth + 1;

    // 1D burst request
    typedef logic [DmaAddrWidth-1 :0] addr_t;
    typedef logic [DmaAxiIdWidth-1:0] axi_id_t;
    typedef struct packed {
        axi_id_t            id;
        addr_t              src, dst, num_bytes;
        axi_pkg::cache_t    cache_src, cache_dst;
        axi_pkg::burst_t    burst_src, burst_dst;
        logic               decouple_rw;
        logic               deburst;
        logic               serialize;
    } burst_req_t;

    // debug only: logfile
    integer log_file;
    string  log_file_name;

    // rr input
    transf_descr_t [NumRegs-1:0] transf_descr;
    logic          [NumRegs-1:0] be_ready;
    logic          [NumRegs-1:0] be_valid;
    // rr output
    transf_descr_t               transf_descr_arb;
    logic                        be_ready_arb;
    logic                        be_valid_arb;
    // the index ob the chosen pe
    logic [IdxWidth-1:0]         pe_idx_arb;

    // burst request definition
    burst_req_t burst_req;

    // transaction id
    logic [31:0] next_id, done_id;

    // backend idle signal
    logic be_idle;
    logic trans_complete;

    // information about most recent transfer
    logic [IdxWidth-1:0] tf_head;
    logic                tf_empty;

    // round robin to arbitrate
    rr_arb_tree #(
        .NumIn      ( NumRegs          ), 
        .DataWidth  ( -1               ),
        .DataType   ( transf_descr_t   ),
        .ExtPrio    ( 0                ),
        .AxiVldRdy  ( 1                ),
        .LockIn     ( 1                )
    ) i_rr_arb_tree (
        .clk_i      ( clk_i             ),
        .rst_ni     ( rst_ni            ),
        .flush_i    ( 1'b0              ),
        .rr_i       ( '0                ),
        .req_i      ( dma_req_valid_i   ),
        .gnt_o      ( dma_req_ready_o   ),
        .data_i     ( dma_req_i         ),
        .gnt_i      ( be_ready_arb      ),
        .req_o      ( be_valid_arb      ),
        .data_o     ( transf_descr_arb  ),
        .idx_o      ( pe_idx_arb        )
    );

    // global transfer id
    transfer_id_gen #(
        // keep this fixed at 32 bit as two 32 bit counters are
        // relatively cheap
        .ID_WIDTH     ( 32     )
    ) i_transfer_id_gen (
        .clk_i        ( clk_i                                                         ),
        .rst_ni       ( rst_ni                                                        ),
        .issue_i      ( be_ready_arb & be_valid_arb & transf_descr_arb.num_bytes != 0 ),
        .retire_i     ( trans_complete                                                ),
        .next_o       ( next_id                                                       ),
        .completed_o  ( done_id                                                       )
    );

    // hold a bit for each launched transfer where it came from
    fifo_v3 #(
        .dtype     ( logic [IdxWidth-1:0]   ),
        .DEPTH     ( TfFifoDepth )
    ) i_tf_id_fifo (
        .clk_i     ( clk_i                                                         ),
        .rst_ni    ( rst_ni                                                        ),
        .flush_i   ( 1'b0                                                          ),
        .testmode_i( 1'b0                                                          ),
        .full_o    ( ),
        .empty_o   ( tf_empty                                                      ),
        .usage_o   ( ),
        .data_i    ( pe_idx_arb                                                    ), // we are external tf
        .push_i    ( be_ready_arb & be_valid_arb & transf_descr_arb.num_bytes != 0 ),
        .data_o    ( tf_head                                                       ),
        .pop_i     ( trans_complete                                                )
    );

    // generate responses
    for (genvar i = 0; i < NumCores; i++) begin : gen_core_regs
        assign dma_rsp_valid_o[i] =  (tf_head == i) & !tf_empty & trans_complete;
    end

    // in-flight request counter
    localparam int unsigned MaxNumRequests = TfReqFifoDepth + BufferDepth + 1;
    localparam int unsigned MaxReqWidth = $clog2(MaxNumRequests);
    logic [NumCores-1:0][MaxReqWidth-1:0] core_tf_num_d, core_tf_num_q;

    for (genvar i = 0; i < NumCores; i++) begin : gen_req_counters
        //increase counter if tf is started
        always_comb begin : proc_counter
            // default
            core_tf_num_d[i] = core_tf_num_q[i];
            // increase
            if (be_ready[i] & be_valid[i] & transf_descr[i].num_bytes != 0) begin
                core_tf_num_d[i] = core_tf_num_d[i] + 1;
            end
            // decrement
            if ((tf_head == i) & !tf_empty & trans_complete) begin
                core_tf_num_d[i] = core_tf_num_d[i] - 1;
            end
        end
        // assign output
        assign no_req_pending_o[i] = core_tf_num_d[i] == 0;
    end // gen_req_counters


    //---------NON SYNTHESIZABLE ---------------
    `ifndef VERILATOR
    //pragma translate_off
    // log dma transfers to disk
    initial begin
        @(posedge rst_ni);
        $sformat(log_file_name, "DMA_TRANSFERS_%2h.log", cluster_id_i);
        log_file = $fopen(log_file_name, "w");
        $fwrite(log_file, "queue_time pe_id tf_id src dst num_bytes launch_time completion_time\n");
        $fclose(log_file);
    end
    // datatype to store arbitrated tf
    typedef struct packed {
        longint queue_time;
        longint pe_id;
        longint next_id;
        longint src;
        longint dst;
        longint len;
    } queued_tf_t;
    // launch tf
    typedef struct packed {
        queued_tf_t queued_tf;
        longint     launch_time;
    } launched_tf_t;
    // create queued tf
    queued_tf_t queued_tf, queued_tf_head;
    // pack queued tf
    always_comb begin
        queued_tf.queue_time = $time();
        queued_tf.pe_id      = pe_idx_arb;
        queued_tf.next_id    = next_id;
        queued_tf.src        = transf_descr_arb.src_addr;
        queued_tf.dst        = transf_descr_arb.dst_addr;
        queued_tf.len        = transf_descr_arb.num_bytes;
    end
    // use a fifo to model queuing
    fifo_v3 #(
        .dtype     ( queued_tf_t        ),
        .DEPTH     ( TfReqFifoDepth     )
    ) i_queue_fifo (
        .clk_i     ( clk_i                            ),
        .rst_ni    ( rst_ni                           ),
        .flush_i   ( 1'b0                             ),
        .testmode_i( 1'b0                             ),
        .full_o    ( ),
        .empty_o   ( ),
        .usage_o   ( ),
        .data_i    ( queued_tf                        ),
        .push_i    ( be_valid_arb && be_ready_arb     ),
        .data_o    ( queued_tf_head                   ),
        .pop_i     ( i_axi_dma_backend.burst_req_pop  )
    );
    // launched tf
    launched_tf_t launched_tf, launched_tf_head;
    // pack launched tf
    always_comb begin
        launched_tf.queued_tf   = queued_tf_head;
        launched_tf.launch_time = $time();
    end
    // use a fifo to hold tf info while it goes through the backend
    fifo_v3 #(
        .dtype     ( launched_tf_t                   ),
        .DEPTH     ( AxiAxReqDepth + BufferDepth + 1 )
    ) i_launch_fifo (
        .clk_i     ( clk_i                            ),
        .rst_ni    ( rst_ni                           ),
        .flush_i   ( 1'b0                             ),
        .testmode_i( 1'b0                             ),
        .full_o    ( ),
        .empty_o   ( ),
        .usage_o   ( ),
        .data_i    ( launched_tf                      ),
        .push_i    ( i_axi_dma_backend.burst_req_pop  ),
        .data_o    ( launched_tf_head                 ),
        .pop_i     ( trans_complete                   )
    );
    // write info to file
    always @(posedge clk_i) begin
        #0;
        if(trans_complete) begin
            log_file = $fopen(log_file_name, "a");
            $fwrite(log_file, "%0d %0d %0d 0x%0x 0x%0x %0d %0d %0d\n",
                               launched_tf_head.queued_tf.queue_time, launched_tf_head.queued_tf.pe_id,
                               launched_tf_head.queued_tf.next_id, launched_tf_head.queued_tf.src,
                               launched_tf_head.queued_tf.dst, launched_tf_head.queued_tf.len,
                               launched_tf_head.launch_time, $time()
                    );
            $fclose(log_file);
        end
    end
    //pragma translate_on
    `endif
    //---------NON SYNTHESIZABLE ---------------

    // map arbitrated transfer descriptor onto generic burst request
    always_comb begin : proc_map_to_1D_burst
        burst_req             = '0;
        burst_req.src         =  transf_descr_arb.src_addr;
        burst_req.dst         =  transf_descr_arb.dst_addr;
        burst_req.num_bytes   =  transf_descr_arb.num_bytes;
        burst_req.burst_src   = axi_pkg::BURST_INCR;
        burst_req.burst_dst   = axi_pkg::BURST_INCR;
        burst_req.decouple_rw = transf_descr_arb.decouple;
        burst_req.deburst     = transf_descr_arb.deburst;
        burst_req.serialize   = transf_descr_arb.serialize;
    end

    // instantiate backend :)
    axi_dma_backend #(
        .DataWidth         ( DmaDataWidth    ),
        .AddrWidth         ( DmaAddrWidth    ),
        .IdWidth           ( DmaAxiIdWidth   ),
        .AxReqFifoDepth    ( AxiAxReqDepth   ),
        .TransFifoDepth    ( TfReqFifoDepth  ),
        .BufferDepth       ( BufferDepth     ), // minimal 3 for giving full performance
        .axi_req_t         ( axi_req_t       ),
        .axi_res_t         ( axi_res_t       ),
        .burst_req_t       ( burst_req_t     ),
        .DmaIdWidth        ( 32              ),
        .DmaTracing        ( 0               )
    ) i_axi_dma_backend (
        .clk_i            ( clk_i             ),
        .rst_ni           ( rst_ni            ),
        .dma_id_i         ( cluster_id_i      ),
        .axi_dma_req_o    ( axi_dma_req_o     ),
        .axi_dma_res_i    ( axi_dma_res_i     ),
        .burst_req_i      ( burst_req         ),
        .valid_i          ( be_valid_arb      ),
        .ready_o          ( be_ready_arb      ),
        .backend_idle_o   ( be_idle           ),
        .trans_complete_o ( trans_complete    )
    );

    // busy if not idle
    assign busy_o = ~be_idle;

    always_ff @(posedge clk_i or negedge rst_ni) begin 
        if(~rst_ni) begin
            core_tf_num_q    <= 0;
        end else begin
            core_tf_num_q    <= core_tf_num_d;
        end
    end

endmodule : snitch_cluster_dma_frontend
