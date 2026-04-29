# AXI_RGBToGray IP 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Zybo Z7-20 PCAM pipeline 的 GammaCorrection 與 VDMA 之間插入 AXI_RGBToGray 自訂 IP，使 HDMI 輸出為 BT.601 灰階影像。

**Architecture:** 單一 Verilog 模組，1-cycle 管線暫存器，BT.601 定點近似（`Y = (77R + 150G + 29B) >> 8`），輸入輸出皆為 24-bit AXI-Stream（R-B-G 排列）。

**Tech Stack:** Verilog, Vivado 2025.2 IP Packaging, Vivado xsim simulator, Vitis 2025.2

---

## 檔案清單

| 動作 | 路徑（相對於 vivado_workspace 所在根目錄） |
|------|------------------------------------------|
| 建立 | `vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_RGBToGray/hdl/AXI_RGBToGray.v` |
| 建立 | `vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_RGBToGray/tb/tb_AXI_RGBToGray.v` |
| 建立 | `vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_RGBToGray/xgui/AXI_RGBToGray_v1_0.tcl` |
| 建立 | `vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_RGBToGray/component.xml` |
| 不動 | `vitis_workspace/...` （Phase 1 Vitis 端無需修改） |

> 所有路徑中「根目錄」= 你的 Vivado 專案路徑，依照 porting notes，通常是 `C:\pcam\`。
> 以下步驟中的 `<ROOT>` 請替換為實際路徑，例如 `C:\pcam\`。

---

## Task 1：建立 IP 目錄結構與 Testbench

**Files:**
- Create: `<ROOT>/vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_RGBToGray/tb/tb_AXI_RGBToGray.v`

- [ ] **Step 1: 建立目錄結構**

```
mkdir <ROOT>\vivado_workspace\Zybo-Z7-20-pcam-5c.ipdefs\repo_0\local\ip\AXI_RGBToGray\hdl
mkdir <ROOT>\vivado_workspace\Zybo-Z7-20-pcam-5c.ipdefs\repo_0\local\ip\AXI_RGBToGray\tb
mkdir <ROOT>\vivado_workspace\Zybo-Z7-20-pcam-5c.ipdefs\repo_0\local\ip\AXI_RGBToGray\xgui
```

- [ ] **Step 2: 建立 Testbench**

在 `tb/tb_AXI_RGBToGray.v` 寫入以下內容：

```verilog
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
```

- [ ] **Step 3: Commit testbench**

```bash
git add vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_RGBToGray/tb/tb_AXI_RGBToGray.v
git commit -m "test: add AXI_RGBToGray BT.601 testbench"
```

---

## Task 2：撰寫 RTL — AXI_RGBToGray.v

**Files:**
- Create: `<ROOT>/vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_RGBToGray/hdl/AXI_RGBToGray.v`

- [ ] **Step 1: 建立 RTL 檔**

在 `hdl/AXI_RGBToGray.v` 寫入以下內容：

```verilog
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
```

- [ ] **Step 2: Commit RTL**

```bash
git add vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_RGBToGray/hdl/AXI_RGBToGray.v
git commit -m "feat: add AXI_RGBToGray BT.601 RTL"
```

---

## Task 3：在 Vivado 執行 Simulation

**目的：** 在燒入硬體之前，用 xsim 驗證 RTL 邏輯正確。

- [ ] **Step 1: 在 Vivado Tcl Console 加入模擬來源**

開啟 Vivado，進入 Tcl Console（View → Tcl Console），執行：

```tcl
# 加入 RTL 到模擬來源
add_files -fileset sim_1 -norecurse \
    {C:/pcam/vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_RGBToGray/hdl/AXI_RGBToGray.v}

# 加入 Testbench
add_files -fileset sim_1 -norecurse \
    {C:/pcam/vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_RGBToGray/tb/tb_AXI_RGBToGray.v}

