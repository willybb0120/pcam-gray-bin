`timescale 1ns / 1ps

module tb_AXI_ImageModeSelect;

reg StreamClk = 0;
reg AxiLiteClk = 0;
reg sStreamReset_n = 0;
reg aAxiLiteReset_n = 0;

reg [23:0] s_tdata = 0;
reg        s_tvalid = 0;
reg        s_tuser = 0;
reg        s_tlast = 0;
reg        m_tready = 1;
wire       s_tready;
wire [23:0] m_tdata;
wire       m_tvalid;
wire       m_tuser;
wire       m_tlast;

reg [3:0]  awaddr = 0;
reg        awvalid = 0;
wire       awready;
reg [31:0] wdata = 0;
reg [3:0]  wstrb = 4'hF;
reg        wvalid = 0;
wire       wready;
wire [1:0] bresp;
wire       bvalid;
reg        bready = 0;
reg [3:0]  araddr = 0;
reg        arvalid = 0;
wire       arready;
wire [31:0] rdata;
wire [1:0] rresp;
wire       rvalid;
reg        rready = 0;

AXI_ImageModeSelect dut (
    .StreamClk(StreamClk),
    .sStreamReset_n(sStreamReset_n),
    .AxiLiteClk(AxiLiteClk),
    .aAxiLiteReset_n(aAxiLiteReset_n),
    .s_axis_video_tready(s_tready),
    .s_axis_video_tdata(s_tdata),
    .s_axis_video_tvalid(s_tvalid),
    .s_axis_video_tuser(s_tuser),
    .s_axis_video_tlast(s_tlast),
    .m_axis_video_tready(m_tready),
    .m_axis_video_tdata(m_tdata),
    .m_axis_video_tvalid(m_tvalid),
    .m_axis_video_tuser(m_tuser),
    .m_axis_video_tlast(m_tlast),
    .s_axi_awaddr(awaddr),
    .s_axi_awvalid(awvalid),
    .s_axi_awready(awready),
    .s_axi_wdata(wdata),
    .s_axi_wstrb(wstrb),
    .s_axi_wvalid(wvalid),
    .s_axi_wready(wready),
    .s_axi_bresp(bresp),
    .s_axi_bvalid(bvalid),
    .s_axi_bready(bready),
    .s_axi_araddr(araddr),
    .s_axi_arvalid(arvalid),
    .s_axi_arready(arready),
    .s_axi_rdata(rdata),
    .s_axi_rresp(rresp),
    .s_axi_rvalid(rvalid),
    .s_axi_rready(rready)
);

always #5 StreamClk = ~StreamClk;
always #5 AxiLiteClk = ~AxiLiteClk;

integer pass_cnt = 0;
integer fail_cnt = 0;
integer test_cycles = 0;
integer handshake_cnt = 0;

task check_pixel;
    input [23:0] expected;
    input [7:0] test_num;
    begin
        if (m_tdata === expected && m_tvalid === 1'b1) begin
            $display("PASS Test %0d: out=0x%06X", test_num, m_tdata);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("FAIL Test %0d: expected 0x%06X valid=1, got 0x%06X valid=%b",
                     test_num, expected, m_tdata, m_tvalid);
            fail_cnt = fail_cnt + 1;
        end
    end
endtask

task axi_write;
    input [3:0] addr;
    input [31:0] data;
    integer cycles;
    integer aw_done;
    integer w_done;
    integer b_done;
    begin
        aw_done = 0;
        w_done = 0;
        b_done = 0;

        @(posedge AxiLiteClk); #1;
        awaddr = addr;
        wdata = data;
        awvalid = 1'b1;
        wvalid = 1'b1;
        bready = 1'b0;

        for (cycles = 0; cycles < 32 && !(aw_done && w_done); cycles = cycles + 1) begin
            @(posedge AxiLiteClk); #1;
            if (!aw_done && awready) begin
                awvalid = 1'b0;
                aw_done = 1;
            end
            if (!w_done && wready) begin
                wvalid = 1'b0;
                w_done = 1;
            end
        end

        if (!(aw_done && w_done)) begin
            $display("FAIL AXI write: addr=0x%X data=0x%08X aw_done=%0d w_done=%0d",
                     addr, data, aw_done, w_done);
            fail_cnt = fail_cnt + 1;
            awvalid = 1'b0;
            wvalid = 1'b0;
            bready = 1'b0;
        end else begin
            for (cycles = 0; cycles < 32 && !b_done; cycles = cycles + 1) begin
                @(posedge AxiLiteClk); #1;
                if (bvalid) begin
                    b_done = 1;
                end
            end

            if (!b_done) begin
                $display("FAIL AXI write: timeout waiting for BVALID addr=0x%X data=0x%08X",
                         addr, data);
                fail_cnt = fail_cnt + 1;
            end

            bready = 1'b1;
            @(posedge AxiLiteClk); #1;
            bready = 1'b0;
        end
        repeat (3) @(posedge StreamClk);
    end
endtask

initial begin
    repeat (4) @(posedge StreamClk);
    sStreamReset_n = 1'b1;
    aAxiLiteReset_n = 1'b1;
    repeat (4) @(posedge StreamClk);

    s_tdata = 24'hAA55CC; s_tvalid = 1'b1; s_tuser = 1'b1; s_tlast = 1'b0;
    @(posedge StreamClk); #1;
    check_pixel(24'hAA55CC, 8'd1);

    axi_write(4'h0, 32'd1);
    s_tdata = 24'hFF0000; s_tvalid = 1'b1; s_tuser = 1'b0; s_tlast = 1'b0;
    @(posedge StreamClk); #1;
    check_pixel(24'h4C4C4C, 8'd2);

    s_tdata = 24'h0000FF;
    @(posedge StreamClk); #1;
    check_pixel(24'h959595, 8'd3);

    s_tdata = 24'h00FF00;
    @(posedge StreamClk); #1;
    check_pixel(24'h1C1C1C, 8'd4);

    axi_write(4'h0, 32'd2);
    s_tdata = 24'h808080;
    @(posedge StreamClk); #1;
    check_pixel(24'hFFFFFF, 8'd5);

    s_tdata = 24'h7F7F7F;
    @(posedge StreamClk); #1;
    check_pixel(24'h000000, 8'd6);

    s_tdata = 24'h818181;
    @(posedge StreamClk); #1;
    check_pixel(24'hFFFFFF, 8'd7);

    s_tdata = 24'hFF0000;
    @(posedge StreamClk); #1;
    check_pixel(24'h000000, 8'd8);

    axi_write(4'h0, 32'd3);
    s_tdata = 24'h123456; s_tuser = 1'b1; s_tlast = 1'b1;
    @(posedge StreamClk); #1;
    check_pixel(24'h123456, 8'd9);

    if (m_tuser === 1'b1 && m_tlast === 1'b1) begin
        $display("PASS Test 10: tuser/tlast pass-through");
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("FAIL Test 10: tuser=%b tlast=%b", m_tuser, m_tlast);
        fail_cnt = fail_cnt + 1;
    end

    s_tvalid = 1'b0; s_tuser = 1'b0; s_tlast = 1'b0;
    @(posedge StreamClk); #1;
    if (m_tvalid === 1'b0) begin
        $display("PASS Test 11: invalid propagated");
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("FAIL Test 11: expected m_tvalid=0, got %b", m_tvalid);
        fail_cnt = fail_cnt + 1;
    end

    axi_write(4'h0, 32'd0);
    m_tready = 1'b1;
    s_tdata = 24'hABCDEF; s_tvalid = 1'b1;
    @(posedge StreamClk); #1;
    m_tready = 1'b0;
    s_tdata = 24'h000000;
    @(posedge StreamClk); #1;
    if (m_tdata === 24'hABCDEF) begin
        $display("PASS Test 12: backpressure holds output");
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("FAIL Test 12: expected held 0xABCDEF, got 0x%06X", m_tdata);
        fail_cnt = fail_cnt + 1;
    end
    if (s_tready === 1'b0) begin
        $display("PASS Test 13: backpressure deasserts upstream ready");
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("FAIL Test 13: expected s_tready=0, got %b", s_tready);
        fail_cnt = fail_cnt + 1;
    end
    m_tready = 1'b1;
    #1;
    if (s_tready === 1'b1) begin
        $display("PASS Test 14: upstream ready returns");
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("FAIL Test 14: expected s_tready=1, got %b", s_tready);
        fail_cnt = fail_cnt + 1;
    end

    awaddr = 4'h0; wdata = 32'd1; wstrb = 4'hF;
    awvalid = 1'b1; wvalid = 1'b1; bready = 1'b1;
    handshake_cnt = 0;
    @(posedge AxiLiteClk);
    if (bvalid && bready) handshake_cnt = handshake_cnt + 1;
    #1;
    awvalid = 1'b0; wvalid = 1'b0;
    @(posedge AxiLiteClk);
    if (bvalid && bready) handshake_cnt = handshake_cnt + 1;
    #1;
    @(posedge AxiLiteClk);
    if (bvalid && bready) handshake_cnt = handshake_cnt + 1;
    #1;
    if (handshake_cnt == 1 && bvalid === 1'b0) begin
        $display("PASS Test 15: write response clears after one B handshake");
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("FAIL Test 15: expected one B handshake and BVALID clear, count=%0d bvalid=%b",
                 handshake_cnt, bvalid);
        fail_cnt = fail_cnt + 1;
    end
    bready = 1'b0;

    araddr = 4'h0; arvalid = 1'b1; rready = 1'b1;
    handshake_cnt = 0;
    @(posedge AxiLiteClk);
    if (rvalid && rready) handshake_cnt = handshake_cnt + 1;
    #1;
    arvalid = 1'b0;
    @(posedge AxiLiteClk);
    if (rvalid && rready) handshake_cnt = handshake_cnt + 1;
    #1;
    @(posedge AxiLiteClk);
    if (rvalid && rready) handshake_cnt = handshake_cnt + 1;
    #1;
    if (handshake_cnt == 1 && rvalid === 1'b0) begin
        $display("PASS Test 16: read response clears after one R handshake");
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("FAIL Test 16: expected one R handshake and RVALID clear, count=%0d rvalid=%b",
                 handshake_cnt, rvalid);
        fail_cnt = fail_cnt + 1;
    end
    for (test_cycles = 0; test_cycles < 4 && rvalid; test_cycles = test_cycles + 1) begin
        @(posedge AxiLiteClk); #1;
    end
    rready = 1'b0;

    axi_write(4'h0, 32'd3);
    araddr = 4'h0; arvalid = 1'b1; rready = 1'b0;
    @(posedge AxiLiteClk); #1;
    arvalid = 1'b0;
    if (rvalid !== 1'b1) begin
        @(posedge AxiLiteClk); #1;
    end
    araddr = 4'h4; arvalid = 1'b1;
    #1;
    if (arready === 1'b0) begin
        $display("PASS Test 17: outstanding read response blocks new AR");
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("FAIL Test 17: ARREADY asserted while RVALID outstanding and RREADY low");
        fail_cnt = fail_cnt + 1;
    end
    @(posedge AxiLiteClk); #1;
    arvalid = 1'b0; rready = 1'b1;
    @(posedge AxiLiteClk); #1;
    rready = 1'b0;

    $display("=== Results: %0d PASS, %0d FAIL ===", pass_cnt, fail_cnt);
    if (fail_cnt > 0) $display("SIMULATION FAILED");
    else              $display("SIMULATION PASSED");
    $finish;
end

endmodule
