`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/12/15 16:44:06
// Design Name: 
// Module Name: tb_layer0_mobilenet_top_28
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

//////////////////////////////////////////////////////////////////////////////////
// Testbench for MobileNetV1 Top - Layer 0 to Layer 28
// 包含:  Conv1 + 13*(DW+PW) + AP + FC
//////////////////////////////////////////////////////////////////////////////////
module tb_layer0_mobilenet_top_28;
  reg  CLK;
  reg  RESETn;
  reg  start;
  wire done;
  wire [2:0] fsm_state;
  wire [5:0] current_layer;

  // 时钟生成
  initial begin
    CLK = 1'b0;
    forever #5 CLK = ~CLK;   // 100 MHz
  end

  // DUT
  mobilenet_top_28layers#(
    . START_LAYER_ID(6'd25),  // 从 Layer 25 开始
    . MAX_LAYER_ID  (6'd28)   // 到 Layer 28 结束
  ) dut (
    .CLK          (CLK),
    .RESETn       (RESETn),
    .start        (start),
    .done         (done),
    .fsm_state    (fsm_state),
    .current_layer(current_layer)
  );

  // ============================================================
  // 层类型名称 (用于调试打印)
  // ============================================================
  function [8*10-1:0] get_layer_type_name;
    input [5:0] layer_id;
    begin
      case (layer_id)
        6'd0:  get_layer_type_name = "CONV1     ";
        6'd27: get_layer_type_name = "AVG_POOL  ";
        6'd28: get_layer_type_name = "FC        ";
        default:  begin
          if (layer_id[0] == 1'b1)  // 奇数层是DW
            get_layer_type_name = "DW        ";
          else                      // 偶数层是PW
            get_layer_type_name = "PW        ";
        end
      endcase
    end
  endfunction

  // ============================================================
  // 运行监控：每次 current_layer 变化就打印
  // ============================================================
  reg [5:0] last_layer;
  reg [31:0] layer_start_time;
  reg [31:0] layer_end_time;
  
  always @(posedge CLK) begin
    if (! RESETn) begin
      last_layer <= 6'h3F;
      layer_start_time <= 0;
    end else if (current_layer != last_layer) begin
      layer_end_time = $time;
      if (last_layer != 6'h3F) begin
        $display("[%0t] Layer %2d (%s) completed in %0d ns", 
                 $time, last_layer, get_layer_type_name(last_layer),
                 layer_end_time - layer_start_time);
      end
      $display("[%0t] Layer %2d (%s) started", 
               $time, current_layer, get_layer_type_name(current_layer));
      last_layer <= current_layer;
      layer_start_time <= $time;
    end
  end

  // ============================================================
  // FSM状态名称打印
  // ============================================================
  reg [2:0] last_fsm_state;
  always @(posedge CLK) begin
    if (!RESETn) begin
      last_fsm_state <= 3'b111;
    end else if (fsm_state != last_fsm_state) begin
      case (fsm_state)
        3'd0: $display("[%0t] FSM:  IDLE", $time);
        3'd1: $display("[%0t] FSM: RUN", $time);
        3'd2: $display("[%0t] FSM: NEXT", $time);
        3'd3: $display("[%0t] FSM:  DONE", $time);
        default: $display("[%0t] FSM: UNKNOWN(%0d)", $time, fsm_state);
      endcase
      last_fsm_state <= fsm_state;
    end
  end

  // ============================================================
  // 超时保护
  // ============================================================
  localparam TIMEOUT_NS = 100_000_000;  // 100ms超时
  
  initial begin
    #TIMEOUT_NS;
    $display("ERROR: Simulation timeout after %0d ns!", TIMEOUT_NS);
    $display("       Current layer: %0d, FSM state: %0d", current_layer, fsm_state);
    $stop;
  end

  // ============================================================
  // 主测试流程
  // ============================================================
  initial begin
    $display("========================================");
    $display("MobileNetV1 Full Network Simulation");
    $display("Layers: 0 (Conv1) -> 27 (AP) -> 28 (FC)");
    $display("========================================");
    
    // 初始化
    RESETn = 1'b0;
    start  = 1'b0;
    #100;
    
    // 释放复位
    RESETn = 1'b1;
    $display("[%0t] Reset released", $time);
    #50;

    // 启动脉冲
    $display("[%0t] Starting network execution.. .", $time);
    start = 1'b1;
    #10;
    start = 1'b0;

    // 等待完成
    wait(done == 1'b1);
    $display("[%0t] Network execution completed!", $time);
    
    // 打印最终结果
    #100;
    $display("========================================");
    $display("Simulation Summary:");
    $display("  Final FSM state: %0d (DONE)", fsm_state);
    $display("  Final layer: %0d", current_layer);
    $display("  Total layers executed: 29 (Layer 0-28)");
    $display("========================================");
    
    #1000;
    $stop;
  end

  // ============================================================
  // 可选：波形记录
  // ============================================================
  initial begin
    $dumpfile("mobilenet_top_28. vcd");
    $dumpvars(0, tb_layer0_mobilenet_top_28);
  end

endmodule