# 設定 testbench 為模擬頂層
set_property top tb_AXI_RGBToGray [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]
```

- [ ] **Step 2: 執行模擬**

```tcl
launch_simulation
run all
```

- [ ] **Step 3: 確認輸出**

在 Tcl Console 或 Simulation log 中確認以下輸出：

```
PASS Test 1: Y=0x00 (0)
PASS Test 2: Y=0xFF (255)
PASS Test 3: Y=0x4C (76)
PASS Test 4: Y=0x95 (149)
PASS Test 5: Y=0x1C (28)
PASS Test 6: tuser/tlast pass-through
PASS Test 7: tvalid=0 propagated
PASS Test 8: Y=0xB4 (180)
PASS Test 9: backpressure holds output at Y=0xB4
=== Results: 9 PASS, 0 FAIL ===
SIMULATION PASSED
```

若有 FAIL，依照錯誤訊息回到 Task 2 修正 RTL，再重新執行 `relaunch_sim; run all`。

---

## Task 4：建立 IP 打包檔案（component.xml + xgui TCL）

**Files:**
- Create: `<ROOT>/vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_RGBToGray/xgui/AXI_RGBToGray_v1_0.tcl`
- Create: `<ROOT>/vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_RGBToGray/component.xml`

- [ ] **Step 1: 建立 xgui TCL**

在 `xgui/AXI_RGBToGray_v1_0.tcl` 寫入：

```tcl
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
}
```

- [ ] **Step 2: 建立 component.xml**

在 `component.xml` 寫入（這是讓 Vivado IP Catalog 識別此 IP 的描述檔）：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<spirit:component
  xmlns:xilinx="http://www.xilinx.com"
  xmlns:spirit="http://www.spiritconsortium.org/XMLSchema/SPIRIT/1685-2009"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">

  <spirit:vendor>user</spirit:vendor>
  <spirit:library>user</spirit:library>
  <spirit:name>AXI_RGBToGray</spirit:name>
  <spirit:version>1.0</spirit:version>

  <spirit:busInterfaces>
    <spirit:busInterface>
      <spirit:name>AXI_Stream_Clk</spirit:name>
      <spirit:busType spirit:vendor="xilinx.com" spirit:library="signal" spirit:name="clock" spirit:version="1.0"/>
      <spirit:abstractionType spirit:vendor="xilinx.com" spirit:library="signal" spirit:name="clock_rtl" spirit:version="1.0"/>
      <spirit:slave/>
      <spirit:portMaps>
        <spirit:portMap>
          <spirit:logicalPort><spirit:name>CLK</spirit:name></spirit:logicalPort>
          <spirit:physicalPort><spirit:name>StreamClk</spirit:name></spirit:physicalPort>
        </spirit:portMap>
      </spirit:portMaps>
      <spirit:parameters>
        <spirit:parameter>
          <spirit:name>ASSOCIATED_BUSIF</spirit:name>
          <spirit:value spirit:id="BUSIFPARAM_VALUE.AXI_STREAM_CLK.ASSOCIATED_BUSIF">s_axis_video:m_axis_video</spirit:value>
        </spirit:parameter>
        <spirit:parameter>
          <spirit:name>ASSOCIATED_RESET</spirit:name>
          <spirit:value spirit:id="BUSIFPARAM_VALUE.AXI_STREAM_CLK.ASSOCIATED_RESET">sStreamReset_n</spirit:value>
        </spirit:parameter>
      </spirit:parameters>
    </spirit:busInterface>

    <spirit:busInterface>
      <spirit:name>AXI_Stream_Reset_n</spirit:name>
      <spirit:busType spirit:vendor="xilinx.com" spirit:library="signal" spirit:name="reset" spirit:version="1.0"/>
      <spirit:abstractionType spirit:vendor="xilinx.com" spirit:library="signal" spirit:name="reset_rtl" spirit:version="1.0"/>
      <spirit:slave/>
      <spirit:portMaps>
        <spirit:portMap>
          <spirit:logicalPort><spirit:name>RST</spirit:name></spirit:logicalPort>
          <spirit:physicalPort><spirit:name>sStreamReset_n</spirit:name></spirit:physicalPort>
        </spirit:portMap>
      </spirit:portMaps>
    </spirit:busInterface>

    <spirit:busInterface>
      <spirit:name>s_axis_video</spirit:name>
      <spirit:busType spirit:vendor="xilinx.com" spirit:library="interface" spirit:name="axis" spirit:version="1.0"/>
      <spirit:abstractionType spirit:vendor="xilinx.com" spirit:library="interface" spirit:name="axis_rtl" spirit:version="1.0"/>
      <spirit:slave/>
      <spirit:portMaps>
        <spirit:portMap>
          <spirit:logicalPort><spirit:name>TDATA</spirit:name></spirit:logicalPort>
          <spirit:physicalPort><spirit:name>s_axis_video_tdata</spirit:name></spirit:physicalPort>
        </spirit:portMap>
        <spirit:portMap>
          <spirit:logicalPort><spirit:name>TVALID</spirit:name></spirit:logicalPort>
          <spirit:physicalPort><spirit:name>s_axis_video_tvalid</spirit:name></spirit:physicalPort>
        </spirit:portMap>
        <spirit:portMap>
          <spirit:logicalPort><spirit:name>TREADY</spirit:name></spirit:logicalPort>
          <spirit:physicalPort><spirit:name>s_axis_video_tready</spirit:name></spirit:physicalPort>
        </spirit:portMap>
        <spirit:portMap>
          <spirit:logicalPort><spirit:name>TUSER</spirit:name></spirit:logicalPort>
          <spirit:physicalPort><spirit:name>s_axis_video_tuser</spirit:name></spirit:physicalPort>
        </spirit:portMap>
        <spirit:portMap>
          <spirit:logicalPort><spirit:name>TLAST</spirit:name></spirit:logicalPort>
          <spirit:physicalPort><spirit:name>s_axis_video_tlast</spirit:name></spirit:physicalPort>
        </spirit:portMap>
      </spirit:portMaps>
    </spirit:busInterface>

    <spirit:busInterface>
      <spirit:name>m_axis_video</spirit:name>
      <spirit:busType spirit:vendor="xilinx.com" spirit:library="interface" spirit:name="axis" spirit:version="1.0"/>
      <spirit:abstractionType spirit:vendor="xilinx.com" spirit:library="interface" spirit:name="axis_rtl" spirit:version="1.0"/>
      <spirit:master/>
      <spirit:portMaps>
        <spirit:portMap>
          <spirit:logicalPort><spirit:name>TDATA</spirit:name></spirit:logicalPort>
          <spirit:physicalPort><spirit:name>m_axis_video_tdata</spirit:name></spirit:physicalPort>
        </spirit:portMap>
        <spirit:portMap>
          <spirit:logicalPort><spirit:name>TVALID</spirit:name></spirit:logicalPort>
          <spirit:physicalPort><spirit:name>m_axis_video_tvalid</spirit:name></spirit:physicalPort>
        </spirit:portMap>
        <spirit:portMap>
          <spirit:logicalPort><spirit:name>TREADY</spirit:name></spirit:logicalPort>
          <spirit:physicalPort><spirit:name>m_axis_video_tready</spirit:name></spirit:physicalPort>
        </spirit:portMap>
        <spirit:portMap>
          <spirit:logicalPort><spirit:name>TUSER</spirit:name></spirit:logicalPort>
          <spirit:physicalPort><spirit:name>m_axis_video_tuser</spirit:name></spirit:physicalPort>
        </spirit:portMap>
        <spirit:portMap>
          <spirit:logicalPort><spirit:name>TLAST</spirit:name></spirit:logicalPort>
          <spirit:physicalPort><spirit:name>m_axis_video_tlast</spirit:name></spirit:physicalPort>
        </spirit:portMap>
      </spirit:portMaps>
    </spirit:busInterface>
  </spirit:busInterfaces>

  <spirit:model>
    <spirit:views>
      <spirit:view>
        <spirit:name>xilinx_anylanguagesynthesis</spirit:name>
        <spirit:envIdentifier>:vivado.xilinx.com:synthesis</spirit:envIdentifier>
        <spirit:language>Verilog</spirit:language>
        <spirit:modelName>AXI_RGBToGray</spirit:modelName>
        <spirit:fileSetRef>
          <spirit:localName>xilinx_anylanguagesynthesis_view_fileset</spirit:localName>
        </spirit:fileSetRef>
      </spirit:view>
      <spirit:view>
        <spirit:name>xilinx_anylanguagebehavioralsimulation</spirit:name>
        <spirit:envIdentifier>:vivado.xilinx.com:simulation</spirit:envIdentifier>
        <spirit:language>Verilog</spirit:language>
        <spirit:modelName>AXI_RGBToGray</spirit:modelName>
        <spirit:fileSetRef>
          <spirit:localName>xilinx_anylanguagebehavioralsimulation_view_fileset</spirit:localName>
        </spirit:fileSetRef>
      </spirit:view>
      <spirit:view>
        <spirit:name>xilinx_xpgui</spirit:name>
        <spirit:envIdentifier>xilinx_xpgui</spirit:envIdentifier>
        <spirit:fileSetRef>
          <spirit:localName>xilinx_xpgui_view_fileset</spirit:localName>
        </spirit:fileSetRef>
      </spirit:view>
    </spirit:views>
    <spirit:ports>
      <spirit:port>
        <spirit:name>StreamClk</spirit:name>
        <spirit:wire>
          <spirit:direction>in</spirit:direction>
          <spirit:wireTypeDefs><spirit:wireTypeDef>
            <spirit:typeName>STD_LOGIC</spirit:typeName>
            <spirit:viewNameRef>xilinx_anylanguagesynthesis</spirit:viewNameRef>
            <spirit:viewNameRef>xilinx_anylanguagebehavioralsimulation</spirit:viewNameRef>
          </spirit:wireTypeDef></spirit:wireTypeDefs>
        </spirit:wire>
      </spirit:port>
      <spirit:port>
        <spirit:name>sStreamReset_n</spirit:name>
        <spirit:wire>
          <spirit:direction>in</spirit:direction>
          <spirit:wireTypeDefs><spirit:wireTypeDef>
            <spirit:typeName>STD_LOGIC</spirit:typeName>
            <spirit:viewNameRef>xilinx_anylanguagesynthesis</spirit:viewNameRef>
            <spirit:viewNameRef>xilinx_anylanguagebehavioralsimulation</spirit:viewNameRef>
          </spirit:wireTypeDef></spirit:wireTypeDefs>
        </spirit:wire>
      </spirit:port>
      <spirit:port>
        <spirit:name>s_axis_video_tready</spirit:name>
        <spirit:wire>
          <spirit:direction>out</spirit:direction>
          <spirit:wireTypeDefs><spirit:wireTypeDef>
            <spirit:typeName>STD_LOGIC</spirit:typeName>
            <spirit:viewNameRef>xilinx_anylanguagesynthesis</spirit:viewNameRef>
            <spirit:viewNameRef>xilinx_anylanguagebehavioralsimulation</spirit:viewNameRef>
          </spirit:wireTypeDef></spirit:wireTypeDefs>
        </spirit:wire>
      </spirit:port>
      <spirit:port>
        <spirit:name>s_axis_video_tdata</spirit:name>
        <spirit:wire>
          <spirit:direction>in</spirit:direction>
          <spirit:vector>
            <spirit:left spirit:format="long">23</spirit:left>
            <spirit:right spirit:format="long">0</spirit:right>
          </spirit:vector>
          <spirit:wireTypeDefs><spirit:wireTypeDef>
            <spirit:typeName>STD_LOGIC_VECTOR</spirit:typeName>
            <spirit:viewNameRef>xilinx_anylanguagesynthesis</spirit:viewNameRef>
            <spirit:viewNameRef>xilinx_anylanguagebehavioralsimulation</spirit:viewNameRef>
          </spirit:wireTypeDef></spirit:wireTypeDefs>
        </spirit:wire>
      </spirit:port>
      <spirit:port>
        <spirit:name>s_axis_video_tvalid</spirit:name>
        <spirit:wire>
          <spirit:direction>in</spirit:direction>
          <spirit:wireTypeDefs><spirit:wireTypeDef>
            <spirit:typeName>STD_LOGIC</spirit:typeName>
            <spirit:viewNameRef>xilinx_anylanguagesynthesis</spirit:viewNameRef>
            <spirit:viewNameRef>xilinx_anylanguagebehavioralsimulation</spirit:viewNameRef>
          </spirit:wireTypeDef></spirit:wireTypeDefs>
        </spirit:wire>
      </spirit:port>
      <spirit:port>
        <spirit:name>s_axis_video_tuser</spirit:name>
        <spirit:wire>
          <spirit:direction>in</spirit:direction>
          <spirit:wireTypeDefs><spirit:wireTypeDef>
            <spirit:typeName>STD_LOGIC</spirit:typeName>
            <spirit:viewNameRef>xilinx_anylanguagesynthesis</spirit:viewNameRef>
            <spirit:viewNameRef>xilinx_anylanguagebehavioralsimulation</spirit:viewNameRef>
          </spirit:wireTypeDef></spirit:wireTypeDefs>
        </spirit:wire>
      </spirit:port>
      <spirit:port>
        <spirit:name>s_axis_video_tlast</spirit:name>
        <spirit:wire>
          <spirit:direction>in</spirit:direction>
          <spirit:wireTypeDefs><spirit:wireTypeDef>
            <spirit:typeName>STD_LOGIC</spirit:typeName>
            <spirit:viewNameRef>xilinx_anylanguagesynthesis</spirit:viewNameRef>
            <spirit:viewNameRef>xilinx_anylanguagebehavioralsimulation</spirit:viewNameRef>
          </spirit:wireTypeDef></spirit:wireTypeDefs>
        </spirit:wire>
      </spirit:port>
      <spirit:port>
        <spirit:name>m_axis_video_tready</spirit:name>
        <spirit:wire>
          <spirit:direction>in</spirit:direction>
          <spirit:wireTypeDefs><spirit:wireTypeDef>
            <spirit:typeName>STD_LOGIC</spirit:typeName>
            <spirit:viewNameRef>xilinx_anylanguagesynthesis</spirit:viewNameRef>
            <spirit:viewNameRef>xilinx_anylanguagebehavioralsimulation</spirit:viewNameRef>
          </spirit:wireTypeDef></spirit:wireTypeDefs>
        </spirit:wire>
      </spirit:port>
      <spirit:port>
        <spirit:name>m_axis_video_tdata</spirit:name>
        <spirit:wire>
          <spirit:direction>out</spirit:direction>
          <spirit:vector>
            <spirit:left spirit:format="long">23</spirit:left>
            <spirit:right spirit:format="long">0</spirit:right>
          </spirit:vector>
          <spirit:wireTypeDefs><spirit:wireTypeDef>
            <spirit:typeName>STD_LOGIC_VECTOR</spirit:typeName>
            <spirit:viewNameRef>xilinx_anylanguagesynthesis</spirit:viewNameRef>
            <spirit:viewNameRef>xilinx_anylanguagebehavioralsimulation</spirit:viewNameRef>
          </spirit:wireTypeDef></spirit:wireTypeDefs>
        </spirit:wire>
      </spirit:port>
      <spirit:port>
        <spirit:name>m_axis_video_tvalid</spirit:name>
        <spirit:wire>
          <spirit:direction>out</spirit:direction>
          <spirit:wireTypeDefs><spirit:wireTypeDef>
            <spirit:typeName>STD_LOGIC</spirit:typeName>
            <spirit:viewNameRef>xilinx_anylanguagesynthesis</spirit:viewNameRef>
            <spirit:viewNameRef>xilinx_anylanguagebehavioralsimulation</spirit:viewNameRef>
          </spirit:wireTypeDef></spirit:wireTypeDefs>
        </spirit:wire>
      </spirit:port>
      <spirit:port>
        <spirit:name>m_axis_video_tuser</spirit:name>
        <spirit:wire>
          <spirit:direction>out</spirit:direction>
          <spirit:wireTypeDefs><spirit:wireTypeDef>
            <spirit:typeName>STD_LOGIC</spirit:typeName>
            <spirit:viewNameRef>xilinx_anylanguagesynthesis</spirit:viewNameRef>
            <spirit:viewNameRef>xilinx_anylanguagebehavioralsimulation</spirit:viewNameRef>
          </spirit:wireTypeDef></spirit:wireTypeDefs>
        </spirit:wire>
      </spirit:port>
      <spirit:port>
        <spirit:name>m_axis_video_tlast</spirit:name>
        <spirit:wire>
          <spirit:direction>out</spirit:direction>
          <spirit:wireTypeDefs><spirit:wireTypeDef>
            <spirit:typeName>STD_LOGIC</spirit:typeName>
            <spirit:viewNameRef>xilinx_anylanguagesynthesis</spirit:viewNameRef>
            <spirit:viewNameRef>xilinx_anylanguagebehavioralsimulation</spirit:viewNameRef>
          </spirit:wireTypeDef></spirit:wireTypeDefs>
        </spirit:wire>
      </spirit:port>
    </spirit:ports>
  </spirit:model>

  <spirit:fileSets>
    <spirit:fileSet>
      <spirit:name>xilinx_anylanguagesynthesis_view_fileset</spirit:name>
      <spirit:file>
        <spirit:name>hdl/AXI_RGBToGray.v</spirit:name>
        <spirit:fileType>verilogSource</spirit:fileType>
      </spirit:file>
    </spirit:fileSet>
    <spirit:fileSet>
      <spirit:name>xilinx_anylanguagebehavioralsimulation_view_fileset</spirit:name>
      <spirit:file>
        <spirit:name>hdl/AXI_RGBToGray.v</spirit:name>
        <spirit:fileType>verilogSource</spirit:fileType>
      </spirit:file>
    </spirit:fileSet>
    <spirit:fileSet>
      <spirit:name>xilinx_xpgui_view_fileset</spirit:name>
      <spirit:file>
        <spirit:name>xgui/AXI_RGBToGray_v1_0.tcl</spirit:name>
        <spirit:fileType>tclSource</spirit:fileType>
        <spirit:userFileType>XGUI_VERSION_2</spirit:userFileType>
      </spirit:file>
    </spirit:fileSet>
  </spirit:fileSets>

  <spirit:description>AXI_RGBToGray_v1_0</spirit:description>

  <spirit:parameters>
    <spirit:parameter>
      <spirit:name>Component_Name</spirit:name>
      <spirit:value spirit:resolve="user" spirit:id="PARAM_VALUE.Component_Name" spirit:order="1">AXI_RGBToGray_v1_0</spirit:value>
    </spirit:parameter>
  </spirit:parameters>

  <spirit:vendorExtensions>
    <xilinx:coreExtensions>
      <xilinx:supportedFamilies>
        <xilinx:family xilinx:lifeCycle="Production">zynq</xilinx:family>
      </xilinx:supportedFamilies>
      <xilinx:taxonomies>
        <xilinx:taxonomy>/Video_&amp;_Image_Processing</xilinx:taxonomy>
      </xilinx:taxonomies>
      <xilinx:displayName>AXI_RGBToGray_v1_0</xilinx:displayName>
      <xilinx:definitionSource>package_project</xilinx:definitionSource>
      <xilinx:vendorDisplayName>User</xilinx:vendorDisplayName>
      <xilinx:coreRevision>1</xilinx:coreRevision>
    </xilinx:coreExtensions>
  </spirit:vendorExtensions>

</spirit:component>
```

