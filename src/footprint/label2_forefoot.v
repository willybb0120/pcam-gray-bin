`timescale 1ns/1ps

// label2_forefoot: 前脚掌边界检测模块
// 功能：找到前脚掌（上半部分）的左右边界点座标
// 逻辑：以 row_boundary 为分界线，只统计上方像素，建立垂直直方图
module label2_forefoot #(
    parameter WIDTH = 640,   // 图像宽度
    parameter HEIGHT = 480   // 图像高度
)(
    input  wire        clk,              // 时钟信号
    input  wire        rst,              // 重置信号 (高电平有效)
    input  wire        in_valid,         // 输入有效信号
    input  wire        pixel,            // 像素资料 (1bit)
    input  wire [31:0] row_boundary,     // 分界行号（来自 label3 的 min_line_mid）

    // 输出：前脚掌左右边界点座标
    output reg  [31:0] left_x,           // 左边界 X 座标
    output reg  [31:0] left_y,           // 左边界 Y 座标（该列的中心）
    output reg  [31:0] right_x,          // 右边界 X 座标
    output reg  [31:0] right_y,          // 右边界 Y 座标（该列的中心）
    output reg         done              // 处理完成标志
);

    // ========================================
    // 衍生常數（從 HEIGHT 計算）
    // ========================================
    localparam Y_BITS     = $clog2(HEIGHT);       // 行座標位元寬（720 → 10）
    localparam VHIST_BITS = $clog2(HEIGHT + 1);   // 垂直直方圖計數位元寬（max = HEIGHT）
    localparam Y_SENTINEL = {Y_BITS{1'b1}};       // "未設置" 哨兵（全 1）

    // 状态定义（One-Hot 编码）
    localparam S_RESET         = 4'b0001;  // 复位状态（逐步清零数组）
    localparam S_IDLE          = 4'b0010;  // 等待输入并建立垂直直方图
    localparam S_FIND_BOUNDARY = 4'b0100;  // 寻找左右边界
    localparam S_DONE          = 4'b1000;  // 完成
    reg [3:0] state;

    // 当前处理的像素位置
    reg [31:0] row, col;

    // 垂直直方图（统计每一列的像素数量，只统计 row < row_boundary 的像素）
    reg [VHIST_BITS-1:0] vertical_hist [0:WIDTH-1];  // 每一列的像素计数（最大值 HEIGHT，需 VHIST_BITS）
    reg [Y_BITS-1:0]     first_y [0:WIDTH-1];        // 每一列第一个白色像素的Y座标（需 Y_BITS）
    reg [Y_BITS-1:0]     last_y  [0:WIDTH-1];        // 每一列最后一个白色像素的Y座标（需 Y_BITS）

    // 边界搜索索引
    reg [31:0] boundary_idx;

    // 复位计数器（用于逐步清零数组）
    reg [31:0] reset_idx;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            row <= 0;
            col <= 0;
            left_x <= 0;
            left_y <= 0;
            right_x <= 0;
            right_y <= 0;
            done <= 0;
            state <= S_RESET;
            boundary_idx <= 0;
            reset_idx <= 0;
        end else begin
            case(state)
                // ===============================
                // S_RESET: 复位状态（逐步清零数组）
                // ===============================
                S_RESET: begin
                    vertical_hist[reset_idx] <= 0;
                    first_y[reset_idx] <= Y_SENTINEL;  // 全 1 表示 "未設置"
                    last_y[reset_idx] <= 0;

                    if (reset_idx == WIDTH-1) begin
                        state <= S_IDLE;
                        reset_idx <= 0;
                    end else begin
                        reset_idx <= reset_idx + 1;
                    end
                end
                // ===============================
                // S_IDLE: 流式建立垂直直方图
                // 只统计 row < row_boundary 的像素
                // ===============================
                S_IDLE: begin
                    if (in_valid) begin
                        // 如果当前像素为 1（白色）且在分界线以上，累加到对应列的计数器
                        if (pixel && row < row_boundary) begin
                            vertical_hist[col] <= vertical_hist[col] + 1;

                            // 记录该列第一个白色像素的Y座标
                            if (first_y[col] == Y_SENTINEL) begin  // 全 1 表示 "未設置"
                                first_y[col] <= row;
                            end

                            // 持续更新该列最后一个白色像素的Y座标
                            last_y[col] <= row;
                        end

                        // 更新列位置
                        if (col == WIDTH - 1) begin
                            // 当前行结束
                            col <= 0;
                            if (row == HEIGHT - 1) begin
                                // 所有像素接收完毕，进入边界搜索阶段
                                row <= 0;
                                boundary_idx <= 0;
                                state <= S_FIND_BOUNDARY;
                            end else begin
                                // 移到下一行
                                row <= row + 1;
                            end
                        end else begin
                            // 移到下一列
                            col <= col + 1;
                        end
                    end
                end

                // ===============================
                // S_FIND_BOUNDARY: 寻找左右边界
                // 从左到右扫描，找第一个和最后一个有像素的列
                // ===============================
                S_FIND_BOUNDARY: begin
                    if (boundary_idx == 0) begin
                        // 初始化，找左边界
                        left_x <= 0;
                        left_y <= 0;
                        right_x <= 0;
                        right_y <= 0;
                        boundary_idx <= 1;  // 开始扫描
                    end else if (boundary_idx <= WIDTH) begin
                        // 从左到右扫描
                        if (vertical_hist[boundary_idx - 1] > 0) begin
                            // 找到有像素的列
                            if (left_x == 0) begin
                                // 这是第一个有像素的列，记录为左边界
                                left_x <= boundary_idx - 1;
                                left_y <= (first_y[boundary_idx - 1] + last_y[boundary_idx - 1]) >> 1;
                            end
                            // 持续更新右边界（最后一个有像素的列）
                            right_x <= boundary_idx - 1;
                            right_y <= (first_y[boundary_idx - 1] + last_y[boundary_idx - 1]) >> 1;
                        end

                        if (boundary_idx == WIDTH) begin
                            // 扫描完成
                            done <= 1;
                            state <= S_DONE;
                        end else begin
                            boundary_idx <= boundary_idx + 1;
                        end
                    end
                end

                // ===============================
                // S_DONE: 完成状态
                // 保持 done 信号直到重置
                // ===============================
                S_DONE: begin
                    done <= 1;
                end
            endcase
        end
    end

endmodule
