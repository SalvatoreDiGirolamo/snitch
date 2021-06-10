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
// Salvatore Di Girolamo <digirols@inf.ethz.ch>

module snitch_cluster_dma_frontend_wrapper #(
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
    // PsPIN command
    parameter type cmd_req_t              = logic,
    parameter type cmd_resp_t             = logic,
    /// data request type
    parameter type axi_req_t              = logic,
    /// data response type
    parameter type axi_res_t              = logic,
    /// transfer descriptor for hw access to DMA
    parameter type transf_descr_t         = logic
) (
    input  logic            clk_i,
    input  logic            rst_ni,
    input  logic [31:0]     cluster_id_i,

    // Command req/resp (from/to clusters)
    input  cmd_req_t        cmd_req_i,
    input  logic            cmd_req_valid_i,
    output logic            cmd_req_ready_o,
    output cmd_resp_t       cmd_resp_o,
    output logic            cmd_resp_valid_o,

    // Direct port (from/to scheduler)
    input  logic            dma_req_valid_i,
    output logic            dma_req_ready_o,
    input  transf_descr_t   dma_req_i,
    output logic            dma_rsp_valid_o,

    // AXI port
    output axi_req_t        axi_dma_req_o,
    input  axi_res_t        axi_dma_res_i
);

    localparam int unsigned CORE_CMD = 0;
    localparam int unsigned SCHED_CMD = 1;

    transf_descr_t core_xfer_descr;
    cmd_resp_t new_cmd_resp;

    logic [1:0] dma_req_valid;
    logic [1:0] dma_req_ready;
    transf_descr_t [1:0] dma_req;
    logic [1:0] dma_resp_valid;

    logic core_resp_fifo_full;

    // link scheduler interface
    assign dma_req_valid[SCHED_CMD] = dma_req_valid_i;
    assign dma_req[SCHED_CMD]       = dma_req_i;
    assign dma_req_ready_o          = dma_req_ready[SCHED_CMD];
    assign dma_rsp_valid_o          = dma_resp_valid[SCHED_CMD];

    // command interface
    //TODO: dma_req_ready should imply ~core_resp_fifo_full
    assign dma_req_valid[CORE_CMD] = ~core_resp_fifo_full && cmd_req_valid_i;
    assign dma_req[CORE_CMD]       = core_xfer_descr;
    assign cmd_req_ready_o         = ~core_resp_fifo_full && dma_req_ready[CORE_CMD];
    assign cmd_resp_valid_o        = dma_resp_valid[CORE_CMD];

    assign new_cmd_resp.cmd_id    = cmd_req_i.cmd_id;

    // queue of responses
    fifo_v3 #(
        .dtype     (cmd_resp_t),
        .DEPTH     (TfReqFifoDepth)
    ) i_resp_fifo (
        .clk_i     ( clk_i                              ),
        .rst_ni    ( rst_ni                             ),
        .flush_i   ( 1'b0                               ),
        .testmode_i( 1'b0                               ),
        .full_o    ( core_resp_fifo_full                ),
        .empty_o   ( /* unconnected */                  ),
        .usage_o   ( /* unconnected */                  ),
        .data_i    ( new_cmd_resp                       ),
        .push_i    ( cmd_req_valid_i && cmd_req_ready_o ),
        .data_o    ( cmd_resp_o                         ),
        .pop_i     ( dma_resp_valid[CORE_CMD]           )
    ); 

    // prepare the transfer descriptor from the command
    assign core_xfer_descr.num_bytes = cmd_req_i.descr.nic_dma_cmd.length;
    assign core_xfer_descr.dst_addr  = cmd_req_i.descr.nic_dma_cmd.dst_addr;
    assign core_xfer_descr.src_addr  = cmd_req_i.descr.nic_dma_cmd.src_addr;
    assign core_xfer_descr.deburst   = 0;
    assign core_xfer_descr.decouple  = 1;
    assign core_xfer_descr.serialize = 0;
    
    snitch_cluster_dma_frontend #(
        .NumCores(2),
        .DmaAxiIdWidth(DmaAxiIdWidth),
        .DmaDataWidth(DmaDataWidth),
        .DmaAddrWidth(DmaAddrWidth),
        .AxiAxReqDepth(AxiAxReqDepth),
        .TfReqFifoDepth(TfReqFifoDepth),
        .axi_req_t(axi_req_t),
        .axi_res_t(axi_res_t),
        .transf_descr_t(transf_descr_t)
    ) i_cluster_dma (
        .clk_i,
        .rst_ni,
        .cluster_id_i     ( cluster_id_i             ),
        .dma_req_valid_i  ( dma_req_valid            ),
        .dma_req_ready_o  ( dma_req_ready            ),
        .dma_req_i        ( dma_req                  ),
        .dma_rsp_valid_o  ( dma_resp_valid           ),
        .axi_dma_req_o    ( axi_dma_req_o            ),
        .axi_dma_res_i    ( axi_dma_res_i            ),
        .busy_o           ( /* unconnected */        ),
        .no_req_pending_o ( /* unconnected */        )
    );

endmodule