- [ ] **Step 3: Commit 打包檔**

```bash
git add vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_RGBToGray/
git commit -m "feat: add AXI_RGBToGray IP packaging files"
```

---

## Task 5：在 Vivado Block Design 插入 IP

**目的：** 修改 `system.bd`，在 GammaCorrection 輸出與 VDMA 之間插入 AXI_RGBToGray。

- [ ] **Step 1: 刷新 IP Catalog（Vivado Tcl Console）**

```tcl
# 若 local/ip 目錄已在 IP repository list 中，只需 refresh
set_property ip_repo_paths \
    [list {C:/pcam/vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip}] \
    [current_project]
update_ip_catalog
```

確認 Tcl Console 出現：
```
INFO: Catalog Refresh Done.
```

- [ ] **Step 2: 在 Block Design 中加入 IP 實例**

在 Vivado Tcl Console 執行：

```tcl
# 開啟 Block Design
open_bd_design {C:/pcam/vivado_workspace/Zybo-Z7-20-pcam-5c.srcs/sources_1/bd/system/system.bd}

# 加入 AXI_RGBToGray 實例
create_bd_cell -type ip -vlnv user:user:AXI_RGBToGray:1.0 AXI_RGBToGray_0
```

- [ ] **Step 3: 斷開舊連線、接上新 IP**

