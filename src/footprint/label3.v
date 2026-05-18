`timescale 1ns/1ps
module label3 #(
    parameter WIDTH = 640,   // 圖像寬度（固定為 640，適應任意 x_cut）
    parameter HEIGHT = 480   // 圖像高度
)(
    input  wire        clk,              // 時鐘信號
    input  wire        rst,              // 重置信號 (高電平有效)
    input  wire        in_valid,         // 輸入有效信號
    input  wire        pixel,            // 像素資料 (1bit)
    output reg  [31:0] max_ones_half,    // 上半部分最大峰值的像素數量
    output reg  [31:0] max_line_half,    // 上半部分最大峰值的行號
    output reg  [31:0] min_ones_mid,     // 中間部分最小值的像素數量
    output reg  [31:0] min_line_mid,     // 中間部分最小值的行號
    output reg  [31:0] max_ones_last3,   // 後三分之一最大峰值的像素數量
    output reg  [31:0] max_line_last3,   // 後三分之一最大峰值的行號
    output reg  [31:0] toe_y,            // 腳趾頭邊界的Y座標（行號）
    output reg  [31:0] toe_x,            // 腳趾頭邊界的X中心座標
    output reg  [31:0] heel_y,           // 腳跟邊界的Y座標（行號）
    output reg  [31:0] heel_x,           // 腳跟邊界的X中心座標
    output reg  [31:0] last3_left_x,     // 後三分之一峰值行的左邊界X座標
    output reg  [31:0] last3_right_x,    // 後三分之一峰值行的右邊界X座標
    output reg         done              // 處理完成標誌
);

    // ========================================
    // 衍生常數（從 WIDTH/HEIGHT 計算）
    // ========================================
    localparam X_BITS      = $clog2(WIDTH);       // 列座標位元寬（1280 → 11）
    localparam HIST_BITS   = $clog2(WIDTH + 1);   // 直方圖計數位元寬（max = WIDTH）
    localparam SMOOTH_BITS = $clog2(3*WIDTH + 1); // 3 點平滑最大值 3*WIDTH（1280 → 12）
    localparam X_SENTINEL  = {X_BITS{1'b1}};      // "未設置" 哨兵（全 1）

    // 狀態定義（One-Hot 編碼）
    localparam S_RESET    = 6'b000001;  // 復位狀態（逐步清零陣列）
    localparam S_IDLE     = 6'b000010;  // 等待輸入並建立直方圖
    localparam S_SMOOTH   = 6'b000100;  // 平滑處理
    localparam S_MAX      = 6'b001000;  // 尋找峰值
    localparam S_BOUNDARY = 6'b010000;  // 尋找邊界
    localparam S_DONE     = 6'b100000;  // 完成
    reg [5:0] state;

    // 當前處理的像素位置
    reg [31:0] row, col;      // 當前行列座標

    // 水平直方圖（統計每一行的像素數量）
    reg [HIST_BITS-1:0]   histogram   [0:HEIGHT-1];  // 原始直方圖（最大值 WIDTH）
    reg [SMOOTH_BITS-1:0] smooth_hist [0:HEIGHT-1];  // 平滑後的直方圖（最大值 3*WIDTH）

    // 每行的邊界X座標（用於計算中心點）
    reg [X_BITS-1:0]      first_x [0:HEIGHT-1];      // 每行第一個白色像素的X座標
    reg [X_BITS-1:0]      last_x  [0:HEIGHT-1];      // 每行最後一個白色像素的X座標

    // 處理索引
    reg [31:0] smooth_idx;    // 平滑處理的當前索引
    reg [31:0] max_idx;       // 峰值搜尋的當前索引
    reg [31:0] boundary_idx;  // 邊界搜尋的當前索引
    reg        boundary_dir;  // 邊界搜尋方向：0=向上(toe), 1=向下(heel)

    // 組合邏輯：3點平滑計算（使用 wire 而非 reg）
    wire [SMOOTH_BITS-1:0] smooth_sum;  // 能容納 3 個 HIST_BITS 數相加（最大 3*WIDTH）
    assign smooth_sum = histogram[smooth_idx] +
                        ((smooth_idx > 0) ? histogram[smooth_idx - 1] : {HIST_BITS{1'b0}}) +
                        ((smooth_idx < HEIGHT-1) ? histogram[smooth_idx + 1] : {HIST_BITS{1'b0}});

    // 復位計數器（用於逐步清零陣列）
    reg [31:0] reset_idx;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            row            <= 0;
            col            <= 0;
            max_ones_half  <= 0;
            max_line_half  <= 0;
            min_ones_mid   <= 32'hFFFFFFFF;  // 初始化為最大值
            min_line_mid   <= 0;
            max_ones_last3 <= 0;
            max_line_last3 <= 0;
            toe_y          <= 0;
            toe_x          <= 0;
            heel_y         <= 0;
            heel_x         <= 0;
            last3_left_x   <= 0;
            last3_right_x  <= 0;
            done           <= 0;
            state          <= S_RESET;
            smooth_idx     <= 0;
            max_idx        <= 0;
            boundary_idx   <= 0;
            boundary_dir   <= 0;
            reset_idx      <= 0;
        end else begin
            case(state)
                // ===============================
                // S_RESET: 復位狀態（逐步清零陣列）
                // ===============================
                S_RESET: begin
                    histogram[reset_idx]   <= 0;
                    smooth_hist[reset_idx] <= 0;
                    first_x[reset_idx]     <= X_SENTINEL;  // 全 1 表示 "未設置"
                    last_x[reset_idx]      <= 0;

                    if (reset_idx == HEIGHT-1) begin
                        state <= S_IDLE;
                        reset_idx <= 0;
                    end else begin
                        reset_idx <= reset_idx + 1;
                    end
                end
                // ===============================
                // S_IDLE: 流式建立水平直方圖
                // 統計每一行（row）的白色像素數量
                // ===============================
                S_IDLE: begin
                    if (in_valid) begin
                        // 如果當前像素為 1（白色），累加到對應行的計數器並記錄邊界
                        if (pixel) begin
                            histogram[row] <= histogram[row] + 1;

                            // 記錄該行第一個白色像素的X座標
                            if (first_x[row] == X_SENTINEL) begin  // 全 1 表示 "未設置"
                                first_x[row] <= col;
                            end

                            // 持續更新該行最後一個白色像素的X座標
                            last_x[row] <= col;
                        end

                        // 更新列位置
                        if (col == WIDTH-1) begin
                            // 當前行結束
                            col <= 0;
                            if (row == HEIGHT-1) begin
                                // 所有像素接收完畢，進入平滑處理階段
                                row        <= 0;
                                smooth_idx <= 0;
                                state      <= S_SMOOTH;
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
                // S_SMOOTH: 平滑處理（使用 3 點平滑窗口）
                // 目的：減少雜訊，使峰值更明顯
                // 每個時鐘週期處理一行
                // ===============================
                S_SMOOTH: begin
                    // 3點平滑：當前點 + 前一點 + 後一點
                    // 邊界處理：
                    //   - 第 0 行：只加 histogram[0] + histogram[1]
                    //   - 第 i 行：histogram[i-1] + histogram[i] + histogram[i+1]
                    //   - 最後一行：histogram[HEIGHT-2] + histogram[HEIGHT-1]
                    // 使用 wire smooth_sum（組合邏輯）計算平滑值
                    smooth_hist[smooth_idx] <= smooth_sum;

                    if (smooth_idx == HEIGHT-1) begin
                        // 平滑處理完成，準備尋找峰值
                        max_idx        <= 0;
                        max_ones_half  <= 0;
                        max_line_half  <= 0;
                        min_ones_mid   <= 32'hFFFFFFFF;  // 初始化為最大值，用於找最小值
                        min_line_mid   <= 0;
                        max_ones_last3 <= 0;
                        max_line_last3 <= 0;
                        state          <= S_MAX;
                    end else begin
                        smooth_idx <= smooth_idx + 1;
                    end
                end

                // ===============================
                // S_MAX: 尋找峰值和最小值（上半部 / 中間部分 / 後三分之一）
                // 每個時鐘週期檢查一行
                // ===============================
                S_MAX: begin
                    // 1. 尋找上半部分 [0, HEIGHT/2) 的最大峰值
                    //    用於檢測腳的上方區域
                    if (max_idx < HEIGHT/2) begin
                        if (smooth_hist[max_idx] > max_ones_half) begin
                            max_ones_half <= smooth_hist[max_idx];
                            max_line_half <= max_idx;
                        end
                    end

                    // 2. 尋找中間部分 [HEIGHT/2, 2*HEIGHT/3) 的最小值
                    //    用於檢測足弓區域（最窄處）
                    if (max_idx >= HEIGHT/2 && max_idx < (2*HEIGHT/3)) begin
                        if (smooth_hist[max_idx] < min_ones_mid) begin
                            min_ones_mid <= smooth_hist[max_idx];
                            min_line_mid <= max_idx;
                        end
                    end

                    // 3. 尋找後三分之一 [2*HEIGHT/3, HEIGHT) 的最大峰值
                    //    用於檢測腳的下方區域（腳尖或腳跟）
                    if (max_idx >= (2*HEIGHT/3)) begin
                        if (smooth_hist[max_idx] > max_ones_last3) begin
                            max_ones_last3 <= smooth_hist[max_idx];
                            max_line_last3 <= max_idx;
                        end
                    end

                    if (max_idx == HEIGHT-1) begin
                        // 所有行都檢查完畢，進入邊界檢測
                        boundary_idx <= min_line_mid;  // 從足弓位置開始
                        boundary_dir <= 0;              // 先向上搜尋(toe)
                        state        <= S_BOUNDARY;
                    end else begin
                        max_idx <= max_idx + 1;
                    end
                end

                // ===============================
                // S_BOUNDARY: 尋找腳趾頭和腳跟邊界
                // 從足弓(min_line_mid)向上下搜尋第一個空行
                // ===============================
                S_BOUNDARY: begin
                    if (boundary_dir == 0) begin
                        // 向上搜尋腳趾頭邊界
                        if (histogram[boundary_idx] == 0 || boundary_idx == 0) begin
                            // 找到第一個空行，前一行就是腳趾頭邊界
                            if (boundary_idx == 0) begin
                                toe_y <= 0;
                                toe_x <= (first_x[0] + last_x[0]) >> 1;
                            end else begin
                                toe_y <= boundary_idx + 1;
                                toe_x <= (first_x[boundary_idx + 1] + last_x[boundary_idx + 1]) >> 1;
                            end

                            // 切換到向下搜尋腳跟邊界
                            boundary_idx <= min_line_mid;
                            boundary_dir <= 1;
                        end else begin
                            // 繼續向上搜尋
                            boundary_idx <= boundary_idx - 1;
                        end
                    end else begin
                        // 向下搜尋腳跟邊界
                        if (histogram[boundary_idx] == 0 || boundary_idx == HEIGHT-1) begin
                            // 找到第一個空行，前一行就是腳跟邊界
                            if (boundary_idx == HEIGHT-1) begin
                                heel_y <= HEIGHT-1;
                                heel_x <= (first_x[HEIGHT-1] + last_x[HEIGHT-1]) >> 1;
                            end else begin
                                heel_y <= boundary_idx - 1;
                                heel_x <= (first_x[boundary_idx - 1] + last_x[boundary_idx - 1]) >> 1;
                            end

                            // 記錄後三分之一峰值行的左右邊界
                            last3_left_x  <= first_x[max_line_last3];
                            last3_right_x <= last_x[max_line_last3];

                            // 邊界檢測完成，進入完成狀態
                            done  <= 1;
                            state <= S_DONE;
                        end else begin
                            // 繼續向下搜尋
                            boundary_idx <= boundary_idx + 1;
                        end
                    end
                end

                // ===============================
                // S_DONE: 完成狀態
                // 保持 done 信號直到重置
                // ===============================
                S_DONE: begin
                    done <= 1;
                end
            endcase
        end
    end

endmodule

