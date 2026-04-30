`timescale 1ns / 1ps

module tb_AXI_RGBToGray;

reg        clk    = 0;
reg        rst_n  = 0;
reg [23:0] s_tdata  = 0;
reg        s_tvalid = 0;
reg        s_tuser  = 0;
reg        s_tlast  = 0;
reg        m_tready = 1;

wire        s_tready;
wire [23:0] m_tdata;
wire        m_tvalid;
wire        m_tuser;
wire        m_tlast;

AXI_RGBToGray dut (
    .StreamClk            (clk),
    .sStreamReset_n       (rst_n),
    .s_axis_video_tready  (s_tready),
    .s_axis_video_tdata   (s_tdata),
    .s_axis_video_tvalid  (s_tvalid),
    .s_axis_video_tuser   (s_tuser),
    .s_axis_video_tlast   (s_tlast),
    .m_axis_video_tready  (m_tready),
    .m_axis_video_tdata   (m_tdata),
    .m_axis_video_tvalid  (m_tvalid),
    .m_axis_video_tuser   (m_tuser),
    .m_axis_video_tlast   (m_tlast)
);

always #5 clk = ~clk;

integer pass_cnt = 0;
integer fail_cnt = 0;

task check_y;
    input [7:0] expected;
    input [7:0] test_num;
    begin
        if (m_tdata[7:0]   === expected &&
            m_tdata[15:8]  === expected &&
            m_tdata[23:16] === expected &&
            m_tvalid === 1'b1) begin
            $display("PASS Test %0d: Y=0x%02X (%0d)", test_num, m_tdata[7:0], m_tdata[7:0]);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("FAIL Test %0d: expected Y=%0d(0x%02X), got tdata=0x%06X tvalid=%b",
                     test_num, expected, expected, m_tdata, m_tvalid);
            fail_cnt = fail_cnt + 1;
        end
    end
endtask

initial begin
    repeat(4) @(posedge clk);
    rst_n = 1;
    @(posedge clk); #1;

    // Test 1: Black (R=0, B=0, G=0) → Y=0
    // tdata bit layout: [23:16]=R, [15:8]=B, [7:0]=G
    s_tdata = 24'h000000; s_tvalid = 1'b1; s_tuser = 1'b1; s_tlast = 1'b0;
    @(posedge clk); #1;
    check_y(8'd0, 8'd1);

    // Test 2: White (R=255, B=255, G=255) → Y=255
    // Y = (77*255 + 150*255 + 29*255) >> 8 = 256*255 >> 8 = 255
    s_tdata = 24'hFFFFFF; s_tvalid = 1'b1;
    @(posedge clk); #1;
    check_y(8'd255, 8'd2);

    // Test 3: Pure Red (R=255, B=0, G=0) → tdata=24'hFF0000
    // Y = (77*255 + 150*0 + 29*0) >> 8 = 19635 >> 8 = 76
    s_tdata = 24'hFF0000; s_tvalid = 1'b1;
    @(posedge clk); #1;
    check_y(8'd76, 8'd3);

    // Test 4: Pure Green (R=0, B=0, G=255) → tdata=24'h0000FF
    // Y = (77*0 + 150*255 + 29*0) >> 8 = 38250 >> 8 = 149
    s_tdata = 24'h0000FF; s_tvalid = 1'b1;
    @(posedge clk); #1;
    check_y(8'd149, 8'd4);

    // Test 5: Pure Blue (R=0, B=255, G=0) → tdata=24'h00FF00
    // Y = (77*0 + 150*0 + 29*255) >> 8 = 7395 >> 8 = 28
    s_tdata = 24'h00FF00; s_tvalid = 1'b1;
    @(posedge clk); #1;
    check_y(8'd28, 8'd5);

    // Test 6: tuser=1 tlast=1 pass-through (1-cycle delay)
    s_tdata = 24'h808080; s_tvalid = 1'b1; s_tuser = 1'b1; s_tlast = 1'b1;
    @(posedge clk); #1;
    if (m_tuser === 1'b1 && m_tlast === 1'b1 && m_tvalid === 1'b1) begin
        $display("PASS Test 6: tuser/tlast pass-through");
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("FAIL Test 6: tuser=%b tlast=%b tvalid=%b (all expected 1)",
                 m_tuser, m_tlast, m_tvalid);
        fail_cnt = fail_cnt + 1;
    end

    // Test 7: tvalid=0 → m_tvalid=0
    s_tvalid = 1'b0;
    @(posedge clk); #1;
    if (m_tvalid === 1'b0) begin
        $display("PASS Test 7: tvalid=0 propagated");
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("FAIL Test 7: expected m_tvalid=0, got %b", m_tvalid);
        fail_cnt = fail_cnt + 1;
    end

    // Test 8: Backpressure – tready=0 holds output unchanged
    // First, send a known pixel at tready=1
    // R=170(0xAA), B=85(0x55), G=204(0xCC) → tdata=24'hAA55CC
    // Y = (77*170 + 150*204 + 29*85) >> 8 = (13090+30600+2465) >> 8 = 46155 >> 8 = 180 (0xB4)
    m_tready = 1'b1;
    s_tdata = 24'hAA55CC; s_tvalid = 1'b1;
    @(posedge clk); #1;
    check_y(8'd180, 8'd8);
    // Now stall: tready=0, change input – output must not update
    m_tready = 1'b0;
    s_tdata  = 24'hFFFFFF;
    @(posedge clk); #1;
    if (m_tdata === 24'hB4B4B4) begin
        $display("PASS Test 9: backpressure holds output at Y=0xB4");
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("FAIL Test 9: expected 24'hB4B4B4, got 0x%06X", m_tdata);
        fail_cnt = fail_cnt + 1;
    end
    m_tready = 1'b1;

    $display("=== Results: %0d PASS, %0d FAIL ===", pass_cnt, fail_cnt);
    if (fail_cnt > 0) $display("SIMULATION FAILED");
    else              $display("SIMULATION PASSED");
    $finish;
end

endmodule
