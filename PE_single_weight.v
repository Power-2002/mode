`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/12/15 16:32:16
// Design Name: 
// Module Name: PE_single_weight
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

module PE_single_weight(
    // System interface
    input wire CLK,                         // Clock signal
    input wire RESET,                       // Reset signal (active low)
    input wire EN,                          // Enable signal
    input wire W_EN,                        // Weight loading enable
    
    // PE row interface (horizontal activation flow)
    input wire signed [7:0] active_left,    // Left input activation
    output reg signed [7:0] active_right,   // Right output activation
    
    // PE column interface (vertical partial sum accumulation)
    input wire signed [31:0] in_sum,        // Input partial sum from above
    output reg signed [31:0] out_sum,       // Output partial sum to below
    
    // Weight flow interface (vertical)
    input wire signed [7:0] in_weight_above,    // Weight input from above
    output reg signed [7:0] out_weight_below    // Weight output to below
);

    // Single weight register
    reg signed [7:0] weight;
    // ===== Multiply and extend (8x8=16, then extend to 32) =====
    wire signed [15:0] mul16 = $signed(active_left) * $signed(weight);
    wire signed [31:0] mul32 = {{16{mul16[15]}}, mul16};

    always @(posedge CLK or negedge RESET) begin
        if (~RESET) begin
            // Reset all outputs and registers
            out_sum <= 32'sd0;
            active_right <= 8'sd0;
            out_weight_below <= 8'sd0;
            weight <= 8'sd0;
        end
        else if (EN) begin
            // Always propagate activation horizontally (systolic flow)
            active_right <= active_left;
            
            if (W_EN) begin
                // ========== Weight Loading Phase ==========
                // Load weight and propagate vertically
                weight <= in_weight_above;
                out_weight_below <= in_weight_above;
                
                // ? KEY FIX: Do NOT compute during weight loading
                // Just pass through the partial sum without modification
                out_sum <= in_sum;
            end
            else begin
                // ========== Computation Phase ==========
                // ? Only compute when NOT loading weights
                // MAC operation: output = weight ¡Á activation + partial_sum
                out_sum <= $signed(in_sum) + mul32;
                
                // Stop weight propagation during computation
                out_weight_below <= 8'sd0;
            end
        end
    end
endmodule

