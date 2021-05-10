// Copyright 2020 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Author: Paul Scheffler <paulsc@iis.ee.ethz.ch>

module snitch_ssr_intersector #(
  parameter type isect_mst_req_t = logic,
  parameter type isect_mst_rsp_t = logic,
  parameter type isect_slv_req_t = logic,
  parameter type isect_slv_rsp_t = logic
) (
  input  isect_mst_req_t [1:0]  isect_mst_req_i,
  output isect_mst_rsp_t [1:0]  isect_mst_rsp_o,
  input  isect_slv_req_t        isect_slv_req_i,
  output isect_slv_rsp_t        isect_slv_rsp_o
);

  // TODO
  assign isect_mst_rsp_o = '0;
  assign isect_slv_rsp_o = '0;

endmodule
