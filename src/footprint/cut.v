module cut #(
    parameter WIDTH  = 640,
    parameter HEIGHT = 480
)(
    input wire clk,              // 時鐘信號
    input wire rst,              // 重置信號 (高電平有效)
    input wire in_valid,         // 輸入有效信號
    input wire pixel,            // 像素資料 (1bit)
    output reg done,             // 處理完成標誌
    output reg [COL_BITS-1:0] x_cut,      // 分割線位置
    output reg [COL_BITS-1:0] r_high,     // 右峰值位置
    output reg [COL_BITS-1:0] l_high      // 左峰值位置
);

    // ========================================
    // 衍生常數（從 WIDTH/HEIGHT 計算）
    // ========================================
    localparam PIXELS    = WIDTH * HEIGHT;
    localparam COL_BITS  = $clog2(WIDTH);       // 列索引位元寬（1280 → 11）
    localparam ROW_BITS  = $clog2(HEIGHT);      // 行索引位元寬（720 → 10）
    localparam PIX_BITS  = $clog2(PIXELS + 1);  // pixel counter 位元寬
    localparam CNT_BITS  = $clog2(HEIGHT + 1);  // 每列計數最大值 = HEIGHT
    localparam HALF_W    = WIDTH >> 1;          // 左右半邊分界

    // 流式處理：只儲存每列的像素計數，不儲存整張圖
    reg [CNT_BITS-1:0] col_count [0:WIDTH-1]; // col_count per column (max = HEIGHT)

    // 狀態定義（One-Hot 編碼）
    localparam RESET     = 5'b00001;  // 復位狀態（逐步清零陣列）
    localparam IDLE      = 5'b00010;
    localparam RECEIVE   = 5'b00100;
    localparam FIND_PEAK = 5'b01000;
    localparam DONE      = 5'b10000;

    reg [4:0] state;
    reg [PIX_BITS-1:0] pixel_count;  // pixel_count: 0 to PIXELS-1, width = PIX_BITS
    reg [COL_BITS-1:0] current_col;  // current_col (0 to WIDTH-1)
    reg [ROW_BITS-1:0] current_row;  // current_row (0 to HEIGHT-1)

    // 峰值搜尋用變數
    reg [COL_BITS-1:0] search_col;    // 搜尋用列索引
    reg [COL_BITS-1:0] max_col_left;  // 左半邊峰值列位置
    reg [CNT_BITS-1:0] max_val_left;  // 左半邊峰值數量
    reg [COL_BITS-1:0] max_col_right; // 右半邊峰值列位置
    reg [CNT_BITS-1:0] max_val_right; // 右半邊峰值數量

    // 復位計數器（用於逐步清零陣列）
    reg [COL_BITS-1:0] reset_idx;

    // 主狀態機
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= RESET;
            pixel_count <= 0;
            current_col <= 0;
            current_row <= 0;
            done <= 0;
            x_cut <= 0;
            l_high <= 0;
            r_high <= 0;
            search_col <= 0;
            max_col_left <= 0;
            max_val_left <= 0;
            max_col_right <= 0;
            max_val_right <= 0;
            reset_idx <= 0;
        end else begin
            case (state)
                // 復位狀態：逐步清零 col_count 陣列
                RESET: begin
                    col_count[reset_idx] <= 0;
                    if (reset_idx == WIDTH-1) begin
                        state <= IDLE;
                        reset_idx <= 0;
                    end else begin
                        reset_idx <= reset_idx + 1;
                    end
                end

                IDLE: begin
                    done <= 0;
                    pixel_count <= 0;
                    current_col <= 0;
                    current_row <= 0;
                    search_col <= 0;
                    max_col_left <= 0;
                    max_val_left <= 0;
                    max_col_right <= 0;
                    max_val_right <= 0;

                    if (in_valid) begin
                        state <= RECEIVE;
                        `ifdef SIMULATION
                        $display("Starting to receive and process 307200 pixels...");
                        `endif
                    end
                end

                RECEIVE: begin
                    if (in_valid) begin
                        // 進度顯示
                        `ifdef SIMULATION
                        if (pixel_count[13:0] == 14'd0) begin  // 每 16384 個像素顯示一次
                            $display("Received %d / 307200 pixels (%.1f%%)", pixel_count, (pixel_count * 100.0) / 307200);
                        end
                        `endif

                        // 直接累加到對應列的計數器（垂直直方圖）
                        if (pixel) begin
                            col_count[current_col] <= col_count[current_col] + 1;
                        end

                        // 更新像素計數
                        pixel_count <= pixel_count + 1;

                        // 更新行列位置
                        if (current_col == WIDTH-1) begin
                            // 當前行結束，換到下一行的第一列
                            current_col <= 0;
                            current_row <= current_row + 1;
                        end else begin
                            // 下一列
                            current_col <= current_col + 1;
                        end
                    end else if (pixel_count >= PIXELS - 1) begin
                        // in_valid 已經變為 0，且所有像素已接收，轉換到峰值搜尋狀態
                        `ifdef SIMULATION
                        $display("All 307200 pixels received!");
                        $display("Starting peak finding...");
                        `endif
                        search_col <= 0;
                        state <= FIND_PEAK;
                    end
                end

                FIND_PEAK: begin
                    // 搜尋峰值：每個週期檢查一列
                    if (search_col < HALF_W) begin
                        // 左半邊
                        if (col_count[search_col] > max_val_left) begin
                            max_val_left <= col_count[search_col];
                            max_col_left <= search_col;
                        end
                    end else begin
                        // 右半邊
                        if (col_count[search_col] > max_val_right) begin
                            max_val_right <= col_count[search_col];
                            max_col_right <= search_col;
                        end
                    end

                    // 進度顯示
                    `ifdef SIMULATION
                    if (search_col[5:0] == 6'd0) begin
                        $display("Peak finding: column %d / 640 (%.1f%%)", search_col, (search_col * 100.0) / 640);
                    end
                    `endif

                    if (search_col == WIDTH-1) begin
                        // 完成峰值搜尋
                        `ifdef SIMULATION
                        $display("Peak finding completed!");
                        $display("Left peak at column %d (count=%d)", max_col_left, max_val_left);
                        $display("Right peak at column %d (count=%d)", max_col_right, max_val_right);
                        `endif

                        l_high <= max_col_left;
                        r_high <= max_col_right;
                        x_cut <= (max_col_left + max_col_right) >> 1;
                        state <= DONE;
                    end else begin
                        search_col <= search_col + 1;
                    end
                end

                DONE: begin
                    done <= 1;
                    // 保持在此狀態，直到重置
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
