
// Copyright 2021 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

module virtual_stdout_demux #(
  /// Data port request type.
  parameter type         dreq_t             = logic,
  /// Data port response type.
  parameter type         drsp_t             = logic
) (
  input  logic            clk_i,
  input  logic            rst_ni,
  input  logic [31:0]     hart_id_i,
  input  dreq_t           core_req_i,
  output drsp_t           core_resp_o,
  output dreq_t           data_req_o,
  input  drsp_t           data_resp_i
);

  `ifndef TARGET_SYNTHESIS 
    `define VIRTUAL_STDOUT
  `elsif TARGET_VERILATOR
    `define VIRTUAL_STDOUT
  `endif
  
  `ifndef VIRTUAL_STDOUT
    // When synthesizing, feed signals through to real stdout device.
    assign data_req_o   = core_req_i;
    assign core_resp_o  = data_resp_i;
  `else
    // When not synthesizing, insert virtual stdout device that is close to the core for fast and
    // interference-free printing.

    byte buffer [$];

    function void flush();
      automatic string s;
      for (int i_char = 0; i_char < buffer.size(); i_char++) begin
        s = $sformatf("%s%c", s, buffer[i_char]);
      end
      if (s.len() > 0) begin
        $display("[%01d,%01d] %s", hart_id_i[31:16], hart_id_i[15:0], s);
      end
      buffer.delete();
    endfunction

    function void append(byte ch);
      if (ch == 8'hA) begin
        flush();
      end else begin
        buffer.push_back(ch);
      end
    endfunction

    logic resp_inj_d, resp_inj_q;
    always_comb begin
      // Feed through by default.
      data_req_o   = core_req_i;
      core_resp_o  = data_resp_i;
      resp_inj_d = resp_inj_q;
      // Inject responses by stdout device.
      if (resp_inj_q) begin
        core_resp_o.p_valid = 1'b1;
        core_resp_o.p.data = '0;
        resp_inj_d = 1'b0;
      end
      // Intercept accesses to stdout device.
      if (core_req_i.q_valid && core_req_i.q.addr[31:12] == 20'h1A104) begin
        data_req_o.q_valid = 1'b0;
        core_resp_o.q_ready = 1'b1;
        resp_inj_d = 1'b1;
      end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        flush();
        resp_inj_q <= 1'b0;
      end else begin
        resp_inj_q <= resp_inj_d;
        if (resp_inj_d) begin
          append(core_req_i.q.data & 32'hFF);
        end
      end
    end

    // Assertions
    assert property(
      @(posedge clk_i) (resp_inj_q |-> core_req_i.p_ready))
        else $fatal (1, "Core is not ready to receive response!");

  `endif
endmodule