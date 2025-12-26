`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/12/15 16:40:36
// Design Name: 
// Module Name: dwc_unit
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

module dwc_unit#(
    parameter K = 3,
    parameter DATA_W = 8,
    parameter PROD_W = 16,
    parameter PSUM_W = 18
)(
    input  wire clk,
    input  wire rst_n,
    input  wire in_valid,
    
    // Six rows of input feature map
    input  wire signed [DATA_W-1:0] buffer0, // row0
    input  wire signed [DATA_W-1:0] buffer1, // row1
    input  wire signed [DATA_W-1:0] buffer2, // row2
    input  wire signed [DATA_W-1:0] buffer3, // row3
    input  wire signed [DATA_W-1:0] buffer4, // row4
    input  wire signed [DATA_W-1:0] buffer5, // row5    

    input  wire [K*DATA_W-1:0] w_col0,
    input  wire [K*DATA_W-1:0] w_col1,
    input  wire [K*DATA_W-1:0] w_col2,

    output wire signed [31:0] out_sum0,
    output wire signed [31:0] out_sum1,
    output wire signed [31:0] out_sum2,
    output wire signed [31:0] out_sum3,
    output wire out_valid0,
    output wire out_valid1,
    output wire out_valid2,
    output wire out_valid3
);

    // row0 read buffer0, buffer1, buffer2
    row_module #(.K(K), .DATA_W(DATA_W), .PROD_W(PROD_W), .PSUM_W(PSUM_W)) row0 (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid),
        .in_r0_c(buffer0), .in_r1_c(buffer1), .in_r2_c(buffer2),
        .w_col0(w_col0), .w_col1(w_col1), .w_col2(w_col2),
        .out_sum(out_sum0), .out_valid(out_valid0)
    );
    // row1 read buffer1, buffer2, buffer3
    row_module #(.K(K), .DATA_W(DATA_W), .PROD_W(PROD_W), .PSUM_W(PSUM_W)) row1 (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid),
        .in_r0_c(buffer1), .in_r1_c(buffer2), .in_r2_c(buffer3),
        .w_col0(w_col0), .w_col1(w_col1), .w_col2(w_col2),
        .out_sum(out_sum1), .out_valid(out_valid1)
    );
    // row2 read buffer2, buffer3, buffer4
    row_module #(.K(K), .DATA_W(DATA_W), .PROD_W(PROD_W), .PSUM_W(PSUM_W)) row2 (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid),
        .in_r0_c(buffer2), .in_r1_c(buffer3), .in_r2_c(buffer4),
        .w_col0(w_col0), .w_col1(w_col1), .w_col2(w_col2),
        .out_sum(out_sum2), .out_valid(out_valid2)
    );
    // row3 read buffer3, buffer4, buffer5
    row_module #(.K(K), .DATA_W(DATA_W), .PROD_W(PROD_W), .PSUM_W(PSUM_W)) row3 (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid),
        .in_r0_c(buffer3), .in_r1_c(buffer4), .in_r2_c(buffer5),
        .w_col0(w_col0), .w_col1(w_col1), .w_col2(w_col2),
        .out_sum(out_sum3), .out_valid(out_valid3)
    );
    
endmodule