在 Vivado Block Design GUI 執行（或用 Tcl）：

**GUI 操作：**
1. 在 Block Design 中找到 `AXI_GammaCorrection_0` 的 `m_axis_video` 輸出端
2. 右鍵 → **Delete Connection**，刪除通往 VDMA 的連線
3. 將 `AXI_GammaCorrection_0.m_axis_video` 連到 `AXI_RGBToGray_0.s_axis_video`
4. 將 `AXI_RGBToGray_0.m_axis_video` 連到原來 VDMA 的 `S_AXIS_S2MM`

**或用 Tcl：**

```tcl
# 先查詢目前 GammaCorrection 輸出的連線名稱
get_bd_intf_nets -of_objects [get_bd_intf_pins AXI_GammaCorrection_0/m_axis_video]
```

記下回傳的 net 名稱（例如 `AXI_GammaCorrection_0_m_axis_video`），然後：

```tcl
# 刪除舊連線
delete_bd_objs [get_bd_intf_nets AXI_GammaCorrection_0_m_axis_video]

# 接新連線
connect_bd_intf_net [get_bd_intf_pins AXI_GammaCorrection_0/m_axis_video] \
    [get_bd_intf_pins AXI_RGBToGray_0/s_axis_video]

connect_bd_intf_net [get_bd_intf_pins AXI_RGBToGray_0/m_axis_video] \
    [get_bd_intf_pins axi_vdma_0/S_AXIS_S2MM]
```

