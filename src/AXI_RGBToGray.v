`timescale 1ns / 1ps

module AXI_RGBToGray (
    input  wire        StreamClk,
    input  wire        sStreamReset_n,

    // Slave AXI-Stream（來自 AXI_GammaCorrection）
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

// tdata bit layout（由 BayerToRGB→GammaCorrection 原始碼確認）:
//   [23:16] = R,  [15:8] = B,  [7:0] = G
wire [7:0] R = s_axis_video_tdata[23:16];
wire [7:0] B = s_axis_video_tdata[15:8];
wire [7:0] G = s_axis_video_tdata[7:0];

// BT.601 定點近似：Y = (77*R + 150*G + 29*B) >> 8
// 係數總和 = 256，最大值 = 256*255 = 65280，16-bit 足夠
wire [15:0] prod_R = {8'b0, R} * 16'd77;
wire [15:0] prod_G = {8'b0, G} * 16'd150;
wire [15:0] prod_B = {8'b0, B} * 16'd29;
wire [15:0] Y_full = prod_R + prod_G + prod_B;
wire [7:0]  Y      = Y_full[15:8];  // 等效 >> 8

// 1-cycle 管線暫存器
// 當 tready=0 時保持輸出（下游背壓）
always @(posedge StreamClk) begin
    if (!sStreamReset_n) begin
        m_axis_video_tdata  <= 24'd0;
        m_axis_video_tvalid <= 1'b0;
        m_axis_video_tuser  <= 1'b0;
        m_axis_video_tlast  <= 1'b0;
    end else if (m_axis_video_tready) begin
        m_axis_video_tdata  <= {Y, Y, Y};
        m_axis_video_tvalid <= s_axis_video_tvalid;
        m_axis_video_tuser  <= s_axis_video_tuser;
        m_axis_video_tlast  <= s_axis_video_tlast;
    end
end

endmodule
