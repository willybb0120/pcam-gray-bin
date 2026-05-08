`timescale 1ns / 1ps

module AXI_ImageModeSelect #(
    parameter [7:0] THRESHOLD = 8'd128
) (
    input wire StreamClk,
    input wire sStreamReset_n,
    input wire AxiLiteClk,
    input wire aAxiLiteReset_n,
    output wire s_axis_video_tready,
    input wire [23:0] s_axis_video_tdata,
    input wire s_axis_video_tvalid,
    input wire s_axis_video_tuser,
    input wire s_axis_video_tlast,
    input wire m_axis_video_tready,
    output reg [23:0] m_axis_video_tdata,
    output reg m_axis_video_tvalid,
    output reg m_axis_video_tuser,
    output reg m_axis_video_tlast,
    input wire [3:0] s_axi_awaddr,
    input wire s_axi_awvalid,
    output wire s_axi_awready,
    input wire [31:0] s_axi_wdata,
    input wire [3:0] s_axi_wstrb,
    input wire s_axi_wvalid,
    output wire s_axi_wready,
    output wire [1:0] s_axi_bresp,
    output reg s_axi_bvalid,
    input wire s_axi_bready,
    input wire [3:0] s_axi_araddr,
    input wire s_axi_arvalid,
    output wire s_axi_arready,
    output reg [31:0] s_axi_rdata,
    output wire [1:0] s_axi_rresp,
    output reg s_axi_rvalid,
    input wire s_axi_rready
);

assign s_axis_video_tready = m_axis_video_tready;

wire [7:0] R = s_axis_video_tdata[23:16];
wire [7:0] B = s_axis_video_tdata[15:8];
wire [7:0] G = s_axis_video_tdata[7:0];

wire [15:0] prod_R = {8'b0, R} * 16'd77;
wire [15:0] prod_G = {8'b0, G} * 16'd150;
wire [15:0] prod_B = {8'b0, B} * 16'd29;
wire [15:0] Y_full = prod_R + prod_G + prod_B;
wire [7:0]  Y      = Y_full[15:8];

wire [23:0] gray_pixel = {Y, Y, Y};
wire [23:0] bin_pixel  = (Y >= THRESHOLD) ? 24'hFFFFFF : 24'h000000;

reg [1:0] mode_reg = 2'b00;
reg [1:0] mode_meta = 2'b00;
reg [1:0] mode_sync = 2'b00;

always @(posedge StreamClk) begin
    if (!sStreamReset_n) begin
        mode_meta <= 2'b00;
        mode_sync <= 2'b00;
    end else begin
        mode_meta <= mode_reg;
        mode_sync <= mode_meta;
    end
end

reg [23:0] selected_pixel;

always @(*) begin
    case (mode_sync)
        2'd1: selected_pixel = gray_pixel;
        2'd2: selected_pixel = bin_pixel;
        default: selected_pixel = s_axis_video_tdata;
    endcase
end

always @(posedge StreamClk) begin
    if (!sStreamReset_n) begin
        m_axis_video_tdata  <= 24'd0;
        m_axis_video_tvalid <= 1'b0;
        m_axis_video_tuser  <= 1'b0;
        m_axis_video_tlast  <= 1'b0;
    end else if (m_axis_video_tready) begin
        m_axis_video_tdata  <= selected_pixel;
        m_axis_video_tvalid <= s_axis_video_tvalid;
        m_axis_video_tuser  <= s_axis_video_tuser;
        m_axis_video_tlast  <= s_axis_video_tlast;
    end
end

reg [3:0]  awaddr_reg = 4'd0;
reg        aw_holding = 1'b0;
reg [31:0] wdata_reg = 32'd0;
reg [3:0]  wstrb_reg = 4'd0;
reg        w_holding = 1'b0;

assign s_axi_awready = !aw_holding;
assign s_axi_wready  = !w_holding;
assign s_axi_bresp   = 2'b00;

wire aw_accept = s_axi_awvalid && s_axi_awready;
wire w_accept  = s_axi_wvalid && s_axi_wready;
wire have_aw   = aw_holding || aw_accept;
wire have_w    = w_holding || w_accept;
wire [3:0]  write_addr  = aw_holding ? awaddr_reg : s_axi_awaddr;
wire [31:0] write_data  = w_holding ? wdata_reg : s_axi_wdata;
wire [3:0]  write_strb  = w_holding ? wstrb_reg : s_axi_wstrb;

always @(posedge AxiLiteClk) begin
    if (!aAxiLiteReset_n) begin
        mode_reg     <= 2'b00;
        awaddr_reg   <= 4'd0;
        aw_holding   <= 1'b0;
        wdata_reg    <= 32'd0;
        wstrb_reg    <= 4'd0;
        w_holding    <= 1'b0;
        s_axi_bvalid <= 1'b0;
    end else begin
        if (s_axi_bvalid && s_axi_bready) begin
            s_axi_bvalid <= 1'b0;
        end

        if (aw_accept) begin
            awaddr_reg <= s_axi_awaddr;
            aw_holding <= 1'b1;
        end

        if (w_accept) begin
            wdata_reg <= s_axi_wdata;
            wstrb_reg <= s_axi_wstrb;
            w_holding <= 1'b1;
        end

        if (!s_axi_bvalid && have_aw && have_w) begin
            if (write_addr == 4'h0 && write_strb[0]) begin
                mode_reg <= write_data[1:0];
            end
            aw_holding   <= 1'b0;
            w_holding    <= 1'b0;
            s_axi_bvalid <= 1'b1;
        end
    end
end

assign s_axi_arready = !s_axi_rvalid;
assign s_axi_rresp   = 2'b00;

always @(posedge AxiLiteClk) begin
    if (!aAxiLiteReset_n) begin
        s_axi_rdata  <= 32'd0;
        s_axi_rvalid <= 1'b0;
    end else begin
        if (s_axi_rvalid && s_axi_rready) begin
            s_axi_rvalid <= 1'b0;
        end

        if (s_axi_arvalid && s_axi_arready) begin
            if (s_axi_araddr == 4'h0) begin
                s_axi_rdata <= {30'd0, mode_reg};
            end else begin
                s_axi_rdata <= 32'd0;
            end
            s_axi_rvalid <= 1'b1;
        end
    end
end

endmodule
