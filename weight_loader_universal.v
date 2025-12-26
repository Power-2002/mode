`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/12/15 16:25:41
// Design Name: 
// Module Name: weight_loader_universal
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

// Module Name: weight_loader_universal
// Description: 通用权重读取引擎
//              负责产生 BRAM 读取时序，支持动态加载长度
//////////////////////////////////////////////////////////////////////////////////
module weight_loader_universal #(
    parameter ADDR_W = 19,
    parameter DATA_W = 128,
    parameter integer RD_LAT = 2   // ? 适配 URAM/BRAM; URAM建议2
)(
    input  wire                 clk,
    input  wire                 rst_n,

    // 控制接口
    input  wire                 start,
    input  wire [ADDR_W-1:0]    base_addr,      // ? DDR base（用于 preload）
    input  wire [16:0]          load_count,     // 需要加载多少行数据
    output reg                  done,

    // ===== NEW: preload handshake to DMA/PS =====
    output reg                  preload_req,
    output reg  [ADDR_W-1:0]    preload_base,
    output reg  [16:0]          preload_count,
    input  wire                 preload_done,

    // weight buffer(BMG) 接口：从 buffer 读取（DMA写入）
    output reg                  bmg_en,
    output reg  [15:0]    bmg_addr,
    input  wire [DATA_W-1:0]    bmg_data,

    // 输出流接口
    output reg                  out_valid,
    output reg  [DATA_W-1:0]    out_data
);

    // ----------------------------
    // FSM States
    // ----------------------------
    reg [1:0] state;
    localparam S_IDLE    = 2'd0;
    localparam S_PRELOAD = 2'd1;  // ? 等DMA把 DDR->buffer 搬完
    localparam S_READ    = 2'd2;
    localparam S_WAIT    = 2'd3;

    reg [16:0] cnt;

    // ----------------------------
    // Read latency alignment
    // ----------------------------
    reg [RD_LAT-1:0] bmg_en_pipe;

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= S_IDLE;
            bmg_en         <= 1'b0;
            bmg_addr       <= {ADDR_W{1'b0}};
            out_valid      <= 1'b0;
            out_data       <= {DATA_W{1'b0}};
            done           <= 1'b0;
            cnt            <= 11'd0;

            preload_req    <= 1'b0;
            preload_base   <= {ADDR_W{1'b0}};
            preload_count  <= 11'd0;

            bmg_en_pipe    <= {RD_LAT{1'b0}};
        end else begin
            // defaults
            out_valid <= 1'b0;
            done      <= 1'b0;

            // shift pipeline for bmg_en (for read latency)
            bmg_en_pipe[0] <= bmg_en;
            for (i = 1; i < RD_LAT; i = i + 1) begin
                bmg_en_pipe[i] <= bmg_en_pipe[i-1];
            end

            // When data becomes valid
            if (bmg_en_pipe[RD_LAT-1]) begin
                out_valid <= 1'b1;
                out_data  <= bmg_data;
            end

            case (state)
                // --------------------------------
                // IDLE: wait for start
                // --------------------------------
                S_IDLE: begin
                    bmg_en <= 1'b0;

                    if (start) begin
                        // 发起 preload 请求
                        preload_req   <= 1'b1;
                        preload_base  <= base_addr;
                        preload_count <= load_count;

                        cnt           <= 11'd0;
                        state         <= S_PRELOAD;
                    end
                end

                // --------------------------------
                // PRELOAD: wait preload_done
                // --------------------------------
                S_PRELOAD: begin
                    bmg_en <= 1'b0;

                    if (preload_done) begin
                        preload_req <= 1'b0;

                        // preload 完成，开始从 weight buffer 读
                        cnt      <= 11'd0;
                        bmg_en   <= 1'b1;
                        bmg_addr <= {ADDR_W{1'b0}};  // ? 从 buffer[0] 开始读
                        state    <= S_READ;
                    end
                end

                // --------------------------------
                // READ: issue buffer reads
                // --------------------------------
                S_READ: begin
                    if (cnt < load_count - 1) begin
                        bmg_en   <= 1'b1;
                        bmg_addr <= bmg_addr + 1'b1;
                        cnt      <= cnt + 1'b1;
                    end else begin
                        bmg_en <= 1'b0;
                        state  <= S_WAIT;
                    end
                end

                // --------------------------------
                // WAIT: drain last data
                // --------------------------------
                S_WAIT: begin
                    // 等待 pipeline 全部排空
                    if (bmg_en_pipe[RD_LAT-1] == 1'b0) begin
                        state <= S_IDLE;
                        done  <= 1'b1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
