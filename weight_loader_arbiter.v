`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/12/15 16:25:01
// Design Name: 
// Module Name: weight_loader_arbiter
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
// 权重加载仲裁器：协调 DW Cache 和 CONV/PW Scheduler 对 weight_loader_universal 的访问
module weight_loader_arbiter #(
    parameter ADDR_W = 16,
    parameter integer BUF_ADDR_W = 13
)(
    input  wire        clk,
    input  wire        rst_n,

    // ===== DW Cache  =====
    input  wire        dw_req,
    input  wire [ADDR_W-1:0] dw_base,
    input  wire [16:0] dw_count,
    output reg         dw_grant,
    output reg         dw_valid,
    output reg  [127:0] dw_data,
    output reg         dw_done,

    // ===== CONV/PW Scheduler =====
    input  wire        pw_req,
    input  wire [ADDR_W-1:0] pw_base,
    input  wire [16:0] pw_count,
    output reg         pw_grant,
    output reg         pw_valid,
    output reg  [127:0] pw_data,
    output reg         pw_done,

    // =====  weight_loader_universal =====
    output reg         ldr_start,
    output reg  [ADDR_W-1:0] ldr_base,
    output reg  [16:0] ldr_count,
    input  wire        ldr_valid,
    input  wire [127:0] ldr_data,
    input  wire        ldr_done,

    // ===== NEW: preload handshake 透出到 top 连接 DMA =====
    output wire        preload_req,
    output wire [ADDR_W-1:0] preload_base,
    output wire [16:0] preload_count,
    input  wire        preload_done,

    // ===== 连接到 weight buffer =====
    output wire        bmg_en,
    output wire [BUF_ADDR_W-1:0] bmg_addr,
    input  wire [127:0] bmg_data
);

    // 实例化 weight_loader_universal
    weight_loader_universal #(
        .ADDR_W (ADDR_W),
        .DATA_W (128),
        .RD_LAT (2)   // ? 如果你的 weight buffer 读延迟是1，可改成1
    ) u_loader (
        .clk          (clk),
        .rst_n        (rst_n),

        .start        (ldr_start),
        .base_addr    (ldr_base),
        .load_count   (ldr_count),
        .done         (ldr_done),

        // NEW preload ports
        .preload_req   (preload_req),
        .preload_base  (preload_base),
        .preload_count (preload_count),
        .preload_done  (preload_done),

        // buffer read ports
        .bmg_en       (bmg_en),
        .bmg_addr     (bmg_addr),
        .bmg_data     (bmg_data),

        // stream out
        .out_valid    (ldr_valid),
        .out_data     (ldr_data)
    );

    // 仲裁状态机
    reg [1:0] state;
    localparam S_IDLE    = 2'd0;
    localparam S_DW_LOAD = 2'd1;
    localparam S_PW_LOAD = 2'd2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            dw_grant  <= 1'b0;
            pw_grant  <= 1'b0;
            ldr_start <= 1'b0;
            dw_valid  <= 1'b0;
            pw_valid  <= 1'b0;
            dw_done   <= 1'b0;
            pw_done   <= 1'b0;
            dw_data   <= 128'd0;
            pw_data   <= 128'd0;
        end else begin
            // 默认信号
            ldr_start <= 1'b0;
            dw_valid  <= 1'b0;
            pw_valid  <= 1'b0;
            dw_done   <= 1'b0;
            pw_done   <= 1'b0;

            case (state)
                S_IDLE: begin
                    dw_grant <= 1'b0;
                    pw_grant <= 1'b0;

                    // DW 优先
                    if (dw_req) begin
                        dw_grant  <= 1'b1;
                        ldr_base  <= dw_base;
                        ldr_count <= dw_count;
                        ldr_start <= 1'b1;
                        state     <= S_DW_LOAD;
                    end else if (pw_req) begin
                        pw_grant  <= 1'b1;
                        ldr_base  <= pw_base;
                        ldr_count <= pw_count;
                        ldr_start <= 1'b1;
                        state     <= S_PW_LOAD;
                    end
                end

                S_DW_LOAD: begin
                    if (ldr_valid) begin
                        dw_valid <= 1'b1;
                        dw_data  <= ldr_data;
                    end
                    if (ldr_done) begin
                        dw_done  <= 1'b1;
                        dw_grant <= 1'b0;
                        state    <= S_IDLE;
                    end
                end

                S_PW_LOAD: begin
                    if (ldr_valid) begin
                        pw_valid <= 1'b1;
                        pw_data  <= ldr_data;
                    end
                    if (ldr_done) begin
                        pw_done  <= 1'b1;
                        pw_grant <= 1'b0;
                        state    <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