> **注意：** VDMA 的 S2MM slave 名稱可能是 `S_AXIS_S2MM` 或 `s_axis_s2mm`，執行前先用 `get_bd_intf_pins axi_vdma_0/*` 確認。

- [ ] **Step 4: 連接 Clock 與 Reset**

```tcl
# StreamClk：與 AXI_GammaCorrection_0 共用同一 clock source
# 先查詢 GammaCorrection 的 StreamClk 連線
get_bd_nets -of_objects [get_bd_pins AXI_GammaCorrection_0/StreamClk]
```

記下 clock net 名稱（例如 `StreamClk_1`），然後：

```tcl
connect_bd_net [get_bd_nets StreamClk_1] \
    [get_bd_pins AXI_RGBToGray_0/StreamClk]

# sStreamReset_n：同樣查詢 GammaCorrection 的 reset net
get_bd_nets -of_objects [get_bd_pins AXI_GammaCorrection_0/sStreamReset_n]
# 記下 net 名稱（例如 sStreamReset_n_1），然後：
connect_bd_net [get_bd_nets sStreamReset_n_1] \
    [get_bd_pins AXI_RGBToGray_0/sStreamReset_n]
```

- [ ] **Step 5: 儲存 Block Design 並驗證**

```tcl
save_bd_design
validate_bd_design
```

