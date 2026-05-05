`timescale 1ns / 1ps

module AXI_Binarize #(
    parameter [7:0] THRESHOLD = 8'd128
) (
    input  wire        StreamClk,
    input  wire        sStreamReset_n,

    // Slave AXI-Stream（來自 AXI_RGBToGray，tdata = {Y, Y, Y}）
    output wire        s_axis_video_tready,
    input  wire [23:0] s_axis_video_tdata,
    input  wire        s_axis_video_tvalid,
    input  wire        s_axis_video_tuser,
    input  wire        s_axis_video_tlast,

    // Master AXI-Stream（送往 AXI VDMA S2MM）
    input  wire        m_axis_video_tready,
    output reg  [23:0] m_axis_video_tdata,
    output reg         m_axis_video_tvalid,
    output reg         m_axis_video_tuser,
    output reg         m_axis_video_tlast
);

// 下游背壓直接往上透傳
assign s_axis_video_tready = m_axis_video_tready;

// 上游已是 {Y, Y, Y}，三個 byte 相同，取最低位 byte 最便宜
wire [7:0]  Y         = s_axis_video_tdata[7:0];
wire        bin       = (Y >= THRESHOLD);
wire [23:0] pixel_out = bin ? 24'hFFFFFF : 24'h000000;

// 1-cycle 管線暫存器；tready=0 時保持輸出
always @(posedge StreamClk) begin
    if (!sStreamReset_n) begin
        m_axis_video_tdata  <= 24'd0;
        m_axis_video_tvalid <= 1'b0;
        m_axis_video_tuser  <= 1'b0;
        m_axis_video_tlast  <= 1'b0;
    end else if (m_axis_video_tready) begin
        m_axis_video_tdata  <= pixel_out;
        m_axis_video_tvalid <= s_axis_video_tvalid;
        m_axis_video_tuser  <= s_axis_video_tuser;
        m_axis_video_tlast  <= s_axis_video_tlast;
    end
end

endmodule
