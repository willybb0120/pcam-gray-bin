`timescale 1ns/1ps

module tb_footprint_top;

    // 預設 640x480，可由 iverilog -DRES_1280x720 切換 1280x720
    localparam WIDTH  = `ifdef RES_1280x720 1280 `else 640  `endif;
    localparam HEIGHT = `ifdef RES_1280x720 720  `else 480  `endif;
    localparam PIXELS = WIDTH * HEIGHT;

    // ========================================
    // 測試訊號宣告
    // ========================================
    reg clk;
    reg rst;
    reg in_valid;
    reg pixel;

    // cut 模組輸出
    wire cut_done;
    wire [$clog2(WIDTH)-1:0] x_cut;
    wire [$clog2(WIDTH)-1:0] r_high;
    wire [$clog2(WIDTH)-1:0] l_high;

    // label3_left 輸出
    wire left_done;
    wire [31:0] left_max_ones_half;
    wire [31:0] left_max_line_half;
    wire [31:0] left_min_ones_mid;
    wire [31:0] left_min_line_mid;
    wire [31:0] left_max_ones_last3;
    wire [31:0] left_max_line_last3;
    wire [31:0] left_toe_y;
    wire [31:0] left_toe_x;
    wire [31:0] left_heel_y;
    wire [31:0] left_heel_x;
    wire [31:0] left_last3_left_x;
    wire [31:0] left_last3_right_x;

    // label3_right 輸出
    wire right_done;
    wire [31:0] right_max_ones_half;
    wire [31:0] right_max_line_half;
    wire [31:0] right_min_ones_mid;
    wire [31:0] right_min_line_mid;
    wire [31:0] right_max_ones_last3;
    wire [31:0] right_max_line_last3;
    wire [31:0] right_toe_y;
    wire [31:0] right_toe_x;
    wire [31:0] right_heel_y;
    wire [31:0] right_heel_x;
    wire [31:0] right_last3_left_x;
    wire [31:0] right_last3_right_x;

    // label2_forefoot_left 輸出
    wire left_forefoot_done;
    wire [31:0] left_forefoot_left_x;
    wire [31:0] left_forefoot_left_y;
    wire [31:0] left_forefoot_right_x;
    wire [31:0] left_forefoot_right_y;

    // label2_forefoot_right 輸出
    wire right_forefoot_done;
    wire [31:0] right_forefoot_left_x;
    wire [31:0] right_forefoot_left_y;
    wire [31:0] right_forefoot_right_x;
    wire [31:0] right_forefoot_right_y;

    // ========================================
    // 實例化待測模組
    // ========================================
    footprint_top #(
        .WIDTH(WIDTH),
        .HEIGHT(HEIGHT)
    ) uut (
        .clk(clk),
        .rst(rst),
        .in_valid(in_valid),
        .pixel(pixel),
        .cut_done(cut_done),
        .x_cut(x_cut),
        .r_high(r_high),
        .l_high(l_high),
        .left_done(left_done),
        .left_max_ones_half(left_max_ones_half),
        .left_max_line_half(left_max_line_half),
        .left_min_ones_mid(left_min_ones_mid),
        .left_min_line_mid(left_min_line_mid),
        .left_max_ones_last3(left_max_ones_last3),
        .left_max_line_last3(left_max_line_last3),
        .left_toe_y(left_toe_y),
        .left_toe_x(left_toe_x),
        .left_heel_y(left_heel_y),
        .left_heel_x(left_heel_x),
        .left_last3_left_x(left_last3_left_x),
        .left_last3_right_x(left_last3_right_x),
        .right_done(right_done),
        .right_max_ones_half(right_max_ones_half),
        .right_max_line_half(right_max_line_half),
        .right_min_ones_mid(right_min_ones_mid),
        .right_min_line_mid(right_min_line_mid),
        .right_max_ones_last3(right_max_ones_last3),
        .right_max_line_last3(right_max_line_last3),
        .right_toe_y(right_toe_y),
        .right_toe_x(right_toe_x),
        .right_heel_y(right_heel_y),
        .right_heel_x(right_heel_x),
        .right_last3_left_x(right_last3_left_x),
        .right_last3_right_x(right_last3_right_x),
        .left_forefoot_done(left_forefoot_done),
        .left_forefoot_left_x(left_forefoot_left_x),
        .left_forefoot_left_y(left_forefoot_left_y),
        .left_forefoot_right_x(left_forefoot_right_x),
        .left_forefoot_right_y(left_forefoot_right_y),
        .right_forefoot_done(right_forefoot_done),
        .right_forefoot_left_x(right_forefoot_left_x),
        .right_forefoot_left_y(right_forefoot_left_y),
        .right_forefoot_right_x(right_forefoot_right_x),
        .right_forefoot_right_y(right_forefoot_right_y)
    );

    // ========================================
    // 時鐘生成：10ns 週期 (100MHz)
    // ========================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ========================================
    // 測試流程
    // ========================================
    integer file;
    integer scan_result;
    integer i;
    reg [0:0] pixel_data;

    initial begin
        $display("===========================================");
        $display("Starting tb_top simulation");
        $display("===========================================");

        // 初始化
        rst = 1;
        in_valid = 0;
        pixel = 0;

        // 重置
        #20;
        rst = 0;

        // 最長需要 WIDTH cycles for cut.v RESET (each module's RESET takes up to max(WIDTH, HEIGHT) cycles)
        #(WIDTH * 12 + 1000);

        // =======================================
        // 第一階段：送入圖像給 cut 模組
        // =======================================
        $display("\n[Phase 1] Feeding image to cut module...");

        file = $fopen("input.txt", "r");
        if (file == 0) begin
            $display("Error: Cannot open input.txt");
            $finish;
        end

        in_valid = 1;

        for (i = 0; i < PIXELS; i = i + 1) begin
            scan_result = $fscanf(file, "%b", pixel_data);
            if (scan_result != 1) begin
                $display("Error reading pixel %d", i);
                $finish;
            end
            pixel = pixel_data[0];

            // 進度顯示（每 10000 個像素）
            if (i % 10000 == 0) begin
                $display("  Phase 1: Sent %d / %0d pixels (%.1f%%)", i, PIXELS, (i * 100.0) / PIXELS);
            end

            @(posedge clk);
        end

        // 等待最後一個像素被處理
        @(posedge clk);
        $display("  Phase 1: All %0d pixels sent!", PIXELS);

        in_valid = 0;
        $fclose(file);

        // 等待 cut 完成
        $display("  Waiting for cut_done...");
        wait(cut_done);
        @(posedge clk);

        $display("\n[Phase 1 Complete]");
        $display("  x_cut  = %d", x_cut);
        $display("  l_high = %d", l_high);
        $display("  r_high = %d", r_high);

        // =======================================
        // 第二階段：再次送入圖像給 label3 模組
        // =======================================
        $display("\n[Phase 2] Feeding image to label3_left and label3_right...");

        // 重新打開檔案
        file = $fopen("input.txt", "r");
        if (file == 0) begin
            $display("Error: Cannot reopen input.txt");
            $finish;
        end

        in_valid = 1;

        for (i = 0; i < PIXELS; i = i + 1) begin
            scan_result = $fscanf(file, "%b", pixel_data);
            if (scan_result != 1) begin
                $display("Error reading pixel %d", i);
                $finish;
            end
            pixel = pixel_data[0];

            // 進度顯示（每 10000 個像素）
            if (i % 10000 == 0) begin
                $display("  Phase 2: Sent %d / %0d pixels (%.1f%%)", i, PIXELS, (i * 100.0) / PIXELS);
            end

            @(posedge clk);
        end

        // 等待最後一個像素被處理
        @(posedge clk);
        $display("  Phase 2: All %0d pixels sent!", PIXELS);

        in_valid = 0;
        $fclose(file);

        // 等待兩個 label3 都完成
        $display("  Waiting for left_done and right_done...");
        wait(left_done && right_done);
        @(posedge clk);

        $display("\n[Phase 2 Complete]");
        $display("  Left foot:  mid_row=%d", left_min_line_mid);
        $display("  Right foot: mid_row=%d", right_min_line_mid);

        // =======================================
        // 第三階段：再次送入圖像給 label2_forefoot 模組
        // =======================================
        $display("\n[Phase 3] Feeding image to label2_forefoot...");

        // 重新打開檔案
        file = $fopen("input.txt", "r");
        if (file == 0) begin
            $display("Error: Cannot reopen input.txt");
            $finish;
        end

        in_valid = 1;

        for (i = 0; i < PIXELS; i = i + 1) begin
            scan_result = $fscanf(file, "%b", pixel_data);
            if (scan_result != 1) begin
                $display("Error reading pixel %d", i);
                $finish;
            end
            pixel = pixel_data[0];

            // 進度顯示（每 10000 個像素）
            if (i % 10000 == 0) begin
                $display("  Phase 3: Sent %d / %0d pixels (%.1f%%)", i, PIXELS, (i * 100.0) / PIXELS);
            end

            @(posedge clk);
        end

        // 等待最後一個像素被處理
        @(posedge clk);
        $display("  Phase 3: All %0d pixels sent!", PIXELS);

        in_valid = 0;
        $fclose(file);

        // 等待兩個 label2_forefoot 都完成
        $display("  Waiting for left_forefoot_done and right_forefoot_done...");
        wait(left_forefoot_done && right_forefoot_done);
        @(posedge clk);

        // =======================================
        // 顯示最終結果
        // =======================================
        $display("\n===========================================");
        $display("SIMULATION COMPLETE");
        $display("===========================================");

        $display("\n[Cut Results]");
        $display("  x_cut  = %d (split line)", x_cut);
        $display("  l_high = %d (left peak)", l_high);
        $display("  r_high = %d (right peak)", r_high);

        $display("\n[Left Foot Results]");
        $display("  上半部峰值:     row %d (%d pixels)", left_max_line_half, left_max_ones_half);
        $display("  中間部分最小值: row %d (%d pixels)", left_min_line_mid, left_min_ones_mid);
        $display("  後三分之一峰值: row %d (%d pixels)", left_max_line_last3, left_max_ones_last3);
        $display("  後三分之一邊界: 左X=%d, 右X=%d, 寬度=%d", left_last3_left_x, left_last3_right_x, left_last3_right_x - left_last3_left_x);
        $display("  腳趾頭邊界:     Y=%d, X=%d", left_toe_y, left_toe_x);
        $display("  腳跟邊界:       Y=%d, X=%d", left_heel_y, left_heel_x);

        $display("\n[Right Foot Results]");
        $display("  上半部峰值:     row %d (%d pixels)", right_max_line_half, right_max_ones_half);
        $display("  中間部分最小值: row %d (%d pixels)", right_min_line_mid, right_min_ones_mid);
        $display("  後三分之一峰值: row %d (%d pixels)", right_max_line_last3, right_max_ones_last3);
        $display("  後三分之一邊界: 左X=%d, 右X=%d, 寬度=%d", right_last3_left_x, right_last3_right_x, right_last3_right_x - right_last3_left_x);
        $display("  腳趾頭邊界:     Y=%d, X=%d", right_toe_y, right_toe_x);
        $display("  腳跟邊界:       Y=%d, X=%d", right_heel_y, right_heel_x);

        $display("\n[Left Forefoot Boundary]");
        $display("  左邊界點: X=%d, Y=%d", left_forefoot_left_x, left_forefoot_left_y);
        $display("  右邊界點: X=%d, Y=%d", left_forefoot_right_x, left_forefoot_right_y);
        $display("  前腳掌寬度: %d pixels", left_forefoot_right_x - left_forefoot_left_x);

        $display("\n[Right Forefoot Boundary]");
        $display("  左邊界點: X=%d, Y=%d", right_forefoot_left_x, right_forefoot_left_y);
        $display("  右邊界點: X=%d, Y=%d", right_forefoot_right_x, right_forefoot_right_y);
        $display("  前腳掌寬度: %d pixels", right_forefoot_right_x - right_forefoot_left_x);

        // =======================================
        // 12個關鍵座標點輸出 (左腳6點 + 右腳6點)
        // =======================================
        $display("\n===========================================");
        $display("12 Key Coordinate Points Summary");
        $display("===========================================");

        $display("\n[Left Foot - 6 Points]");
        $display("  1. Toe (腳趾頭):           (%4d, %4d)", left_toe_x, left_toe_y);
        $display("  2. Heel (腳跟):            (%4d, %4d)", left_heel_x, left_heel_y);
        $display("  3. Forefoot Left (前掌左):  (%4d, %4d)", left_forefoot_left_x, left_forefoot_left_y);
        $display("  4. Forefoot Right (前掌右): (%4d, %4d)", left_forefoot_right_x, left_forefoot_right_y);
        $display("  5. Last3 Left (後1/3左):    (%4d, %4d)", left_last3_left_x, left_max_line_last3);
        $display("  6. Last3 Right (後1/3右):   (%4d, %4d)", left_last3_right_x, left_max_line_last3);

        $display("\n[Right Foot - 6 Points]");
        $display("  7. Toe (腳趾頭):           (%4d, %4d)", right_toe_x, right_toe_y);
        $display("  8. Heel (腳跟):            (%4d, %4d)", right_heel_x, right_heel_y);
        $display("  9. Forefoot Left (前掌左):  (%4d, %4d)", right_forefoot_left_x, right_forefoot_left_y);
        $display(" 10. Forefoot Right (前掌右): (%4d, %4d)", right_forefoot_right_x, right_forefoot_right_y);
        $display(" 11. Last3 Left (後1/3左):    (%4d, %4d)", right_last3_left_x, right_max_line_last3);
        $display(" 12. Last3 Right (後1/3右):   (%4d, %4d)", right_last3_right_x, right_max_line_last3);

        $display("\n===========================================");

        // 結束模擬
        #100;
        $finish;
    end

    // ========================================
    // 監控關鍵狀態變化
    // ========================================
    initial begin
        @(posedge cut_done);
        $display("\n*** cut_done asserted at time %t ***", $time);
    end

    initial begin
        @(posedge left_done);
        $display("\n*** left_done asserted at time %t ***", $time);
    end

    initial begin
        @(posedge right_done);
        $display("\n*** right_done asserted at time %t ***", $time);
    end

    initial begin
        @(posedge left_forefoot_done);
        $display("\n*** left_forefoot_done asserted at time %t ***", $time);
    end

    initial begin
        @(posedge right_forefoot_done);
        $display("\n*** right_forefoot_done asserted at time %t ***", $time);
    end

    // ========================================
    // 超時保護 (防止模擬卡住)
    // ========================================
    initial begin
        #(PIXELS * 60); // 約 3x PIXELS cycles 緩衝（一輪掃描 + reset + 處理時間）
        $display("\n!!! TIMEOUT: Simulation took too long !!!");
        $finish;
    end

endmodule
