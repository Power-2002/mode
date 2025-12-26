`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/12/15 16:42:39
// Design Name: 
// Module Name: adder_tree
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
module adder_tree #(
    parameter PSUM_W = 18
)(
    input  wire clk,
    input  wire rst_n,
    input  wire in_valid0,
    input  wire in_valid1,
    input  wire in_valid2,
    input  wire signed [PSUM_W-1:0] psum0,
    input  wire signed [PSUM_W-1:0] psum1,
    input  wire signed [PSUM_W-1:0] psum2,
    output reg  signed [31:0] out_sum,  
    output reg  out_valid
);

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            out_sum   <= 0;
            out_valid <= 1'b0;
        end else if (in_valid0 && in_valid1 && in_valid2) begin
            out_sum   <= psum0 + psum1 + psum2;
            out_valid <= 1'b1;
        end else begin
            out_valid <= 1'b0;
        end
    end

endmodule