確認 Tcl Console 出現：
```
INFO: Validation was successful.
```

若出現 Warning 關於 TDATA width mismatch，檢查連線兩端的 TDATA 寬度是否都是 24-bit（3 bytes）。

---

## Task 6：Generate Bitstream 並 Export XSA

- [ ] **Step 1: 產生 Output Products**

```tcl
generate_target all [get_files \
    {C:/pcam/vivado_workspace/Zybo-Z7-20-pcam-5c.srcs/sources_1/bd/system/system.bd}]
```

- [ ] **Step 2: Generate Bitstream**

```tcl
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
```

預計耗時 5–15 分鐘。完成後確認：
```
INFO: write_bitstream completed successfully
```

> 若出現 Critical Warning 關於 Timing（WNS < 0），比對 porting_notes.md 第 3 節「坑 5」：MIPI D-PHY clock domain 的 timing violation 是已知問題，不影響功能，直接燒入測試。

- [ ] **Step 3: Export Hardware（含 Bitstream）**

```tcl
write_hw_platform -fixed -include_bit -force \
    {C:/pcam/vivado_workspace/system_wrapper.xsa}
```

確認 `C:\pcam\vivado_workspace\system_wrapper.xsa` 存在。

- [ ] **Step 4: Commit**

```bash
# 注意：.xsa 和 .bit 通常不進 git（binary 檔太大）
# 只 commit Block Design 的變更
git add vivado_workspace/Zybo-Z7-20-pcam-5c.srcs/sources_1/bd/system/system.bd
git commit -m "feat: insert AXI_RGBToGray into block design pipeline"
```

