`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/12/15 16:37:20
// Design Name: 
// Module Name: dw_weight_cache
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
module dw_weight_cache #(
    parameter UNIT_NUM = 16,
    parameter DATA_W   = 8,
    parameter K        = 3
)(
    input  wire                      clk,
    input  wire                      rst_n,

    // 控制接口
    input  wire                      load_start,
    input  wire [18:0]               base_addr,
    output reg                       load_done,

    // ===== 请求仲裁接口 =====
    output reg                       ldr_req,
    input  wire                      ldr_grant,
    output wire [18:0]               ldr_base_addr,
    output wire [10:0]               ldr_count,
    input  wire                      ldr_valid,
    input  wire [127:0]              ldr_data,
    input  wire                      ldr_done_sig,

    // 输出到 DWC PU (寄存器化，避免组合重排爆 LUT)
    output reg [UNIT_NUM*K*K*DATA_W-1:0] weights_parallel_out
);

    // ============================================================
    // 固定 DW 3x3，一共 9 个权重向量（每个向量 16 通道 * 8bit）
    // ============================================================
    assign ldr_base_addr = base_addr;
    assign ldr_count     = 11'd9;

    // 存储 9 组 128bit 权重
    reg [127:0] weight_buffer [0:8];

    reg [3:0] recv_cnt;
    reg       loading;

    integer ch, k_idx;

    // ============================================================
    // 加载控制：请求 -> grant -> 接收 -> done
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            recv_cnt  <= 4'd0;
            loading   <= 1'b0;
            load_done <= 1'b0;
            ldr_req   <= 1'b0;
        end else begin
            load_done <= 1'b0;

            // 发起请求
            if (load_start && !loading && !ldr_req) begin
                ldr_req  <= 1'b1;
                recv_cnt <= 4'd0;
            end

            // 获得 grant 开始加载
            if (ldr_grant && ldr_req) begin
                ldr_req <= 1'b0;
                loading <= 1'b1;
            end

            // 接收权重数据
            if (ldr_valid && loading) begin
                weight_buffer[recv_cnt] <= ldr_data;
                recv_cnt <= recv_cnt + 1'b1;
            end

            // 完成信号
            if (ldr_done_sig && loading) begin
                loading   <= 1'b0;
                load_done <= 1'b1;
            end
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            weights_parallel_out <= {(UNIT_NUM*K*K*DATA_W){1'b0}};
        end else if (load_done) begin
            for (ch = 0; ch < UNIT_NUM; ch = ch + 1) begin
                for (k_idx = 0; k_idx < 9; k_idx = k_idx + 1) begin
                    weights_parallel_out[ch*72 + k_idx*8 +: 8]
                        <= weight_buffer[k_idx][ch*8 +: 8];
                end
            end
        end
    end

endmodule
