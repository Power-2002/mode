`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/12/15 16:42:10
// Design Name: 
// Module Name: PE
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

module PE#(
    parameter K=3,
    parameter DATA_W=8,
    parameter PROD_W=16,//int8 * int8=int 16
    parameter PSUM_W=18//sum
)(
    input wire clk,
    input wire rst_n,//Reset signal, active low
    input wire in_valid,//input valid
    input wire [K*DATA_W-1:0] in_data,//input
    input wire [K*DATA_W-1:0] weight,
    //`partial_sum`is an accumulator that must be updated on the rising edge of the clock (to preserve the calculation result), so it must be declared as a register type.
    //`in_data` and `weight` are merely "packed bit vectors?? and do not directly participate in computations.
    output reg signed [PSUM_W-1:0] partial_sum,
    output reg partial_valid
    );

    integer i;
    reg signed [PROD_W-1:0] prod_reg [0:K-1];//K product results
    reg valid_d1;
    
    // Stage0: capture inputs and compute products (combinational, register them)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for(i=0;i<K;i=i+1) prod_reg[i] <=0;
            valid_d1<= 1'b0;
        end else begin
            valid_d1 <=in_valid;
            if (in_valid) begin
                    for (i=0;i<K;i=i+1) 
                        prod_reg[i]<= $signed(in_data[i*DATA_W +:DATA_W])*$signed(weight[i*DATA_W +:DATA_W]);
                //valid pipeline
            end
        end
    end
    // Stage1: compute sum of prod0 and prod2
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            partial_sum <=0;
            partial_valid <=1'b0;
        end else if (valid_d1) begin
            partial_sum <= $signed(prod_reg[0]) + 
                            $signed(prod_reg[1]) + 
                            $signed(prod_reg[2]);
            partial_valid <= 1'b1;
        end else begin
            partial_valid <= 1'b0; 
        end
    end
endmodule