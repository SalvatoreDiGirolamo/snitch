// Copyright 2020 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Author: Florian Zaruba <zarubaf@iis.ee.ethz.ch>
// Author: Fabian Schuiki <fschuiki@iis.ee.ethz.ch>
//
// AUTOMATICALLY GENERATED by genoccamy.py; edit the script instead.

`include "common_cells/registers.svh"

module occamy_top
  import occamy_pkg::*;
(
  input  logic        clk_i,
  input  logic        rst_ni,
  /// Peripheral clock
  input  logic        clk_periph_i,
  input  logic        rst_periph_ni,
  /// Real-time clock (for time keeping)
  input  logic        rtc_i,
  input  logic        test_mode_i,
  input  logic [1:0]  chip_id_i,
  input  logic [1:0]  boot_mode_i,
  // pad cfg
  output logic [31:0]      pad_slw_o,
  output logic [31:0]      pad_smt_o,
  output logic [31:0][1:0] pad_drv_o,
  // `uart` Interface
  output logic        uart_tx_o,
  input  logic        uart_rx_i,
  // `gpio` Interface
  input  logic [31:0] gpio_d_i,
  output logic [31:0] gpio_d_o,
  output logic [31:0] gpio_oe_o,
  output logic [31:0] gpio_puen_o,
  output logic [31:0] gpio_pden_o,
  // `jtag` Interface
  input  logic        jtag_trst_ni,
  input  logic        jtag_tck_i,
  input  logic        jtag_tms_i,
  input  logic        jtag_tdi_i,
  output logic        jtag_tdo_o,
  // `i2c` Interface
  output logic        i2c_sda_o,
  input  logic        i2c_sda_i,
  output logic        i2c_sda_en_o,
  output logic        i2c_scl_o,
  input  logic        i2c_scl_i,
  output logic        i2c_scl_en_o,
  // `SPI Host` Interface
  output logic        spim_sck_o,
  output logic        spim_sck_en_o,
  output logic [1:0]  spim_csb_o,
  output logic [1:0]  spim_csb_en_o,
  output logic [3:0]  spim_sd_o,
  output logic [3:0]  spim_sd_en_o,
  input        [3:0]  spim_sd_i,

  /// Boot ROM
  output ${soc_regbus_periph_xbar.out_bootrom.req_type()} bootrom_req_o,
  input  ${soc_regbus_periph_xbar.out_bootrom.rsp_type()} bootrom_rsp_i,

  /// Clk manager
  output ${soc_regbus_periph_xbar.out_clk_mgr.req_type()} clk_mgr_req_o,
  input  ${soc_regbus_periph_xbar.out_clk_mgr.rsp_type()} clk_mgr_rsp_i,

  /// HBM2e Ports
% for i in range(8):
  output  ${soc_wide_xbar.__dict__["out_hbm_{}".format(i)].req_type()} hbm_${i}_req_o,
  input   ${soc_wide_xbar.__dict__["out_hbm_{}".format(i)].rsp_type()} hbm_${i}_rsp_i,
% endfor

  /// HBI Ports
% for i in range(nr_s1_quadrants):
  input   ${soc_wide_xbar.__dict__["in_hbi_{}".format(i)].req_type()} hbi_${i}_req_i,
  output  ${soc_wide_xbar.__dict__["in_hbi_{}".format(i)].rsp_type()} hbi_${i}_rsp_o,
% endfor

  /// PCIe Ports
  output  ${soc_wide_xbar.out_pcie.req_type()} pcie_axi_req_o,
  input   ${soc_wide_xbar.out_pcie.rsp_type()} pcie_axi_rsp_i,

  input  ${soc_wide_xbar.in_pcie.req_type()} pcie_axi_req_i,
  output ${soc_wide_xbar.in_pcie.rsp_type()} pcie_axi_rsp_o
);

  occamy_soc_reg_pkg::occamy_soc_reg2hw_t soc_ctrl_in;
  occamy_soc_reg_pkg::occamy_soc_hw2reg_t soc_ctrl_out;
  // Machine timer and machine software interrupt pending.
  logic mtip, msip;
  // Supervisor and machine-mode external interrupt pending.
  logic [1:0] eip;
  logic debug_req;
  occamy_interrupt_t irq;

  addr_t [${nr_s1_quadrants-1}:0] s1_quadrant_base_addr;
  % for i in range(nr_s1_quadrants):
  assign s1_quadrant_base_addr[${i}] = ClusterBaseOffset + ${i} * S1QuadrantAddressSpace;
  % endfor

  ///////////////////
  //   CROSSBARS   //
  ///////////////////
  ${module}

  /////////////////////////////
  // Narrow to Wide Crossbar //
  /////////////////////////////
  <% soc_narrow_xbar.out_soc_wide \
        .change_iw(context, 3, "soc_narrow_wide_iwc") \
        .atomic_adapter(context, 16, "soc_narrow_wide_amo_adapter") \
        .change_dw(context, 512, "soc_narrow_wide_dw", to=soc_wide_xbar.in_soc_narrow)
  %>

  //////////
  // PCIe //
  //////////
  assign pcie_axi_req_o = ${soc_wide_xbar.out_pcie.req_name()};
  assign ${soc_wide_xbar.out_pcie.rsp_name()} = pcie_axi_rsp_i;
  assign ${soc_wide_xbar.in_pcie.req_name()} = pcie_axi_req_i;
  assign pcie_axi_rsp_o = ${soc_wide_xbar.in_pcie.rsp_name()};

  //////////
  // CVA6 //
  //////////

  occamy_cva6 i_occamy_cva6 (
    .clk_i (clk_i),
    .rst_ni (rst_ni),
    .irq_i (eip),
    .ipi_i (msip),
    .time_irq_i (mtip),
    .debug_req_i (debug_req),
    .axi_req_o (${soc_narrow_xbar.in_cva6.req_name()}),
    .axi_resp_i (${soc_narrow_xbar.in_cva6.rsp_name()})
  );

  % for i in range(nr_s1_quadrants):
  ////////////////////
  // S1 Quadrants ${i} //
  ////////////////////
  <%
    cut_width = 1
    narrow_in = soc_narrow_xbar.__dict__["out_s1_quadrant_{}".format(i)].cut(context, cut_width, name="narrow_in_cut_{}".format(i))
    narrow_out = soc_narrow_xbar.__dict__["in_s1_quadrant_{}".format(i)].copy(name="narrow_out_cut_{}".format(i)).declare(context)
    narrow_out.cut(context, cut_width, to=soc_narrow_xbar.__dict__["in_s1_quadrant_{}".format(i)])
    wide_in = soc_wide_xbar.__dict__["out_s1_quadrant_{}".format(i)].cut(context, cut_width, name="wide_in_cut_{}".format(i))
    wide_out = soc_wide_xbar.__dict__["in_s1_quadrant_{}".format(i)].copy(name="wide_out_cut_{}".format(i)).declare(context)
    wide_out.cut(context, cut_width, to=soc_wide_xbar.__dict__["in_s1_quadrant_{}".format(i)])
  %>
  occamy_quadrant_s1 i_occamy_quadrant_s1_${i} (
    .clk_i (clk_i),
    .rst_ni (rst_ni),
    .test_mode_i (test_mode_i),
    .tile_id_i (6'd${i}),
    .debug_req_i ('0),
    .meip_i ('0),
    .mtip_i ('0),
    .msip_i ('0),
    .quadrant_narrow_out_req_o (${narrow_out.req_name()}),
    .quadrant_narrow_out_rsp_i (${narrow_out.rsp_name()}),
    .quadrant_narrow_in_req_i (${narrow_in.req_name()}),
    .quadrant_narrow_in_rsp_o (${narrow_in.rsp_name()}),
    .quadrant_wide_out_req_o (${wide_out.req_name()}),
    .quadrant_wide_out_rsp_i (${wide_out.rsp_name()}),
    .quadrant_wide_in_req_i (${wide_in.req_name()}),
    .quadrant_wide_in_rsp_o (${wide_in.rsp_name()})
  );

  % endfor

  /// HBM2e Ports
% for i in range(8):
  assign hbm_${i}_req_o = ${soc_wide_xbar.__dict__["out_hbm_{}".format(i)].req_name()};
  assign ${soc_wide_xbar.__dict__["out_hbm_{}".format(i)].rsp_name()} = hbm_${i}_rsp_i;
% endfor

  /// HBI Ports
  // TODO(zarubaf): Truncate address.
% for i in range(nr_s1_quadrants):
  assign ${soc_wide_xbar.__dict__["in_hbi_{}".format(i)].req_name()} = hbi_${i}_req_i;
  assign hbi_${i}_rsp_o = ${soc_wide_xbar.__dict__["in_hbi_{}".format(i)].rsp_name()};
% endfor

  /////////////////
  // Peripherals //
  /////////////////
  <% soc_narrow_xbar.out_periph \
      .cdc(context, "clk_periph_i", "rst_periph_ni", "axi_lite_cdc") \
      .to_axi_lite(context, "axi_to_axi_lite_periph", to=soc_periph_xbar.in_soc) %>

  <% soc_narrow_xbar.out_regbus_periph \
      .cdc(context, "clk_periph_i", "rst_periph_ni", "periph_cdc") \
      .change_dw(context, 32, "axi_to_axi_lite_dw") \
      .to_axi_lite(context, "axi_to_axi_lite_regbus_periph") \
      .to_reg(context, "axi_lite_to_regbus_periph", to=soc_regbus_periph_xbar.in_soc) %>


  ///////////
  // Debug //
  ///////////
  <% regbus_debug = soc_periph_xbar.out_debug.to_reg(context, "axi_lite_to_reg_debug") %>
  dm::hartinfo_t [0:0] hartinfo;
  assign hartinfo = ariane_pkg::DebugHartInfo;

  logic          dmi_rst_n;
  dm::dmi_req_t  dmi_req;
  logic          dmi_req_valid;
  logic          dmi_req_ready;
  dm::dmi_resp_t dmi_resp;
  logic          dmi_resp_ready;
  logic          dmi_resp_valid;

  logic dbg_req;
  logic dbg_we;
  logic [${regbus_debug.aw-1}:0] dbg_addr;
  logic [${regbus_debug.dw-1}:0] dbg_wdata;
  logic [${regbus_debug.dw//8-1}:0] dbg_wstrb;
  logic [${regbus_debug.dw-1}:0] dbg_rdata;
  logic dbg_rvalid;

  reg_to_mem #(
    .AW(${regbus_debug.aw}),
    .DW(${regbus_debug.dw}),
    .req_t (${regbus_debug.req_type()}),
    .rsp_t (${regbus_debug.rsp_type()})
  ) i_reg_to_mem_dbg (
    .clk_i (${regbus_debug.clk}),
    .rst_ni (${regbus_debug.rst}),
    .reg_req_i (${regbus_debug.req_name()}),
    .reg_rsp_o (${regbus_debug.rsp_name()}),
    .req_o (dbg_req),
    .gnt_i (dbg_req),
    .we_o (dbg_we),
    .addr_o (dbg_addr),
    .wdata_o (dbg_wdata),
    .wstrb_o (dbg_wstrb),
    .rdata_i (dbg_rdata),
    .rvalid_i (dbg_rvalid),
    .rerror_i (1'b0)
  );

  `FFARN(dbg_rvalid, dbg_req, 1'b0, ${regbus_debug.clk}, ${regbus_debug.rst})

  logic        sba_req;
  logic [${regbus_debug.aw-1}:0] sba_addr;
  logic        sba_we;
  logic [${regbus_debug.dw-1}:0] sba_wdata;
  logic [${regbus_debug.dw//8-1}:0]  sba_strb;
  logic        sba_gnt;

  logic [${regbus_debug.dw-1}:0] sba_rdata;
  logic        sba_rvalid;

  logic [${regbus_debug.dw-1}:0] sba_addr_long;

  dm_top #(
    .NrHarts (1),
    .BusWidth (${regbus_debug.dw}),
    .DmBaseAddress ('h0)
  ) i_dm_top (
    .clk_i (${regbus_debug.clk}),
    .rst_ni (${regbus_debug.rst}),
    .testmode_i (1'b0),
    .ndmreset_o (),
    .dmactive_o (),
    .debug_req_o (debug_req),
    .unavailable_i ('0),
    .hartinfo_i (hartinfo),
    .slave_req_i (dbg_req),
    .slave_we_i (dbg_we),
    .slave_addr_i ({${regbus_debug.dw-regbus_debug.aw}'b0, dbg_addr}),
    .slave_be_i (dbg_wstrb),
    .slave_wdata_i (dbg_wdata),
    .slave_rdata_o (dbg_rdata),
    .master_req_o (sba_req),
    .master_add_o (sba_addr_long),
    .master_we_o (sba_we),
    .master_wdata_o (sba_wdata),
    .master_be_o (sba_strb),
    .master_gnt_i (sba_gnt),
    .master_r_valid_i (sba_rvalid),
    .master_r_rdata_i (sba_rdata),
    .dmi_rst_ni (dmi_rst_n),
    .dmi_req_valid_i (dmi_req_valid),
    .dmi_req_ready_o (dmi_req_ready),
    .dmi_req_i (dmi_req),
    .dmi_resp_valid_o (dmi_resp_valid),
    .dmi_resp_ready_i (dmi_resp_ready),
    .dmi_resp_o (dmi_resp)
  );

  assign sba_addr = sba_addr_long[${regbus_debug.aw-1}:0];

  mem_to_axi_lite #(
    .MemAddrWidth (${regbus_debug.aw}),
    .AxiAddrWidth (${regbus_debug.aw}),
    .DataWidth (${regbus_debug.dw}),
    .MaxRequests (2),
    .AxiProt ('0),
    .axi_req_t (${soc_periph_xbar.in_debug.req_type()}),
    .axi_rsp_t (${soc_periph_xbar.in_debug.rsp_type()})
  ) i_mem_to_axi_lite (
    .clk_i (${regbus_debug.clk}),
    .rst_ni (${regbus_debug.rst}),
    .mem_req_i (sba_req),
    .mem_addr_i (sba_addr),
    .mem_we_i (sba_we),
    .mem_wdata_i (sba_wdata),
    .mem_be_i (sba_strb),
    .mem_gnt_o (sba_gnt),
    .mem_rsp_valid_o (sba_rvalid),
    .mem_rsp_rdata_o (sba_rdata),
    .mem_rsp_error_o (/* left open */),
    .axi_req_o (${soc_periph_xbar.in_debug.req_name()}),
    .axi_rsp_i (${soc_periph_xbar.in_debug.rsp_name()})

  );

  dmi_jtag #(
    .IdcodeValue (occamy_pkg::IDCode)
  ) i_dmi_jtag (
    .clk_i (${regbus_debug.clk}),
    .rst_ni (${regbus_debug.rst}),
    .testmode_i (1'b0),
    .dmi_rst_no (dmi_rst_n),
    .dmi_req_o (dmi_req),
    .dmi_req_valid_o (dmi_req_valid),
    .dmi_req_ready_i (dmi_req_ready),
    .dmi_resp_i (dmi_resp),
    .dmi_resp_ready_o (dmi_resp_ready),
    .dmi_resp_valid_i (dmi_resp_valid),
    .tck_i (jtag_tck_i),
    .tms_i (jtag_tms_i),
    .trst_ni (jtag_trst_ni),
    .td_i (jtag_tdi_i),
    .td_o (jtag_tdo_o),
    .tdo_oe_o ()
  );


  /////////
  // SPM //
  /////////
  // TODO(zarubaf): Add a tiny bit of SPM

  ///////////////
  //   CLINT   //
  ///////////////
  clint #(
    .AXI_ADDR_WIDTH (${soc_periph_xbar.out_clint.aw}),
    .AXI_DATA_WIDTH (${soc_periph_xbar.out_clint.dw}),
    .AXI_ID_WIDTH (0),
    .NR_CORES (1),
    .axi_req_t (${soc_periph_xbar.out_clint.req_type()}),
    .axi_resp_t (${soc_periph_xbar.out_clint.rsp_type()})
  ) i_clint (
    .clk_i (${soc_periph_xbar.out_clint.clk}),
    .rst_ni (${soc_periph_xbar.out_clint.rst}),
    .testmode_i (1'b0),
    .axi_req_i (${soc_periph_xbar.out_clint.req_name()}),
    .axi_resp_o (${soc_periph_xbar.out_clint.rsp_name()}),
    .rtc_i (rtc_i),
    .timer_irq_o (mtip),
    .ipi_o (msip)
  );

  /////////////////////
  //   SOC CONTROL   //
  /////////////////////
  occamy_soc_reg_top #(
    .reg_req_t ( ${soc_regbus_periph_xbar.out_soc_ctrl.req_type()} ),
    .reg_rsp_t ( ${soc_regbus_periph_xbar.out_soc_ctrl.rsp_type()} )
  ) i_soc_ctrl (
    .clk_i     ( clk_i  ),
    .rst_ni    ( rst_ni ),
    .reg_req_i ( ${soc_regbus_periph_xbar.out_soc_ctrl.req_name()} ),
    .reg_rsp_o ( ${soc_regbus_periph_xbar.out_soc_ctrl.rsp_name()} ),
    .reg2hw    ( soc_ctrl_in ),
    .hw2reg    ( soc_ctrl_out ),
    .devmode_i ( 1'b1 )
  );

  //////////////
  //   UART   //
  //////////////
  uart #(
    .reg_req_t (${soc_regbus_periph_xbar.out_uart.req_type()} ),
    .reg_rsp_t (${soc_regbus_periph_xbar.out_uart.rsp_type()} )
  ) i_uart (
    .clk_i (${soc_regbus_periph_xbar.out_uart.clk}),
    .rst_ni (${soc_regbus_periph_xbar.out_uart.rst}),
    .reg_req_i (${soc_regbus_periph_xbar.out_uart.req_name()}),
    .reg_rsp_o (${soc_regbus_periph_xbar.out_uart.rsp_name()}),
    .cio_tx_o (uart_tx_o),
    .cio_rx_i (uart_rx_i),
    .cio_tx_en_o (),
    .intr_tx_watermark_o (irq.uart_tx_watermark),
    .intr_rx_watermark_o (irq.uart_rx_watermark),
    .intr_tx_empty_o (irq.uart_tx_empty),
    .intr_rx_overflow_o (irq.uart_rx_overflow),
    .intr_rx_frame_err_o (irq.uart_rx_frame_err),
    .intr_rx_break_err_o (irq.uart_rx_break_err),
    .intr_rx_timeout_o (irq.uart_rx_timeout),
    .intr_rx_parity_err_o (irq.uart_rx_parity_err)
  );

  /////////////
  //   ROM   //
  /////////////

  // This is very system specific, so we might be better off
  // placing it outside the top-level.
  assign bootrom_req_o = ${soc_regbus_periph_xbar.out_bootrom.req_name()};
  assign ${soc_regbus_periph_xbar.out_bootrom.rsp_name()} = bootrom_rsp_i;

  /////////////////
  //   Clk Mgr   //
  /////////////////

  assign clk_mgr_req_o = ${soc_regbus_periph_xbar.out_clk_mgr.req_name()};
  assign ${soc_regbus_periph_xbar.out_clk_mgr.rsp_name()} = clk_mgr_rsp_i;

  //////////////
  //   PLIC   //
  //////////////
  rv_plic #(
    .reg_req_t (${soc_regbus_periph_xbar.out_plic.req_type()}),
    .reg_rsp_t (${soc_regbus_periph_xbar.out_plic.rsp_type()})
  ) i_rv_plic (
    .clk_i (${soc_regbus_periph_xbar.out_plic.clk}),
    .rst_ni (${soc_regbus_periph_xbar.out_plic.rst}),
    .reg_req_i (${soc_regbus_periph_xbar.out_plic.req_name()}),
    .reg_rsp_o (${soc_regbus_periph_xbar.out_plic.rsp_name()}),
    .intr_src_i (irq),
    .irq_o (eip),
    .irq_id_o (),
    .msip_o ()
  );

  //////////////////
  //   SPI Host   //
  //////////////////
  spi_host #(
    .reg_req_t (${soc_regbus_periph_xbar.out_spim.req_type()}),
    .reg_rsp_t (${soc_regbus_periph_xbar.out_spim.rsp_type()})
  ) i_spi_host (
    // TODO(zarubaf): Fix clock assignment
    .clk_i  (${soc_regbus_periph_xbar.out_spim.clk}),
    .rst_ni (${soc_regbus_periph_xbar.out_spim.rst}),
    .clk_core_i (${soc_regbus_periph_xbar.out_spim.clk}),
    .rst_core_ni (${soc_regbus_periph_xbar.out_spim.rst}),
    .reg_req_i (${soc_regbus_periph_xbar.out_spim.req_name()}),
    .reg_rsp_o (${soc_regbus_periph_xbar.out_spim.rsp_name()}),
    .cio_sck_o (spim_sck_o),
    .cio_sck_en_o (spim_sck_en_o),
    .cio_csb_o (spim_csb_o),
    .cio_csb_en_o (spim_csb_en_o),
    .cio_sd_o (spim_sd_o),
    .cio_sd_en_o (spim_sd_en_o),
    .cio_sd_i (spim_sd_i),
    .intr_error_o (irq.spim_error),
    .intr_spi_event_o (irq.spim_spi_event)
  );

  //////////////
  //   GPIO   //
  //////////////
  gpio #(
    .reg_req_t (${soc_regbus_periph_xbar.out_gpio.req_type()}),
    .reg_rsp_t (${soc_regbus_periph_xbar.out_gpio.rsp_type()})
  ) i_gpio (
    .clk_i (${soc_regbus_periph_xbar.out_gpio.clk}),
    .rst_ni (${soc_regbus_periph_xbar.out_gpio.rst}),
    .reg_req_i (${soc_regbus_periph_xbar.out_gpio.req_name()}),
    .reg_rsp_o (${soc_regbus_periph_xbar.out_gpio.rsp_name()}),
    .cio_gpio_i (gpio_d_i),
    .cio_gpio_o (gpio_d_o),
    .cio_gpio_en_o (gpio_oe_o),
    .intr_gpio_o (irq.gpio)
  );

  /////////////
  //   I2C   //
  /////////////
  i2c #(
    .reg_req_t (${soc_regbus_periph_xbar.out_i2c.req_type()}),
    .reg_rsp_t (${soc_regbus_periph_xbar.out_i2c.rsp_type()})
  ) i_i2c (
    .clk_i (${soc_regbus_periph_xbar.out_i2c.clk}),
    .rst_ni (${soc_regbus_periph_xbar.out_i2c.rst}),
    .reg_req_i (${soc_regbus_periph_xbar.out_i2c.req_name()}),
    .reg_rsp_o (${soc_regbus_periph_xbar.out_i2c.rsp_name()}),
    .cio_scl_i (i2c_scl_i),
    .cio_scl_o (i2c_scl_o),
    .cio_scl_en_o (i2c_scl_en_o),
    .cio_sda_i (i2c_sda_i),
    .cio_sda_o (i2c_sda_o),
    .cio_sda_en_o (i2c_sda_en_o),
    .intr_fmt_watermark_o (irq.i2c_fmt_watermark),
    .intr_rx_watermark_o (irq.i2c_rx_watermark),
    .intr_fmt_overflow_o (irq.i2c_fmt_overflow),
    .intr_rx_overflow_o (irq.i2c_rx_overflow),
    .intr_nak_o (irq.i2c_nak),
    .intr_scl_interference_o (irq.i2c_scl_interference),
    .intr_sda_interference_o (irq.i2c_sda_interference),
    .intr_stretch_timeout_o (irq.i2c_stretch_timeout),
    .intr_sda_unstable_o (irq.i2c_sda_unstable),
    .intr_trans_complete_o (irq.i2c_trans_complete),
    .intr_tx_empty_o (irq.i2c_tx_empty),
    .intr_tx_nonempty_o (irq.i2c_tx_nonempty),
    .intr_tx_overflow_o (irq.i2c_tx_overflow),
    .intr_acq_overflow_o (irq.i2c_acq_overflow),
    .intr_ack_stop_o (irq.i2c_ack_stop),
    .intr_host_timeout_o (irq.i2c_host_timeout)
  );

endmodule
