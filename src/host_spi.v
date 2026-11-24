/*
 * Copyright (c) 2026 Zixin (Stan) Wan
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// Host port: SPI target, mode 0, MSB first, SCK <= clk / 8 (7.5 MHz at 60 MHz).
//
// The host (RP2350 on the demo board) uses it to load programs and data and to
// read results. SCK, COPI and CS_n are asynchronous to clk and pass through a
// two-flop synchroniser; the port runs entirely in the clk domain.
//
// Frame (CS_n low for the whole frame):
//   WRITE: 0x02, addr[15:8], addr[7:0], data0[15:8], data0[7:0], data1 ...
//   READ : 0x03, addr[15:8], addr[7:0], dummy byte,  data0 ...  (data on CIPO)
// The word address auto-increments after every data word. Any other opcode
// makes the rest of the frame a no-op. CIPO is 0 outside the read data phase.
//
// Bus side: bus_req is a one-cycle strobe with bus_we/bus_addr/bus_wdata valid
// in the same cycle (all registered). For reads the bus answers with a
// one-cycle bus_rvalid some cycles later (2 in this design); the port only
// needs the word before the next 16 SCK periods are over.
module host_spi (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        sck_in,
    input  wire        copi_in,
    input  wire        csn_in,
    output reg         cipo,

    output reg         bus_req,
    output reg         bus_we,
    output reg  [15:0] bus_addr,
    output reg  [15:0] bus_wdata,
    input  wire [15:0] bus_rdata,
    input  wire        bus_rvalid
);

  localparam OP_WRITE = 8'h02;
  localparam OP_READ  = 8'h03;

  localparam PH_OPCODE = 3'd0;
  localparam PH_ADDR   = 3'd1;
  localparam PH_WDATA  = 3'd2;
  localparam PH_DUMMY  = 3'd3;
  localparam PH_RDATA  = 3'd4;
  localparam PH_IGNORE = 3'd5;

  // ---- Synchronisers --------------------------------------------------------
  reg [2:0] sck_s;   // [0],[1] synchroniser, [2] previous value for edge detect
  reg [1:0] copi_s;
  reg [1:0] csn_s;

  always @(posedge clk) begin
    if (!rst_n) begin
      sck_s  <= 3'b000;
      copi_s <= 2'b00;
      csn_s  <= 2'b11;
    end else begin
      sck_s  <= {sck_s[1:0], sck_in};
      copi_s <= {copi_s[0], copi_in};
      csn_s  <= {csn_s[0], csn_in};
    end
  end

  wire sck_rise = sck_s[1] & ~sck_s[2];
  wire sck_fall = ~sck_s[1] & sck_s[2];
  wire copi     = copi_s[1];
  wire cs_act   = ~csn_s[1];

  // ---- Frame state ----------------------------------------------------------
  reg [2:0]  phase;
  reg [3:0]  bit_cnt;     // bits received in the current field, minus one
  reg [14:0] shift_in;    // the 16th bit comes straight from copi
  reg [15:0] addr;        // next word address
  reg [15:0] rd_buf;      // prefetched read word
  reg [15:0] tx;          // word being shifted out
  reg [3:0]  tx_left;     // bits still to shift out of tx

  wire [15:0] shifted = {shift_in, copi};

  always @(posedge clk) begin
    if (!rst_n) begin
      phase     <= PH_OPCODE;
      bit_cnt   <= 4'd0;
      shift_in  <= 15'd0;
      addr      <= 16'd0;
      rd_buf    <= 16'd0;
      tx        <= 16'd0;
      tx_left   <= 4'd0;
      cipo      <= 1'b0;
      bus_req   <= 1'b0;
      bus_we    <= 1'b0;
      bus_addr  <= 16'd0;
      bus_wdata <= 16'd0;
    end else begin
      bus_req <= 1'b0;

      if (bus_rvalid) begin
        rd_buf <= bus_rdata;
      end

      if (!cs_act) begin
        phase   <= PH_OPCODE;
        bit_cnt <= 4'd0;
        tx_left <= 4'd0;
        cipo    <= 1'b0;
      end else begin
        // Sample on the rising edge.
        if (sck_rise) begin
          shift_in <= shifted[14:0];
          bit_cnt  <= bit_cnt + 4'd1;
          case (phase)
            PH_OPCODE: if (bit_cnt == 4'd7) begin
              bit_cnt <= 4'd0;
              if (shifted[7:0] == OP_WRITE || shifted[7:0] == OP_READ) begin
                bus_we <= (shifted[7:0] == OP_WRITE);
                phase  <= PH_ADDR;
              end else begin
                phase  <= PH_IGNORE;
              end
            end
            PH_ADDR: if (bit_cnt == 4'd15) begin
              bit_cnt <= 4'd0;
              if (bus_we) begin
                addr  <= shifted;
                phase <= PH_WDATA;
              end else begin
                // First read goes out now; the dummy byte covers its latency.
                bus_req  <= 1'b1;
                bus_addr <= shifted;
                addr     <= shifted + 16'd1;
                phase    <= PH_DUMMY;
              end
            end
            PH_WDATA: if (bit_cnt == 4'd15) begin
              bit_cnt   <= 4'd0;
              bus_req   <= 1'b1;
              bus_addr  <= addr;
              bus_wdata <= shifted;
              addr      <= addr + 16'd1;
            end
            PH_DUMMY: if (bit_cnt == 4'd7) begin
              bit_cnt <= 4'd0;
              tx_left <= 4'd0;
              phase   <= PH_RDATA;
            end
            default: bit_cnt <= 4'd0;   // PH_RDATA, PH_IGNORE: inputs ignored
          endcase
        end

        // Shift out on the falling edge.
        if (sck_fall && phase == PH_RDATA) begin
          if (tx_left == 4'd0) begin
            cipo     <= rd_buf[15];
            tx       <= {rd_buf[14:0], 1'b0};
            tx_left  <= 4'd15;
            // Prefetch the next word.
            bus_req  <= 1'b1;
            bus_addr <= addr;
            addr     <= addr + 16'd1;
          end else begin
            cipo    <= tx[15];
            tx      <= {tx[14:0], 1'b0};
            tx_left <= tx_left - 4'd1;
          end
        end
      end
    end
  end

endmodule
