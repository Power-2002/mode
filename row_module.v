`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/12/15 16:41:40
// Design Name: 
// Module Name: row_module
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
//column-serial depthwise3*3 conv row module

module row_module#(
    parameter K = 3,
    parameter DATA_W = 8,
    parameter PROD_W = 16,
    parameter PSUM_W = 18
)(
    input  wire clk,
    input  wire rst_n,
    input  wire in_valid,
    //input  wire [K*DATA_W-1:0] din,

    //Three pixels in the same column
    input  wire signed [DATA_W-1:0] in_r0_c,
    input  wire signed [DATA_W-1:0] in_r1_c,
    input  wire signed [DATA_W-1:0] in_r2_c,
    

    //Three-column weights (fixed)
    input  wire [K*DATA_W-1:0] w_col0, //{w20,w10,w00}
    input  wire [K*DATA_W-1:0] w_col1, //{w21,w11,w01}
    input  wire [K*DATA_W-1:0] w_col2, //{w22,w12,w02}
    
    output wire signed [31:0] out_sum,
    output wire out_valid
);

    //{r2,r1,r0}, LSB is r0
    wire [K*DATA_W-1:0] vec_s0 = {in_r2_c, in_r1_c, in_r0_c};

    reg  [K*DATA_W-1:0] vec_s1;  // delay 1 clock
    reg  [K*DATA_W-1:0] vec_s2;  // delay 2 clock
    reg                  v_s0, v_s1, v_s2; // in_valid delay chain


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vec_s1 <= {K*DATA_W{1'b0}};
            vec_s2 <= {K*DATA_W{1'b0}};
            v_s0   <= 1'b0;
            v_s1   <= 1'b0;
            v_s2   <= 1'b0;
        end else begin
            v_s0   <= in_valid;
            v_s1   <= v_s0;
            v_s2   <= v_s1;
            vec_s1 <= vec_s0;  // s1 = s0 delay 1 cycle
            vec_s2 <= vec_s1;  // s2 = s1 delay 2 cycle
        end
    end

    //Three PE: Each uses its own weight to process the same column  with different phases.

    wire signed [PSUM_W-1:0] ps0, ps1, ps2;
    wire v0p, v1p, v2p;  // PE output valid
   
    
    PE #(.K(K), .DATA_W(DATA_W), .PROD_W(PROD_W), .PSUM_W(PSUM_W)) u_PE0 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_s2), .in_data(vec_s2), .weight(w_col0),
        .partial_sum(ps0), .partial_valid(v0p)
    );

    PE #(.K(K), .DATA_W(DATA_W), .PROD_W(PROD_W), .PSUM_W(PSUM_W)) u_PE1 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_s1), .in_data(vec_s1), .weight(w_col1),
        .partial_sum(ps1), .partial_valid(v1p)
    );
    //newest
    PE #(.K(K), .DATA_W(DATA_W), .PROD_W(PROD_W), .PSUM_W(PSUM_W)) u_PE2 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_s0), .in_data(vec_s0), .weight(w_col2),
        .partial_sum(ps2), .partial_valid(v2p)
    );
   
    adder_tree #(.PSUM_W(PSUM_W)) u_adder (
        .clk(clk), .rst_n(rst_n),
        .in_valid0(v0p), .in_valid1(v1p), .in_valid2(v2p),
        .psum0(ps0), .psum1(ps1), .psum2(ps2),
        .out_sum(out_sum),
        .out_valid(out_valid)
    );
endmodule
