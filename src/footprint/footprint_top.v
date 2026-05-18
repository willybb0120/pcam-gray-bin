module footprint_top #(
    parameter WIDTH  = 1280,
    parameter HEIGHT = 720
)(
    input wire clk,              // 時鐘信號
    input wire rst,              // 重置信號 (高電平有效)
    input wire in_valid,         // 輸入有效信號
    input wire pixel,            // 像素資料 (1bit)

    // cut 模組輸出
    output wire cut_done,        // cut 處理完成標誌
    output wire [$clog2(WIDTH)-1:0] x_cut,     // 分割線位置
    output wire [$clog2(WIDTH)-1:0] r_high,    // 右峰值位置
    output wire [$clog2(WIDTH)-1:0] l_high,    // 左峰值位置

    // label3_left 輸出（左腳）
    output wire left_done,
    output wire [31:0] left_max_ones_half,
    output wire [31:0] left_max_line_half,
    output wire [31:0] left_min_ones_mid,
    output wire [31:0] left_min_line_mid,
    output wire [31:0] left_max_ones_last3,
    output wire [31:0] left_max_line_last3,
    output wire [31:0] left_toe_y,
    output wire [31:0] left_toe_x,
    output wire [31:0] left_heel_y,
    output wire [31:0] left_heel_x,
    output wire [31:0] left_last3_left_x,
    output wire [31:0] left_last3_right_x,

    // label3_right 輸出（右腳）
    output wire right_done,
    output wire [31:0] right_max_ones_half,
    output wire [31:0] right_max_line_half,
    output wire [31:0] right_min_ones_mid,
    output wire [31:0] right_min_line_mid,
    output wire [31:0] right_max_ones_last3,
    output wire [31:0] right_max_line_last3,
    output wire [31:0] right_toe_y,
    output wire [31:0] right_toe_x,
    output wire [31:0] right_heel_y,
    output wire [31:0] right_heel_x,
    output wire [31:0] right_last3_left_x,
    output wire [31:0] right_last3_right_x,

    // label2_forefoot_left 輸出（左腳前脚掌边界）
    output wire left_forefoot_done,
    output wire [31:0] left_forefoot_left_x,
    output wire [31:0] left_forefoot_left_y,
    output wire [31:0] left_forefoot_right_x,
    output wire [31:0] left_forefoot_right_y,

    // label2_forefoot_right 輸出（右腳前脚掌边界）
    output wire right_forefoot_done,
    output wire [31:0] right_forefoot_left_x,
    output wire [31:0] right_forefoot_left_y,
    output wire [31:0] right_forefoot_right_x,
    output wire [31:0] right_forefoot_right_y
);

    // ========================================
    // 衍生常數（從 WIDTH/HEIGHT 計算）
    // ========================================
    localparam COL_BITS = $clog2(WIDTH);
    localparam ROW_BITS = $clog2(HEIGHT);

    // ========================================
    // 內部信號
    // ========================================

    // 當前像素位置計數器
    reg [COL_BITS-1:0] current_col;   // 當前列 (0 to WIDTH-1)
    reg [ROW_BITS-1:0] current_row;   // 當前行 (0 to HEIGHT-1)

    // 給 label3 模組的控制信號
    reg left_valid, right_valid;
    reg left_pixel, right_pixel;

    // label3 啟動信號（當 cut 完成後才啟動 label3）
    reg label3_enable;
    reg label3_start;  // 用於第二輪掃描的啟動信號

    // 給 label2_forefoot 模組的控制信號
    reg left_forefoot_valid, right_forefoot_valid;
    reg left_forefoot_pixel, right_forefoot_pixel;

    // label2_forefoot 啟動信號（當 label3 完成後才啟動 label2_forefoot）
    reg label2_enable;
    reg label2_start;  // 用於第三輪掃描的啟動信號

    // ========================================
    // 實例化 cut 模組（第一階段：找到分割線）
    // ========================================
    cut #(
        .WIDTH(WIDTH),
        .HEIGHT(HEIGHT)
    ) u_cut (
        .clk(clk),
        .rst(rst),
        .in_valid(in_valid),
        .pixel(pixel),
        .done(cut_done),
        .x_cut(x_cut),
        .r_high(r_high),
        .l_high(l_high)
    );

    // ========================================
    // 實例化 label3_left（第二階段：處理左腳）
    // 使用固定寬度 640，但實際只處理 [0, x_cut) 的像素
    // ========================================
    label3 #(
        .WIDTH(WIDTH),
        .HEIGHT(HEIGHT)
    ) u_label3_left (
        .clk(clk),
        .rst(rst),
        .in_valid(left_valid),
        .pixel(left_pixel),
        .max_ones_half(left_max_ones_half),
        .max_line_half(left_max_line_half),
        .min_ones_mid(left_min_ones_mid),
        .min_line_mid(left_min_line_mid),
        .max_ones_last3(left_max_ones_last3),
        .max_line_last3(left_max_line_last3),
        .toe_y(left_toe_y),
        .toe_x(left_toe_x),
        .heel_y(left_heel_y),
        .heel_x(left_heel_x),
        .last3_left_x(left_last3_left_x),
        .last3_right_x(left_last3_right_x),
        .done(left_done)
    );

    // ========================================
    // 實例化 label3_right（第二階段：處理右腳）
    // 使用固定寬度 640，但實際只處理 [x_cut, 640) 的像素
    // ========================================
    label3 #(
        .WIDTH(WIDTH),
        .HEIGHT(HEIGHT)
    ) u_label3_right (
        .clk(clk),
        .rst(rst),
        .in_valid(right_valid),
        .pixel(right_pixel),
        .max_ones_half(right_max_ones_half),
        .max_line_half(right_max_line_half),
        .min_ones_mid(right_min_ones_mid),
        .min_line_mid(right_min_line_mid),
        .max_ones_last3(right_max_ones_last3),
        .max_line_last3(right_max_line_last3),
        .toe_y(right_toe_y),
        .toe_x(right_toe_x),
        .heel_y(right_heel_y),
        .heel_x(right_heel_x),
        .last3_left_x(right_last3_left_x),
        .last3_right_x(right_last3_right_x),
        .done(right_done)
    );

    // ========================================
    // 實例化 label2_forefoot_left（第三階段：找前脚掌边界）
    // 使用 left_min_line_mid 作为分界线
    // ========================================
    label2_forefoot #(
        .WIDTH(WIDTH),
        .HEIGHT(HEIGHT)
    ) u_label2_forefoot_left (
        .clk(clk),
        .rst(rst),
        .in_valid(left_forefoot_valid),
        .pixel(left_forefoot_pixel),
        .row_boundary(left_min_line_mid),
        .left_x(left_forefoot_left_x),
        .left_y(left_forefoot_left_y),
        .right_x(left_forefoot_right_x),
        .right_y(left_forefoot_right_y),
        .done(left_forefoot_done)
    );

    // ========================================
    // 實例化 label2_forefoot_right（第三階段：找前脚掌边界）
    // 使用 right_min_line_mid 作为分界线
    // ========================================
    label2_forefoot #(
        .WIDTH(WIDTH),
        .HEIGHT(HEIGHT)
    ) u_label2_forefoot_right (
        .clk(clk),
        .rst(rst),
        .in_valid(right_forefoot_valid),
        .pixel(right_forefoot_pixel),
        .row_boundary(right_min_line_mid),
        .left_x(right_forefoot_left_x),
        .left_y(right_forefoot_left_y),
        .right_x(right_forefoot_right_x),
        .right_y(right_forefoot_right_y),
        .done(right_forefoot_done)
    );

    // ========================================
    // 像素分割邏輯（第二和第三階段）
    // 第二階段：根據 x_cut 分割像素流給 label3
    // 第三階段：根據 x_cut 分割像素流給 label2_forefoot
    // ========================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            current_col <= 0;
            current_row <= 0;
            left_valid <= 0;
            right_valid <= 0;
            left_pixel <= 0;
            right_pixel <= 0;
            left_forefoot_valid <= 0;
            right_forefoot_valid <= 0;
            left_forefoot_pixel <= 0;
            right_forefoot_pixel <= 0;
            label3_enable <= 0;
            label3_start <= 0;
            label2_enable <= 0;
            label2_start <= 0;
        end else begin
            // 當 cut 完成後，啟動第二階段（label3）
            if (cut_done && !label3_enable) begin
                label3_enable <= 1;
                label3_start <= 1;
                current_col <= 0;
                current_row <= 0;
            end

            // 當 label3 完成後，啟動第三階段（label2_forefoot）
            if (left_done && right_done && !label2_enable) begin
                label2_enable <= 1;
                label2_start <= 1;
                current_col <= 0;
                current_row <= 0;
            end

            // 第二階段：重新掃描像素並分割給左右腳 label3
            if (label3_enable && !label2_enable) begin
                label3_start <= 0;  // 清除啟動信號

                if (in_valid) begin
                    // 有真實像素輸入
                    // 左腳：如果在左側區域，使用真實像素；否則填充 0
                    left_valid <= 1;
                    left_pixel <= (current_col < x_cut) ? pixel : 1'b0;

                    // 右腳：如果在右側區域，使用真實像素；否則填充 0
                    right_valid <= 1;
                    right_pixel <= (current_col >= x_cut) ? pixel : 1'b0;

                    // 更新行列位置
                    if (current_col == WIDTH-1) begin
                        current_col <= 0;
                        current_row <= current_row + 1;
                    end else begin
                        current_col <= current_col + 1;
                    end
                end else begin
                    // 沒有輸入時，關閉 valid 信號
                    left_valid <= 0;
                    right_valid <= 0;
                end
            end else begin
                // label3 未啟動時，保持 valid 為 0
                left_valid <= 0;
                right_valid <= 0;
            end

            // 第三階段：重新掃描像素並分割給左右腳 label2_forefoot
            if (label2_enable) begin
                label2_start <= 0;  // 清除啟動信號

                if (in_valid) begin
                    // 有真實像素輸入
                    // 左腳：如果在左側區域，使用真實像素；否則填充 0
                    left_forefoot_valid <= 1;
                    left_forefoot_pixel <= (current_col < x_cut) ? pixel : 1'b0;

                    // 右腳：如果在右側區域，使用真實像素；否則填充 0
                    right_forefoot_valid <= 1;
                    right_forefoot_pixel <= (current_col >= x_cut) ? pixel : 1'b0;

                    // 更新行列位置
                    if (current_col == WIDTH-1) begin
                        current_col <= 0;
                        current_row <= current_row + 1;
                    end else begin
                        current_col <= current_col + 1;
                    end
                end else begin
                    // 沒有輸入時，關閉 valid 信號
                    left_forefoot_valid <= 0;
                    right_forefoot_valid <= 0;
                end
            end else begin
                // label2 未啟動時，保持 valid 為 0
                left_forefoot_valid <= 0;
                right_forefoot_valid <= 0;
            end
        end
    end

endmodule
