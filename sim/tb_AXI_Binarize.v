`timescale 1ns / 1ps

module tb_AXI_Binarize;

reg        clk    = 0;
reg        rst_n  = 0;
reg [23:0] s_tdata  = 0;
reg        s_tvalid = 0;
reg        s_tuser  = 0;
reg        s_tlast  = 0;
reg        m_tready = 1;

// DUT1: default THRESHOLD = 128
wire        s1_tready;
wire [23:0] m1_tdata;
wire        m1_tvalid;
wire        m1_tuser;
wire        m1_tlast;

AXI_Binarize dut1 (
    .StreamClk            (clk),
    .sStreamReset_n       (rst_n),
    .s_axis_video_tready  (s1_tready),
    .s_axis_video_tdata   (s_tdata),
    .s_axis_video_tvalid  (s_tvalid),
    .s_axis_video_tuser   (s_tuser),
    .s_axis_video_tlast   (s_tlast),
    .m_axis_video_tready  (m_tready),
    .m_axis_video_tdata   (m1_tdata),
    .m_axis_video_tvalid  (m1_tvalid),
    .m_axis_video_tuser   (m1_tuser),
    .m_axis_video_tlast   (m1_tlast)
);

// DUT2: parameter override THRESHOLD = 200
wire        s2_tready;
wire [23:0] m2_tdata;
wire        m2_tvalid;
wire        m2_tuser;
wire        m2_tlast;

AXI_Binarize #(.THRESHOLD(8'd200)) dut2 (
    .StreamClk            (clk),
    .sStreamReset_n       (rst_n),
    .s_axis_video_tready  (s2_tready),
    .s_axis_video_tdata   (s_tdata),
    .s_axis_video_tvalid  (s_tvalid),
    .s_axis_video_tuser   (s_tuser),
    .s_axis_video_tlast   (s_tlast),
    .m_axis_video_tready  (m_tready),
    .m_axis_video_tdata   (m2_tdata),
    .m_axis_video_tvalid  (m2_tvalid),
    .m_axis_video_tuser   (m2_tuser),
    .m_axis_video_tlast   (m2_tlast)
);

always #5 clk = ~clk;

integer pass_cnt = 0;
integer fail_cnt = 0;

reg [23:0] m2_at_199;
reg [23:0] m2_at_200;

task check_bin;
    input [23:0] expected;
    input [7:0]  test_num;
    begin
        if (m1_tdata === expected && m1_tvalid === 1'b1) begin
            $display("PASS Test %0d: out=0x%06X", test_num, m1_tdata);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("FAIL Test %0d: expected 0x%06X tvalid=1, got tdata=0x%06X tvalid=%b",
                     test_num, expected, m1_tdata, m1_tvalid);
            fail_cnt = fail_cnt + 1;
        end
    end
endtask

initial begin
    repeat(4) @(posedge clk);
    rst_n = 1;
    @(posedge clk); #1;

    // Test 1: Y=0 -> black
    s_tdata = 24'h000000; s_tvalid = 1'b1; s_tuser = 1'b1; s_tlast = 1'b0;
    @(posedge clk); #1;
    check_bin(24'h000000, 8'd1);

    // Test 2: Y=255 -> white
    s_tdata = 24'hFFFFFF; s_tvalid = 1'b1; s_tuser = 1'b0;
    @(posedge clk); #1;
    check_bin(24'hFFFFFF, 8'd2);

    // Test 3: Y=128 (boundary, equal to THRESHOLD) -> white
    s_tdata = 24'h808080; s_tvalid = 1'b1;
    @(posedge clk); #1;
    check_bin(24'hFFFFFF, 8'd3);

    // Test 4: Y=127 (below THRESHOLD) -> black
    s_tdata = 24'h7F7F7F; s_tvalid = 1'b1;
    @(posedge clk); #1;
    check_bin(24'h000000, 8'd4);

    // Test 5: Y=129 (above THRESHOLD) -> white
    s_tdata = 24'h818181; s_tvalid = 1'b1;
    @(posedge clk); #1;
    check_bin(24'hFFFFFF, 8'd5);

    // Test 6: tuser/tlast pass-through
    s_tdata = 24'hFFFFFF; s_tvalid = 1'b1; s_tuser = 1'b1; s_tlast = 1'b1;
    @(posedge clk); #1;
    if (m1_tuser === 1'b1 && m1_tlast === 1'b1 && m1_tvalid === 1'b1) begin
        $display("PASS Test 6: tuser/tlast pass-through");
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("FAIL Test 6: tuser=%b tlast=%b tvalid=%b (all expected 1)",
                 m1_tuser, m1_tlast, m1_tvalid);
        fail_cnt = fail_cnt + 1;
    end

    // Test 7: tvalid=0 -> m_tvalid=0
    s_tvalid = 1'b0; s_tuser = 1'b0; s_tlast = 1'b0;
    @(posedge clk); #1;
    if (m1_tvalid === 1'b0) begin
        $display("PASS Test 7: tvalid=0 propagated");
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("FAIL Test 7: expected m_tvalid=0, got %b", m1_tvalid);
        fail_cnt = fail_cnt + 1;
    end

    // Test 8: backpressure - feed white, then stall and change input,
    //         verify m1_tdata holds at white
    m_tready = 1'b1;
    s_tdata = 24'hFFFFFF; s_tvalid = 1'b1;
    @(posedge clk); #1;
    // sanity: output should be white now (covered by Test 2; not counted again)
    m_tready = 1'b0;
    s_tdata  = 24'h000000;  // would be black if not stalled
    @(posedge clk); #1;
    if (m1_tdata === 24'hFFFFFF) begin
        $display("PASS Test 8: backpressure holds output at white");
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("FAIL Test 8: expected 0xFFFFFF held, got 0x%06X", m1_tdata);
        fail_cnt = fail_cnt + 1;
    end
    m_tready = 1'b1;

    // Test 9: parameter override - DUT2 with THRESHOLD=200
    //         Y=199 must be black, Y=200 must be white (single combined PASS)
    s_tdata = 24'hC7C7C7; s_tvalid = 1'b1;  // 0xC7 = 199
    @(posedge clk); #1;
    m2_at_199 = m2_tdata;
    s_tdata = 24'hC8C8C8; s_tvalid = 1'b1;  // 0xC8 = 200
    @(posedge clk); #1;
    m2_at_200 = m2_tdata;
    if (m2_at_199 === 24'h000000 && m2_at_200 === 24'hFFFFFF) begin
        $display("PASS Test 9: parameter override (TH=200) Y=199->black, Y=200->white");
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("FAIL Test 9: Y=199 got 0x%06X (expect black), Y=200 got 0x%06X (expect white)",
                 m2_at_199, m2_at_200);
        fail_cnt = fail_cnt + 1;
    end

    $display("=== Results: %0d PASS, %0d FAIL ===", pass_cnt, fail_cnt);
    if (fail_cnt > 0) $display("SIMULATION FAILED");
    else              $display("SIMULATION PASSED");
    $finish;
end

endmodule
