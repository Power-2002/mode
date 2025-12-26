`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/12/24 14:51:51
// Design Name: 
// Module Name: dma_preload_ctrl_sim
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
module dma_preload_ctrl_sim #(
    parameter ADDR_W = 16,
    parameter integer BUF_ADDR_W = 13,
    parameter DATA_W = 128,
    parameter MEM_FILE = "D:/NoC/mycode/mobilenet_acc3/data/weights/all_weights_128b.mem"
)(
    input  wire                clk,
    input  wire                rst_n,
    input  wire                preload_req,
    input  wire [ADDR_W-1:0]   preload_base,
    input  wire [16:0]         preload_count,  // ? 17bit，支持 65536
    output reg                 preload_done,

    output reg                 dma_wr_en,
    output reg [BUF_ADDR_W-1:0]          dma_wr_addr,     // ? buffer 内地址 0..65535
    output reg [DATA_W-1:0]    dma_wr_data
);

`ifndef SYNTHESIS
    reg [DATA_W-1:0] ddr_mem [0:(1 << ADDR_W)-1];
    initial begin
        $readmemh(MEM_FILE, ddr_mem);
    end
`endif

    reg [1:0] state;
    localparam S_IDLE    = 2'd0;
    localparam S_PRELOAD = 2'd1;
    localparam S_DONE    = 2'd2;

    reg [16:0]      count;     // ? 17bit
    reg [ADDR_W-1:0] ddr_addr; // DDR 地址
    reg [BUF_ADDR_W:0]      buf_addr;  // buffer 地址

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            preload_done <= 1'b0;
            dma_wr_en    <= 1'b0;
            dma_wr_addr  <= 16'd0;
            dma_wr_data  <= {DATA_W{1'b0}};
            count        <= 17'd0;
            ddr_addr     <= {ADDR_W{1'b0}};
            buf_addr     <= 16'd0;

        end else begin
            case (state)
                S_IDLE: begin
                    preload_done <= 1'b0;
                    dma_wr_en    <= 1'b0;
                    if (preload_req) begin
                        state    <= S_PRELOAD;
                        count    <= 17'd0;
                        buf_addr <= 16'd0;
                        ddr_addr <= preload_base;
                    end
                end

                S_PRELOAD: begin
                    dma_wr_en   <= 1'b1;
                    dma_wr_addr <= buf_addr;
                  `ifndef SYNTHESIS
    dma_wr_data <= ddr_mem[ddr_addr];
`else
    dma_wr_data <= {DATA_W{1'b0}};
`endif


                    if (count < preload_count - 1) begin
                        count    <= count + 1;
                        buf_addr <= buf_addr + 1;
                        ddr_addr <= ddr_addr + 1;
                    end else begin
                        dma_wr_en    <= 1'b0;
                        preload_done <= 1'b1;
                        state        <= S_DONE;
                    end
                end

                S_DONE: begin
                    dma_wr_en <= 1'b0;
                    if (!preload_req) begin
                        state <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
