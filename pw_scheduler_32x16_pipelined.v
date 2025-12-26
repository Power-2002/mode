`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/12/22 19:20:45
// Design Name: 
// Module Name: pw_scheduler_32x16_pipelined
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
module pw_scheduler_32x16_pipelined #(
    parameter NUM_ROWS = 32,
    parameter NUM_COLS = 16,
    parameter A_BITS   = 8,
    parameter W_BITS   = 8,
    parameter ACC_BITS = 32,
    parameter ADDR_W   = 19,
    // FAST_SIM: keep real PE compute but reduce workload (power-of-2 subsample)
    parameter integer FAST_SIM_EN = 0,
    parameter integer FAST_COUT_SUBSAMPLE = 16, // 16 => compute 1/16 cout tiles (cout_idx[3:0]==0)
    parameter integer FAST_PX_SUBSAMPLE   = 16  // 16 => compute 1/16 pixels (px_idx[3:0]==0)
)(
    input  wire CLK,
    input  wire RESET,
    input  wire start,
    output reg  done,

    input  wire [10: 0] cin,
    input  wire [10:0] cout,
    input  wire [7:0]  img_w,
    input  wire [7:0]  img_h,
    input  wire [ADDR_W-1:0] w_base_in,

    // 权重接口
    output reg  weight_req,
    input  wire weight_grant,
    output reg  [ADDR_W-1:0] weight_base,
    output reg  [10:0] weight_count,
    input  wire weight_valid,
    input  wire [127:0] weight_data,
    input  wire weight_done,

    // 特征接口
    output reg  feat_rd_en,
    output reg  [15:0] feat_rd_addr,
    input  wire [127:0] feat_rd_data,
    input  wire feat_rd_valid,

    // PE阵列接口
    output reg  arr_W_EN,
    output reg  [NUM_COLS*W_BITS-1:0] in_weight_above,
    output reg  [NUM_ROWS*A_BITS-1:0] active_left,
    input  wire [NUM_COLS*ACC_BITS-1:0] out_sum_final,

    output reg  y_valid,
    output reg  [NUM_COLS*ACC_BITS-1:0] y_data,
    output reg  y_tile_sel
);

    // 计算参数
    wire [10:0] cin_tiles  = (cin + 31) >> 5;
    wire [10:0] cout_tiles = (cout + 15) >> 4;
    wire [15:0] total_px   = img_w * img_h;
    
    
   
    
    
    
    localparam integer PE_LAT = NUM_ROWS - 1;  // 31 周期

    // ============================================================
    // 双缓冲结构
    // ============================================================
    // 激活缓冲
    reg [255:0] act_buf [0:1];      // 双缓冲
    reg act_buf_valid [0:1];
    reg act_buf_sel;                // 当前使用的缓冲
    reg act_load_sel;               // 正在加载的缓冲
    
    // 权重缓冲 (每个cin_tile需要4个128-bit权重)
    reg [127:0] weight_buf [0:1][0:3];
    reg [2:0] weight_buf_cnt [0:1];  // 已加载的权重数
    reg weight_buf_valid [0:1];
    reg weight_buf_sel;
    reg weight_load_sel;

    // ============================================================
    // 流水线阶段信号
    // ============================================================
    // Stage 1: 数据加载 (可与Stage 2并行)
    reg load_active;
    reg [1:0] load_act_phase;   // 0=空闲, 1=加载低16ch, 2=加载高16ch
    reg [127:0] load_act_low;
    
    reg load_weight_active;
    reg [2:0] load_weight_cnt;
    
    // Stage 2: PE 计算
    reg pe_active;
    reg [5:0] pe_cycle_cnt;     // 0~31 延迟计数
    reg [10:0] pe_cin_idx;      // 正在计算的cin_tile
    
    // Stage 3: 结果捕获和累加
    reg capture_active;
    reg [4:0] capture_col;
    
    // ============================================================
    // 计数器和状态
    // ============================================================
    reg [15:0] px_idx;
    reg [10:0] cin_idx;         // 下一个要加载的cin_tile
    reg [10:0] cout_idx;
    reg [10:0] cin_computed;    // 已完成计算的cin_tile数
    
    // 累加器
    reg signed [ACC_BITS-1:0] psum [0:NUM_COLS-1];
    
    // 主状态机
    localparam S_IDLE      = 4'd0;
    localparam S_PREFETCH  = 4'd1;  // 预取第一组数据
    localparam S_PIPELINE  = 4'd2;  // 流水线运行
    localparam S_DRAIN     = 4'd3;  // 排空流水线
    localparam S_OUTPUT    = 4'd4;
    localparam S_NEXT_COUT = 4'd5;
    localparam S_NEXT_PX   = 4'd6;
    localparam S_DONE      = 4'd7;
    
    reg [3:0] state;
    
    integer i;

    // ============================================================
    // 地址计算
    // ============================================================
    wire [15:0] act_addr_base = px_idx * cin_tiles * 2 + cin_idx * 2;
    wire [ADDR_W-1:0] weight_addr_base = w_base_in + (cout_idx * cin_tiles + cin_idx) * 4;

    // ============================================================
    // FAST_SIM gating (power-of-2 subsampling). Still uses real PE for selected tiles/pixels.
    // ============================================================
        localparam [10:0] FAST_COUT_MASK = (FAST_COUT_SUBSAMPLE > 1) ? (FAST_COUT_SUBSAMPLE-1) : 11'd0;
    localparam [15:0] FAST_PX_MASK   = (FAST_PX_SUBSAMPLE   > 1) ? (FAST_PX_SUBSAMPLE  -1) : 16'd0;

    wire fast_do_compute =
        (FAST_SIM_EN == 0) ? 1'b1 :
        (((cout_idx & FAST_COUT_MASK) == 0) && ((px_idx & FAST_PX_MASK) == 0));
  
   
    // ============================================================
    // 主状态机
    // ============================================================
    always @(posedge CLK or negedge RESET) begin
        if (! RESET) begin
            state <= S_IDLE;
            done <= 0;
            y_valid <= 0;
            arr_W_EN <= 0;
            weight_req <= 0;
            feat_rd_en <= 0;
            
            load_active <= 0;
            load_act_phase <= 0;
            load_weight_active <= 0;
            load_weight_cnt <= 0;
            
            pe_active <= 0;
            pe_cycle_cnt <= 0;
            
            capture_active <= 0;
            capture_col <= 0;
            
            px_idx <= 0;
            cin_idx <= 0;
            cout_idx <= 0;
            cin_computed <= 0;
            
            act_buf_sel <= 0;
            act_load_sel <= 0;
            weight_buf_sel <= 0;
            weight_load_sel <= 0;
            
            for (i = 0; i < NUM_COLS; i = i + 1) psum[i] <= 0;
            for (i = 0; i < 2; i = i + 1) begin
                act_buf_valid[i] <= 0;
                weight_buf_valid[i] <= 0;
                weight_buf_cnt[i] <= 0;
            end
        end else begin
            done <= 0;
            y_valid <= 0;
            arr_W_EN <= 0;

            // ============================================================
            // Stage 1: 数据加载 (独立运行)
            // ============================================================
            
            // 激活加载状态机
            if (load_active) begin
                case (load_act_phase)
                    2'd0: begin  // 开始加载
                        feat_rd_en <= 1;
                        feat_rd_addr <= act_addr_base;
                        load_act_phase <= 2'd1;
                    end
                    2'd1: begin  // 等待低16ch
                        feat_rd_en <= 0;
                        if (feat_rd_valid) begin
                            load_act_low <= feat_rd_data;
                            feat_rd_en <= 1;
                            feat_rd_addr <= act_addr_base + 16'd1;
                            load_act_phase <= 2'd2;
                        end
                    end
                    2'd2: begin  // 等待高16ch
                        feat_rd_en <= 0;
                        if (feat_rd_valid) begin
                            act_buf[act_load_sel] <= {feat_rd_data, load_act_low};
                            act_buf_valid[act_load_sel] <= 1;
                            load_act_phase <= 2'd0;
                            load_active <= 0;
                        end
                    end
                endcase
            end
            
            // 权重加载状态机
            if (load_weight_active) begin
                if (weight_buf_cnt[weight_load_sel] == 0 && ! weight_req) begin
                    weight_req <= 1;
                    weight_base <= weight_addr_base;
                    weight_count <= 11'd4;
                end
                
                if (weight_grant) weight_req <= 0;
                
                if (weight_valid) begin
                    weight_buf[weight_load_sel][weight_buf_cnt[weight_load_sel]] <= weight_data;
                    weight_buf_cnt[weight_load_sel] <= weight_buf_cnt[weight_load_sel] + 1;
                end
                
                if (weight_done) begin
                    weight_buf_valid[weight_load_sel] <= 1;
                    load_weight_active <= 0;
                end
            end

            // ============================================================
            // Stage 2: PE 计算
            // ============================================================
            if (pe_active) begin
                if (pe_cycle_cnt == 0) begin
                    // 第一个周期:  加载权重和注入激活
                    active_left <= act_buf[act_buf_sel];
                    in_weight_above <= weight_buf[weight_buf_sel][0];  // 简化:  只用第一组
                    arr_W_EN <= 1;
                end
                
                pe_cycle_cnt <= pe_cycle_cnt + 1;
                
                if (pe_cycle_cnt >= PE_LAT) begin
                    // PE计算完成，开始捕获
                    pe_active <= 0;
                    capture_active <= 1;
                    capture_col <= 0;
                    
                    // 释放当前缓冲
                    act_buf_valid[act_buf_sel] <= 0;
                    weight_buf_valid[weight_buf_sel] <= 0;
                    weight_buf_cnt[weight_buf_sel] <= 0;
                    
                    // 切换缓冲
                    act_buf_sel <= ~act_buf_sel;
                    weight_buf_sel <= ~weight_buf_sel;
                end
            end

            // ============================================================
            // Stage 3: 结果捕获
            // ============================================================
            if (capture_active) begin
                psum[capture_col] <= psum[capture_col] + 
                    $signed(out_sum_final[capture_col*ACC_BITS +: ACC_BITS]);
                capture_col <= capture_col + 1;
                
                if (capture_col == NUM_COLS - 1) begin
                    capture_active <= 0;
                    cin_computed <= cin_computed + 1;
                end
            end

            // ============================================================
            // 主控制状态机
            // ============================================================
            case (state)
                S_IDLE:  begin
                    if (start) begin
                        px_idx <= 0;
                        cin_idx <= 0;
                        cout_idx <= 0;
                        cin_computed <= 0;
                        for (i = 0; i < NUM_COLS; i = i + 1) psum[i] <= 0;
                        
                        // 开始预取
                        load_active <= 1;
                        load_act_phase <= 0;
                        act_load_sel <= 0;
                        
                        load_weight_active <= 1;
                        weight_load_sel <= 0;
                        
                        state <= S_PREFETCH;
                    end
                end

                S_PREFETCH: begin
                // FAST_SIM: if this (cout_idx,px_idx) is not selected, skip compute and output zeros quickly
                    if (!fast_do_compute) begin
                        for (i = 0; i < NUM_COLS; i = i + 1) psum[i] <= 0;
                        cin_idx <= 0;
                        cin_computed <= cin_tiles; // mark as done
                        // stop any outstanding loads
                        load_active <= 0;
                        load_weight_active <= 0;
                        pe_active <= 0;
                        capture_active <= 0;
                        state <= S_OUTPUT;
                    end
                    
                    // 等待第一组数据加载完成
                    if (act_buf_valid[0] && weight_buf_valid[0]) begin
                        // 启动PE计算
                        pe_active <= 1;
                        pe_cycle_cnt <= 0;
                        act_buf_sel <= 0;
                        weight_buf_sel <= 0;
                        
                        // 同时开始加载下一组 (如果有)
                        cin_idx <= cin_idx + 1;
                        if (cin_idx + 1 < cin_tiles) begin
                            load_active <= 1;
                            load_act_phase <= 0;
                            act_load_sel <= 1;
                            
                            load_weight_active <= 1;
                            weight_load_sel <= 1;
                        end
                        
                        state <= S_PIPELINE;
                    end
                end

                S_PIPELINE: begin
                    // 流水线运行:  加载和计算并行
                    
                    // 当一个cin_tile计算完成时
                    if (! capture_active && cin_computed > 0) begin
                        // 检查是否有下一组准备好
                        if (act_buf_valid[act_buf_sel] && weight_buf_valid[weight_buf_sel]) begin
                            // 启动下一个cin_tile的计算
                            pe_active <= 1;
                            pe_cycle_cnt <= 0;
                            
                            // 开始加载更下一组
                            if (cin_idx < cin_tiles) begin
                                load_active <= 1;
                                load_act_phase <= 0;
                                act_load_sel <= ~act_buf_sel;
                                
                                load_weight_active <= 1;
                                weight_load_sel <= ~weight_buf_sel;
                                
                                cin_idx <= cin_idx + 1;
                            end
                        end
                    end
                    
                    // 所有cin_tile完成
                    if (cin_computed >= cin_tiles && !pe_active && !capture_active) begin
                        state <= S_OUTPUT;
                    end
                end

                S_OUTPUT: begin
                    y_valid <= 1;
                    for (i = 0; i < NUM_COLS; i = i + 1) begin
                        y_data[i*ACC_BITS +:  ACC_BITS] <= psum[i];
                    end
                    y_tile_sel <= cout_idx[0];
                    
                    // 清零
                    for (i = 0; i < NUM_COLS; i = i + 1) psum[i] <= 0;
                    cin_idx <= 0;
                    cin_computed <= 0;
                    
                    state <= S_NEXT_COUT;
                end

                S_NEXT_COUT: begin
                    if (cout_idx + 1 < cout_tiles) begin
                        // advance to next cout tile
                        cout_idx <= cout_idx + 1;

                        // clear accumulators / indices for next tile
                        for (i = 0; i < NUM_COLS; i = i + 1) psum[i] <= 0;
                        cin_idx <= 0;
                        cin_computed <= 0;

                        // clear buffer valids/counters
                        act_buf_valid[0] <= 0;
                        act_buf_valid[1] <= 0;
                        weight_buf_valid[0] <= 0;
                        weight_buf_valid[1] <= 0;
                        weight_buf_cnt[0] <= 0;
                        weight_buf_cnt[1] <= 0;

                        // FAST_SIM: if next tile should be skipped (based on next cout_idx and current px_idx), output zeros immediately
                        if ((FAST_SIM_EN != 0) && ((((cout_idx + 11'd1) & FAST_COUT_MASK) != 0) || ((px_idx & FAST_PX_MASK) != 0))) begin
                            load_active <= 0;
                            load_weight_active <= 0;
                            pe_active <= 0;
                            capture_active <= 0;
                            cin_computed <= cin_tiles;
                            state <= S_OUTPUT;
                        end else begin
                            // normal prefetch for next tile
                            load_active <= 1;
                            load_act_phase <= 0;
                            act_load_sel <= 0;

                            load_weight_active <= 1;
                            weight_load_sel <= 0;

                            state <= S_PREFETCH;
                        end
                    end else begin
                        state <= S_DONE;
                    end
                end
                S_NEXT_PX: begin
                    if (px_idx + 1 < total_px) begin
                        px_idx <= px_idx + 1;
                        cout_idx <= 0;

                        // clear accumulators / indices for next pixel
                        for (i = 0; i < NUM_COLS; i = i + 1) psum[i] <= 0;
                        cin_idx <= 0;
                        cin_computed <= 0;

                        // clear buffer valids/counters
                        act_buf_valid[0] <= 0;
                        act_buf_valid[1] <= 0;
                        weight_buf_valid[0] <= 0;
                        weight_buf_valid[1] <= 0;
                        weight_buf_cnt[0] <= 0;
                        weight_buf_cnt[1] <= 0;

                        // FAST_SIM: if this pixel is not selected (px_idx+1), skip compute for cout_idx=0 too
                        if ((FAST_SIM_EN != 0) && (((( (px_idx + 16'd1) & FAST_PX_MASK) != 0))) ) begin
                            load_active <= 0;
                            load_weight_active <= 0;
                            pe_active <= 0;
                            capture_active <= 0;
                            cin_computed <= cin_tiles;
                            state <= S_OUTPUT;
                        end else begin
                            // normal prefetch for next pixel (cout_idx=0)
                            load_active <= 1;
                            load_act_phase <= 0;
                            act_load_sel <= 0;

                            load_weight_active <= 1;
                            weight_load_sel <= 0;

                            state <= S_PREFETCH;
                        end
                    end else begin
                        state <= S_DONE;
                    end
                end
                S_DONE:  begin
                    done <= 1;
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
