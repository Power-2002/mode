`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/12/15 16:40:01
// Design Name: 
// Module Name: dwc_pu
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

module dwc_pu#(
    parameter UNIT_NUM = 16,
    parameter K = 3,
    parameter DATA_W = 8,
    parameter PROD_W = 16,
    parameter PSUM_W = 18,
    parameter TILE_H = 6
)(
    input wire clk,
    input wire rst_n,
    input wire in_valid,
    
    input wire [UNIT_NUM*TILE_H*DATA_W-1:0] column_data,
    input wire [UNIT_NUM*3*K*DATA_W-1:0] weights,
    
    output wire [UNIT_NUM*4*32-1:0] out_sums,
    output wire [UNIT_NUM*4-1:0] out_valids
);

    genvar i;
    generate
        for (i = 0; i < UNIT_NUM; i = i + 1) begin: dwc_units
            
            wire [DATA_W-1:0] row_data [0:TILE_H-1];
            
            for (genvar r = 0; r < TILE_H; r = r + 1) begin
                assign row_data[r] = column_data[i*TILE_H*DATA_W + r*DATA_W +: DATA_W];
            end
            
            dwc_unit #(
                .K(K), 
                .DATA_W(DATA_W), 
                .PROD_W(PROD_W), 
                .PSUM_W(PSUM_W)
            ) u_dwc (
                .clk(clk),
                .rst_n(rst_n),
                .in_valid(in_valid),
                .buffer0(row_data[0]),
                .buffer1(row_data[1]),
                .buffer2(row_data[2]),
                .buffer3(row_data[3]),
                .buffer4(row_data[4]),
                .buffer5(row_data[5]),
                .w_col0(weights[i*3*K*DATA_W + 0*K*DATA_W +: K*DATA_W]),
                .w_col1(weights[i*3*K*DATA_W + 1*K*DATA_W +: K*DATA_W]),
                .w_col2(weights[i*3*K*DATA_W + 2*K*DATA_W +: K*DATA_W]),
                .out_sum0(out_sums[i*4*32 + 0*32 +: 32]),
                .out_sum1(out_sums[i*4*32 + 1*32 +: 32]),
                .out_sum2(out_sums[i*4*32 + 2*32 +: 32]),
                .out_sum3(out_sums[i*4*32 + 3*32 +: 32]),
                .out_valid0(out_valids[i*4 + 0]),
                .out_valid1(out_valids[i*4 + 1]),
                .out_valid2(out_valids[i*4 + 2]),
                .out_valid3(out_valids[i*4 + 3])
            );
        end
    endgenerate

endmodule
