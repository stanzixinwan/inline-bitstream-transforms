/*
 * Copyright (c) 2026 Zixin (Stan) Wan
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// Inline Bitstream Transforms -- Milestone 1 skeleton.
//
// What is here: the host SPI port, the word bus behind it, the three SRAM
// macros of the final design (Proposal v5, section 7) and a few CSRs. The
// protocol CPU, the two field-level state machines, the bit timers and the
// transform units attach to the same bus in later milestones; until then the
// protocol pins are driven from CSRs so the pad ring can be exercised.
//
// Pins
//   ui_in[0]  host SCK         uo_out[0]  host CIPO
//   ui_in[1]  host COPI        uo_out[1]  host IRQ
//   ui_in[2]  host CS_n        uo_out[7:2] protocol outputs (GPIO_OUT[5:0])
//   ui_in[7:3] protocol inputs uio[7:0]   protocol bidirectional (GPIO_OUT[15:8], GPIO_OE)
//
// Word address map (16-bit words)
//   0x0000-0x03FF  shared SRAM, 1024x16 (CPU program, data, frame buffers)
//   0x1000-0x10FF  SM0 private SRAM, 256x16
//   0x1100-0x11FF  SM1 private SRAM, 256x16
//   0x8000-0x8007  CSRs (see below); unmapped addresses read 0
module tt_um_stanzixinwan_ibt (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  localparam [15:0] CHIP_ID      = 16'hB175;
  localparam [15:0] CHIP_VERSION = 16'h0001;   // milestone 1 skeleton

  // ---- Reset synchroniser ---------------------------------------------------
  reg [1:0] rst_s;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) rst_s <= 2'b00;
    else        rst_s <= {rst_s[0], 1'b1};
  end
  wire rst_n_i = rst_s[1];

  // ---- Host port --------------------------------------------------------------
  wire        bus_req, bus_we;
  wire [15:0] bus_addr, bus_wdata;
  reg  [15:0] bus_rdata;
  reg         bus_rvalid;
  wire        host_cipo;

  host_spi u_host (
      .clk       (clk),
      .rst_n     (rst_n_i),
      .sck_in    (ui_in[0]),
      .copi_in   (ui_in[1]),
      .csn_in    (ui_in[2]),
      .cipo      (host_cipo),
      .bus_req   (bus_req),
      .bus_we    (bus_we),
      .bus_addr  (bus_addr),
      .bus_wdata (bus_wdata),
      .bus_rdata (bus_rdata),
      .bus_rvalid(bus_rvalid)
  );

  // ---- Address decode -------------------------------------------------------
  wire sel_shared = (bus_addr[15:10] == 6'b000000);
  wire sel_sm0    = (bus_addr[15:8]  == 8'h10);
  wire sel_sm1    = (bus_addr[15:8]  == 8'h11);
  wire sel_csr    = (bus_addr[15:3]  == 13'h1000);   // 0x8000-0x8007

  // ---- CSRs -----------------------------------------------------------------
  //   0x8000 ID        RO  0xB175
  //   0x8001 VERSION   RO  0x0001
  //   0x8002 SCRATCH   RW
  //   0x8003 GPIO_OUT  RW  [5:0] -> uo_out[7:2], [15:8] -> uio_out[7:0]
  //   0x8004 GPIO_OE   RW  [7:0] -> uio_oe[7:0]
  //   0x8005 GPIO_IN   RO  {uio_in, ui_in}, synchronised
  //   0x8006 IRQ       RW  [0] drives the host IRQ pin
  //   0x8007 CYCLES    RO  free-running cycle counter (low 16 bits)
  reg [15:0] scratch;
  reg [15:0] gpio_out;
  reg [7:0]  gpio_oe;
  reg        irq;
  reg [15:0] cycles;
  reg [15:0] gpio_in_s1, gpio_in_s2;

  always @(posedge clk) begin
    if (!rst_n_i) begin
      scratch    <= 16'd0;
      gpio_out   <= 16'd0;
      gpio_oe    <= 8'd0;
      irq        <= 1'b0;
      cycles     <= 16'd0;
      gpio_in_s1 <= 16'd0;
      gpio_in_s2 <= 16'd0;
    end else begin
      cycles     <= cycles + 16'd1;
      gpio_in_s1 <= {uio_in, ui_in};
      gpio_in_s2 <= gpio_in_s1;
      if (bus_req && bus_we && sel_csr) begin
        case (bus_addr[2:0])
          3'd2: scratch  <= bus_wdata;
          3'd3: gpio_out <= bus_wdata;
          3'd4: gpio_oe  <= bus_wdata[7:0];
          3'd6: irq      <= bus_wdata[0];
          default: ;
        endcase
      end
    end
  end

  reg [15:0] csr_rdata;
  always @(*) begin
    case (bus_addr[2:0])
      3'd0:    csr_rdata = CHIP_ID;
      3'd1:    csr_rdata = CHIP_VERSION;
      3'd2:    csr_rdata = scratch;
      3'd3:    csr_rdata = gpio_out;
      3'd4:    csr_rdata = {8'd0, gpio_oe};
      3'd5:    csr_rdata = gpio_in_s2;
      3'd6:    csr_rdata = {15'd0, irq};
      default: csr_rdata = cycles;
    endcase
  end

  // ---- SRAM macros ----------------------------------------------------------
  // Every macro input comes from a flip-flop (bus_* are registered in
  // u_host). A macro samples on the edge after bus_req; its output is valid
  // during the following cycle and is captured into bus_rdata on the edge
  // after that, together with bus_rvalid.
  wire        rd = bus_req & ~bus_we;
  wire        wr = bus_req &  bus_we;
  wire [15:0] dout_shared, dout_sm0, dout_sm1;

  // Instance names are referenced by MACROS and PDN_MACRO_CONNECTIONS in src/config.json.
  RM_IHPSG13_1P_1024x16_c2_bm_bist u_mem_shared (
      .A_CLK      (clk),
      .A_MEN      (bus_req & sel_shared),
      .A_WEN      (wr),
      .A_REN      (rd),
      .A_ADDR     (bus_addr[9:0]),
      .A_DIN      (bus_wdata),
      .A_DLY      (1'b1),               // must be tied high (see the macro datasheet)
      .A_DOUT     (dout_shared),
      .A_BM       (16'hFFFF),
      .A_BIST_CLK (1'b0),
      .A_BIST_EN  (1'b0),
      .A_BIST_MEN (1'b0),
      .A_BIST_WEN (1'b0),
      .A_BIST_REN (1'b0),
      .A_BIST_ADDR(10'd0),
      .A_BIST_DIN (16'd0),
      .A_BIST_BM  (16'd0)
  );

  RM_IHPSG13_1P_256x16_c2_bm_bist u_mem_sm0 (
      .A_CLK      (clk),
      .A_MEN      (bus_req & sel_sm0),
      .A_WEN      (wr),
      .A_REN      (rd),
      .A_ADDR     (bus_addr[7:0]),
      .A_DIN      (bus_wdata),
      .A_DLY      (1'b1),
      .A_DOUT     (dout_sm0),
      .A_BM       (16'hFFFF),
      .A_BIST_CLK (1'b0),
      .A_BIST_EN  (1'b0),
      .A_BIST_MEN (1'b0),
      .A_BIST_WEN (1'b0),
      .A_BIST_REN (1'b0),
      .A_BIST_ADDR(8'd0),
      .A_BIST_DIN (16'd0),
      .A_BIST_BM  (16'd0)
  );

  RM_IHPSG13_1P_256x16_c2_bm_bist u_mem_sm1 (
      .A_CLK      (clk),
      .A_MEN      (bus_req & sel_sm1),
      .A_WEN      (wr),
      .A_REN      (rd),
      .A_ADDR     (bus_addr[7:0]),
      .A_DIN      (bus_wdata),
      .A_DLY      (1'b1),
      .A_DOUT     (dout_sm1),
      .A_BM       (16'hFFFF),
      .A_BIST_CLK (1'b0),
      .A_BIST_EN  (1'b0),
      .A_BIST_MEN (1'b0),
      .A_BIST_WEN (1'b0),
      .A_BIST_REN (1'b0),
      .A_BIST_ADDR(8'd0),
      .A_BIST_DIN (16'd0),
      .A_BIST_BM  (16'd0)
  );

  // ---- Read return ----------------------------------------------------------
  localparam SRC_NONE = 2'd0, SRC_SHARED = 2'd1, SRC_SM = 2'd2, SRC_CSR = 2'd3;
  reg [1:0]  rd_src_q;
  reg        rd_sm1_q;
  reg        rd_pend_q;
  reg [15:0] csr_rdata_q;

  always @(posedge clk) begin
    if (!rst_n_i) begin
      rd_pend_q   <= 1'b0;
      rd_src_q    <= SRC_NONE;
      rd_sm1_q    <= 1'b0;
      csr_rdata_q <= 16'd0;
      bus_rvalid  <= 1'b0;
      bus_rdata   <= 16'd0;
    end else begin
      rd_pend_q   <= rd;
      rd_src_q    <= sel_shared ? SRC_SHARED :
                     (sel_sm0 | sel_sm1) ? SRC_SM :
                     sel_csr ? SRC_CSR : SRC_NONE;
      rd_sm1_q    <= sel_sm1;
      csr_rdata_q <= csr_rdata;

      bus_rvalid <= rd_pend_q;
      if (rd_pend_q) begin
        case (rd_src_q)
          SRC_SHARED: bus_rdata <= dout_shared;
          SRC_SM:     bus_rdata <= rd_sm1_q ? dout_sm1 : dout_sm0;
          SRC_CSR:    bus_rdata <= csr_rdata_q;
          default:    bus_rdata <= 16'd0;
        endcase
      end
    end
  end

  // ---- Outputs --------------------------------------------------------------
  assign uo_out  = {gpio_out[5:0], irq, host_cipo};
  assign uio_out = gpio_out[15:8];
  assign uio_oe  = gpio_oe;

  // List all unused inputs to prevent warnings
  wire _unused = &{ena, gpio_out[7:6], 1'b0};

endmodule