---

## Task 7：Vitis 更新 Platform 並燒入

**目的：** 用新的 XSA 更新 Vitis Platform，然後燒入驗證 HDMI 灰階輸出。

- [ ] **Step 1: 在 Vitis 更新 Platform**

1. 開啟 Vitis 2025.2，File → Switch Workspace → 選擇現有 vitis workspace（`C:\vitis_workspace\...`）
2. 在 Explorer 中找到 Platform 專案（例如 `platform_zyboz7`）
3. 右鍵 → **Update Hardware Specification** → 選擇新的 `system_wrapper.xsa`
4. 點選 Platform 專案右鍵 → **Build**

- [ ] **Step 2: Build Application**

在 Vitis 中 Application 專案右鍵 → **Build Project**

確認 Console 出現：
```
Build complete (0 errors, 0 warnings)
```

- [ ] **Step 3: 燒入並執行**

1. 接上 JTAG（micro-USB）、HDMI 螢幕、PCAM 5C
2. 確認 JP5 為 JTAG mode（或 SD card mode）
3. 右鍵 Application → **Run As → Launch Hardware**

- [ ] **Step 4: 驗證結果**

UART Console（baud rate 115200）確認 OV5640 init 成功：
```
OV5640 Chip ID: 0x5640  ← 表示 I2C 正常
```

HDMI 螢幕確認：
- 畫面顯示即時攝影機影像
- 影像為灰階（無彩色）
- 膚色、深色、亮色區域的明暗分佈自然（BT.601 加權，綠色環境亮，藍色環境暗）

---

## 故障排除速查

| 症狀 | 可能原因 | 解法 |
|------|----------|------|
| IP Catalog 找不到 AXI_RGBToGray | component.xml 路徑錯誤 | 確認 component.xml 在 `AXI_RGBToGray/` 根目錄，執行 `update_ip_catalog` |
| validate_bd_design TDATA 寬度警告 | AXIS 介面 TDATA bytes 不符 | 確認雙端 TDATA 都是 24-bit（TDATA_NUM_BYTES=3） |
| 畫面全黑或全白 | Reset 未連接或 tdata 全 0 | 在 ILA 或 Vivado Analyzer 抓 m_axis_video 波形 |
| 畫面有色彩（不是灰階） | IP 未插入 pipeline | 確認 system.bd 中 GammaCorrection.m_axis_video 連到 AXI_RGBToGray.s_axis_video |
| 模擬 Test 3 FAIL（Y 預期 76 但不同） | tdata bit ordering 錯誤 | 確認 R=[23:16], B=[15:8], G=[7:0] |
