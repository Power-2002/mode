`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/12/15 16:33:02
// Design Name: 
// Module Name: requantize16
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
module requantize16#(
  parameter integer LANES         = 16,
  parameter integer ACC_BITS      = 32,
  parameter integer OUT_BITS      = 8
)(
  input  wire                      CLK,
  input  wire                      RESET,
  input  wire                      en,
  input  wire [LANES*ACC_BITS-1:0] in_acc,     // 16x int32
  input  wire [LANES*32-1:0]       bias_in,    // [New] External Bias Input

  input  wire  signed [31:0]       cfg_mult_scalar,
  input  wire         [5:0]        cfg_shift_scalar,
  input  wire                      cfg_symmetric,
  input  wire  signed [7:0]        cfg_zp_out,

  output reg  [LANES*OUT_BITS-1:0] out_q,
  output reg                       out_valid
);

  function [7:0] sat_s8; input signed [31:0] x;
    begin
      if (x > 32'sd127)       sat_s8 = 8'sd127;
      else if (x < -32'sd128) sat_s8 = -8'sd128;
      else                    sat_s8 = x[7:0];
    end
  endfunction

  function signed [31:0] rshift_round;
    input signed [63:0] val; input [5:0] sh;
    reg signed [63:0] add;
    begin
      if (sh == 0) rshift_round = val[31:0];
      else begin
        add = val + (64'sd1 << (sh-1));
        rshift_round = (add >>> sh);
      end
    end
  endfunction

  reg en_d1, en_d2; // Pipeline valid

  genvar gi;
  generate
    for (gi=0; gi<LANES; gi=gi+1) begin : G
      wire signed [ACC_BITS-1:0] acc_i = in_acc[gi*ACC_BITS + ACC_BITS-1 : gi*ACC_BITS];
      wire signed [31:0]         bias_i = bias_in[gi*32 + 31 : gi*32];

      reg signed [63:0] p1_prod;
      reg signed [31:0] p2_res;
      
      always @(posedge CLK or negedge RESET) begin
        if (!RESET) begin
          p1_prod <= 0; p2_res <= 0; 
          out_q[gi*OUT_BITS +: OUT_BITS] <= 0;
        end else begin
          // Stage 1: Add Bias & Multiply
          if (en) begin
             p1_prod <= ($signed(acc_i) + bias_i) * $signed(cfg_mult_scalar);
          end
          // Stage 2: Shift & Round
          if (en_d1) begin
             p2_res <= rshift_round(p1_prod, cfg_shift_scalar) + (cfg_symmetric ? 32'sd0 : {{24{cfg_zp_out[7]}}, cfg_zp_out});
          end
          // Stage 3: Saturate
          if (en_d2) begin
             out_q[gi*OUT_BITS +: OUT_BITS] <= sat_s8(p2_res);
          end
        end
      end
    end
  endgenerate

  always @(posedge CLK or negedge RESET) begin
    if (!RESET) begin
      en_d1 <= 0; en_d2 <= 0; out_valid <= 0;
    end else begin
      en_d1 <= en;
      en_d2 <= en_d1;
      out_valid <= en_d2; 
    end
  end
endmodule
