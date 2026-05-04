# AXI_Binarize Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在現有 PCAM pipeline 中、`AXI_RGBToGray` 之後插入新 `AXI_Binarize` IP，將灰階影像依固定閾值（compile-time `parameter THRESHOLD`，預設 128）二值化後輸出至 HDMI。

**Architecture:** 純 stream-only 1-cycle pipeline IP。讀 `s_axis_video_tdata[7:0]` 為 Y（上游已輸出 `{Y,Y,Y}`），與 `THRESHOLD` 比較後輸出 `24'hFFFFFF`（白）或 `24'h000000`（黑）。介面完全鏡射 `AXI_RGBToGray`。

**Tech Stack:** Verilog 2001、iverilog/vvp（門 1 模擬）、Vivado 2025.2（門 2 合成）、Vitis 2025.2（門 3 板驗）、Zybo Z7-20 (xc7z020)、PCAM 5C。

**Spec:** `docs/superpowers/specs/2026-05-05-axi-binarize-design.md`

---

## File Structure

| 路徑 | 動作 | 用途 |
|------|------|------|
| `src/AXI_Binarize.v` | Create | RTL source of truth |
| `sim/tb_AXI_Binarize.v` | Create | iverilog testbench（含 parameter override DUT） |
| `vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_Binarize/hdl/AXI_Binarize.v` | Create (cp) | Vivado IP repo（cp 目標 1） |
| `vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_Binarize/component.xml` | Create (Vivado packager) | IP 元資料 |
| `vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_Binarize/xgui/AXI_Binarize_v1_0.tcl` | Create (Vivado packager) | GUI 參數定義 |
| Block Design `system.bd` | Modify (Vivado GUI) | 在 RGBToGray 與 VDMA 之間插入 Binarize |
| `vivado_workspace/system_wrapper.xsa` | Regenerate | Export Hardware 輸出 |

---

## Task 1: 建立 feature branch（強制規則檢查）

**Files:** 無檔案變更，純 git 操作。

- [ ] **Step 1: 確認當前不在 main**

```bash
cd /mnt/c/workspace-win/pcam-gray-bin
git branch --show-current
```

預期：顯示 `main`。**這就是停手點**。CLAUDE.md 強制規則 1：任何 `src/` 修改必須先離開 main。

- [ ] **Step 2: 建立並切換到 feature branch**

```bash
git checkout -b feat/axi-binarize
git branch --show-current
```

預期：顯示 `feat/axi-binarize`。

- [ ] **Step 3: 確認工作樹乾淨**

```bash
git status
```

預期：`nothing to commit, working tree clean`（spec 已 commit）。

---

## Task 2: TDD — 寫 testbench（測試先行，預期模擬無法編譯）

**Files:**
- Create: `sim/tb_AXI_Binarize.v`

- [ ] **Step 1: 寫 testbench 完整內容**

Create `sim/tb_AXI_Binarize.v`:

```verilog
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

    // Test 1: Y=0 → black
    s_tdata = 24'h000000; s_tvalid = 1'b1; s_tuser = 1'b1; s_tlast = 1'b0;
    @(posedge clk); #1;
    check_bin(24'h000000, 8'd1);

    // Test 2: Y=255 → white
    s_tdata = 24'hFFFFFF; s_tvalid = 1'b1; s_tuser = 1'b0;
    @(posedge clk); #1;
    check_bin(24'hFFFFFF, 8'd2);

    // Test 3: Y=128 (boundary, equal to THRESHOLD) → white
    s_tdata = 24'h808080; s_tvalid = 1'b1;
    @(posedge clk); #1;
    check_bin(24'hFFFFFF, 8'd3);

    // Test 4: Y=127 (below THRESHOLD) → black
    s_tdata = 24'h7F7F7F; s_tvalid = 1'b1;
    @(posedge clk); #1;
    check_bin(24'h000000, 8'd4);

    // Test 5: Y=129 (above THRESHOLD) → white
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

    // Test 7: tvalid=0 → m_tvalid=0
    s_tvalid = 1'b0; s_tuser = 1'b0; s_tlast = 1'b0;
    @(posedge clk); #1;
    if (m1_tvalid === 1'b0) begin
        $display("PASS Test 7: tvalid=0 propagated");
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("FAIL Test 7: expected m_tvalid=0, got %b", m1_tvalid);
        fail_cnt = fail_cnt + 1;
    end

    // Test 8: backpressure — feed white, then stall and change input,
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

    // Test 9: parameter override — DUT2 with THRESHOLD=200
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
```

- [ ] **Step 2: 嘗試編譯（預期失敗）**

```bash
cd /mnt/c/workspace-win/pcam-gray-bin
iverilog -o sim/sim_bin sim/tb_AXI_Binarize.v
```

預期失敗訊息類似：
```
sim/tb_AXI_Binarize.v:XX: error: Unknown module type: AXI_Binarize
```

這證明 testbench 已正確要求 `AXI_Binarize` module，但模組尚未實作 — 符合 TDD 流程。**不要 commit testbench 直到 Task 3 完成**（避免一次只 commit 失敗的測試）。

---

## Task 3: 寫 RTL 並通過模擬（門 1）

**Files:**
- Create: `src/AXI_Binarize.v`

- [ ] **Step 1: 寫 RTL 完整內容**

Create `src/AXI_Binarize.v`:

```verilog
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
```

- [ ] **Step 2: 編譯**

```bash
cd /mnt/c/workspace-win/pcam-gray-bin
iverilog -o sim/sim_bin sim/tb_AXI_Binarize.v src/AXI_Binarize.v
```

預期：無錯誤、無警告（或僅 timescale 警告）。

- [ ] **Step 3: 執行模擬（門 1）**

```bash
vvp sim/sim_bin
```

預期完整輸出：
```
PASS Test 1: out=0x000000
PASS Test 2: out=0xFFFFFF
PASS Test 3: out=0xFFFFFF
PASS Test 4: out=0x000000
PASS Test 5: out=0xFFFFFF
PASS Test 6: tuser/tlast pass-through
PASS Test 7: tvalid=0 propagated
PASS Test 8: backpressure holds output at white
PASS Test 9: parameter override (TH=200) Y=199->black, Y=200->white
=== Results: 9 PASS, 0 FAIL ===
SIMULATION PASSED
```

通過標準：**9 PASS, 0 FAIL**。任何 FAIL 都不得繼續到 Task 4。

---

## Task 4: 同步源碼到 Vivado IP repo + commit

**Files:**
- Create: `vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_Binarize/hdl/AXI_Binarize.v`

- [ ] **Step 1: 建立 IP 目錄並 cp**

```bash
cd /mnt/c/workspace-win/pcam-gray-bin
mkdir -p vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_Binarize/hdl
cp src/AXI_Binarize.v \
   vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_Binarize/hdl/
ls -la vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_Binarize/hdl/
```

預期：列表顯示 `AXI_Binarize.v`。

- [ ] **Step 2: 確認 .gitignore 不會排除這份檔案**

```bash
git check-ignore -v vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_Binarize/hdl/AXI_Binarize.v
```

預期：無輸出（exit code 1 = 沒被 ignore）。若被 ignore，將檔案改放至 `src/` 為準，cp 步驟仍保留（Vivado 需要）。

- [ ] **Step 3: Stage + commit RTL + testbench**

```bash
git add src/AXI_Binarize.v sim/tb_AXI_Binarize.v
git status
```

預期：兩個新檔在 staging area。若 IP repo 路徑下的檔案沒被 ignore，也一併 add：

```bash
git add vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_Binarize/hdl/AXI_Binarize.v
```

- [ ] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
sim: add AXI_Binarize RTL and testbench (9 PASS)

Fixed-threshold (parameter THRESHOLD = 128) binarization IP.
1-cycle pipeline, mirrors AXI_RGBToGray AXI-Stream interface.
Testbench verifies threshold boundary, pass-through, backpressure,
and parameter-override (THRESHOLD=200) behavior.
EOF
)"
git log --oneline -3
```

預期：新 commit 出現在 log 最上方。

---

## Task 5: 在 Vivado 打包 IP（GUI 操作）

**Files:**
- Create (by Vivado packager): `vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_Binarize/component.xml`
- Create (by Vivado packager): `vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_Binarize/xgui/AXI_Binarize_v1_0.tcl`

> 此 task 為 Vivado GUI 操作，無 bash 自動化，依下列步驟在 Vivado 中執行。

- [ ] **Step 1: 開啟 Vivado 專案**

開啟 `vivado_workspace/Zybo-Z7-20-pcam-5c.xpr`。

- [ ] **Step 2: 建立並打包新 IP**

選單列：**Tools → Create and Package New IP...** → Next。

選 **Package a specified directory** → Next。

**IP location** 填：
```
<absolute path>/vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_Binarize
```
（即上一 task `mkdir -p` 建立的目錄）→ Next。

選 **Package as a library core** → Next，IP root 同上 → Next → Finish。

- [ ] **Step 3: 在 Package IP 視窗逐項設定**

| 標籤頁 | 動作 |
|--------|------|
| **Identification** | name = `AXI_Binarize`，display name = `AXI Binarize`，version = `1.0`，vendor = `local`，library = `local`，category 任意 |
| **Compatibility** | 確認包含 `zynq` 系列 |
| **File Groups** | 確認 `hdl/AXI_Binarize.v` 已被列入 Verilog Synthesis 與 Verilog Simulation |
| **Customization Parameters** | 找到 `THRESHOLD`，右鍵 → Edit Parameter；Format = `bitString`，Display name = `Threshold (0-255)`，Type = `range of integers`，Min=0, Max=255，Default=128 |
| **Ports and Interfaces** | 確認 `s_axis_video` / `m_axis_video` 自動推斷為 AXI4-Stream interfaces；clock = `StreamClk`，reset = `sStreamReset_n` |
| **Customization GUI** | 確認 `THRESHOLD` 顯示為可編輯欄位 |
| **Review and Package** | 點 **Re-Package IP**（不要勾「After Packaging, Close Project」） |

完成後檢查檔案：

- [ ] **Step 4: 驗證 IP repo 結構**

```bash
ls vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_Binarize/
ls vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_Binarize/xgui/
```

預期：含 `component.xml`、`hdl/AXI_Binarize.v`、`xgui/AXI_Binarize_v1_0.tcl`。

- [ ] **Step 5: Commit IP 打包檔案**

```bash
git add vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_Binarize/
git status
git commit -m "feat: package AXI_Binarize as Vivado IP"
```

---

## Task 6: Block Design 整合（GUI 操作）

**Files:**
- Modify (by Vivado): `system.bd` 與相關 wrapper

- [ ] **Step 1: 重新整理 IP Catalog**

回到 Vivado 主視窗：左側 Flow Navigator → **PROJECT MANAGER → IP Catalog** → 上方 Refresh 按鈕。確認 `local/ip/AXI_Binarize` 出現在 catalog 中。

- [ ] **Step 2: 開啟 Block Design**

Flow Navigator → **IP INTEGRATOR → Open Block Design**（或開啟 `system.bd`）。

- [ ] **Step 3: 找到既有連線**

在 BD 中找到 `AXI_RGBToGray_0.m_axis_video` → `axi_vdma_0.S_AXIS_S2MM` 這條 AXI-Stream 連線，**右鍵該連線 → Delete**。

- [ ] **Step 4: 加入 AXI_Binarize 實例**

BD 空白處右鍵 → **Add IP** → 搜尋 `AXI_Binarize` → 點兩下加入。

雙擊新增的 `AXI_Binarize_0` 實例 → 確認 `THRESHOLD` 為 128 → OK。

- [ ] **Step 5: 連線**

| 來源 | 目的 |
|------|------|
| `AXI_RGBToGray_0.m_axis_video` | `AXI_Binarize_0.s_axis_video` |
| `AXI_Binarize_0.m_axis_video` | `axi_vdma_0.S_AXIS_S2MM` |
| 共用 clock 來源（與 RGBToGray 同一條） | `AXI_Binarize_0.StreamClk` |
| 共用 reset 來源（與 RGBToGray 同一條） | `AXI_Binarize_0.sStreamReset_n` |

- [ ] **Step 6: Validate Design**

BD 工具列 → **Validate Design**（F6）。預期：無 error、無 critical warning。

- [ ] **Step 7: Generate Output Products**

Sources 面板 → 找到 `system.bd` → 右鍵 → **Generate Output Products** → Generation Mode = `Out of context per IP` → Generate。

- [ ] **Step 8: Commit BD 變更**

```bash
git add vivado_workspace/Zybo-Z7-20-pcam-5c.srcs/sources_1/bd/
git status
git commit -m "feat: insert AXI_Binarize between AXI_RGBToGray and VDMA in BD"
```

---

## Task 7: Synthesis + Bitstream + Timing 檢查（門 2）

**Files:**
- Generate: `vivado_workspace/.../*.bit`, `vivado_workspace/.../*.ltx`
- Generate: `vivado_workspace/system_wrapper.xsa`

- [ ] **Step 1: Generate Bitstream**

Flow Navigator → **PROGRAM AND DEBUG → Generate Bitstream**。Vivado 會自動先跑 Synthesis 與 Implementation。

預期完成時間：依 PC 規格約 5–15 分鐘。完成後右上角彈出 `Bitstream Generation Completed`。

- [ ] **Step 2: 檢查 Timing Report（門 2）**

點擊 Implementation → **Open Implemented Design** → Reports → **Timing → Report Timing Summary**。

通過標準：
- Pixel clock domain（與 `AXI_Binarize` 相關的 clock）：**WNS ≥ 0ns**
- MIPI D-PHY domain：既有 `dphy_hs_clock_p` 的負 WNS（約 -2.45ns）**維持不變**（已知坑，不視為新失敗）

若 pixel clock domain 出現新的負 WNS（之前沒有），停手並回頭分析 RTL（最常見：未預期的長路徑）。

- [ ] **Step 3: Export Hardware（含 Bitstream）**

選單：**File → Export → Export Hardware...** → Include bitstream → 輸出路徑保持預設（`vivado_workspace/system_wrapper.xsa`） → Finish。

- [ ] **Step 4: 確認 XSA 已更新**

```bash
ls -la vivado_workspace/system_wrapper.xsa
stat -c '%y' vivado_workspace/system_wrapper.xsa
```

預期：mtime 為剛才 Export 的時間戳。

---

## Task 8: Vitis Update HW Spec + Build + Program（板驗準備）

**Files:** 無源碼變更（Vitis 端 Phase 1 不需要修改 main.cc）。

> CLAUDE.md 已知坑：Vitis 不會自動感知 XSA 更新，必須手動 Update Hardware Specification → Build Platform。

- [ ] **Step 1: 開啟 Vitis 並 Update Hardware Specification**

打開 `vitis_workspace/`。Vitis 中對 Platform Component 右鍵 → **Update Hardware Specification** → 選擇剛剛 export 的 `vivado_workspace/system_wrapper.xsa` → OK。

- [ ] **Step 2: Build Platform**

對 Platform Component 右鍵 → **Build**。

預期：Console 顯示 `Build Finished`、無 error。

- [ ] **Step 3: Build App**

對 Application Component 右鍵 → **Build**。

預期：產出 `.elf`，無 error。

- [ ] **Step 4: 連接硬體**

- 接好 PCAM 5C（MIPI 排線）
- 接 HDMI 至螢幕
- USB 連接 Zybo Z7-20（同時供電與 JTAG/UART）
- 開啟 serial terminal（115200 baud）監看 UART

- [ ] **Step 5: Program Device**

對 Application Component 右鍵 → **Run / Program Device** → 選擇硬體目標。

---

## Task 9: 板上驗證（門 3）

**Files:** 無檔案變更。

- [ ] **Step 1: UART 檢查**

預期 UART 輸出包含：
```
OV5640 chip ID = 0x5640
```

若 chip ID 錯誤或 timeout，停手檢查 PCAM 排線、I2C 訊號完整性。

- [ ] **Step 2: HDMI 影像檢查（核心驗證）**

| 測試 | 預期結果 |
|------|----------|
| 鏡頭朝向亮處（窗戶、燈光） | 螢幕大面積純白 `0xFFFFFF` |
| 鏡頭遮住或朝向暗處 | 螢幕大面積純黑 `0x000000` |
| 鏡頭對人臉 | 高反差黑白剪影；面部輪廓、頭髮、衣物形成清楚黑白塊 |
| 鏡頭快速移動 | 影像即時跟隨，無延遲、無撕裂、無拖影 |
| 看畫面顏色 | **只有純黑與純白兩個值**，無灰階、無彩色 |

如果有任何項目失敗：
- 螢幕仍是彩色 → BD 連線錯（沒接到 Binarize 或 bypass 了）
- 螢幕仍是灰階 → Binarize module 未啟用，檢查 ipshared 快取（需 Reset Output Products 並重新 Generate Bitstream）
- 螢幕全黑或全白且不變 → tvalid 沒接好或 reset 卡住

- [ ] **Step 3: 通報使用者並停下**

向使用者口頭/訊息回報：
> 「板上驗證通過：UART 偵測到 OV5640 chip ID = 0x5640，HDMI 顯示純黑白二值化影像，移動鏡頭即時跟隨。請確認是否可以合併到 main。」

**等待使用者明確回覆「可以合併」**。在使用者明確同意之前**不可進入 Task 10**（CLAUDE.md 強制規則 4）。

---

## Task 10: 階段三 — 收尾（僅在使用者說「可以合併」後執行）

**Files:**
- Modify (Obsidian)：`/mnt/c/Users/User/Documents/Obsidian/proj-vault/proj/pcam-gray-bin/TODO.md` 與 `開發紀錄.md`（如存在）

- [ ] **Step 1: 確認使用者授權**

只在使用者明確說「可以合併」/「OK 合併」後才繼續。否則停在 Task 9。

- [ ] **Step 2: Squash merge 回 main**

```bash
cd /mnt/c/workspace-win/pcam-gray-bin
git checkout main
git merge --squash feat/axi-binarize
git status   # 檢查 staging
git commit -m "$(cat <<'EOF'
feat: add AXI_Binarize IP for fixed-threshold binarization

Insert new AXI_Binarize IP after AXI_RGBToGray, threshold = 128
(compile-time parameter). Pipeline now produces pure black/white
HDMI output. Phase 1 has no runtime control; mode switching is
deferred to a follow-up phase.
EOF
)"
```

- [ ] **Step 3: 刪除 feature branch**

```bash
git branch -d feat/axi-binarize
git branch
```

預期：只剩 `main`。

- [ ] **Step 4: Push 到 remote**

```bash
git push
git log --oneline -5
```

- [ ] **Step 5: 更新 Obsidian 筆記**

開啟 `/mnt/c/Users/User/Documents/Obsidian/proj-vault/proj/pcam-gray-bin`：
- `TODO.md`：將二值化 IP 任務勾選 `[x]`
- `開發紀錄.md`：補上日期、threshold 值、板上驗證結果（亮/暗/人臉觀察）

---

## Self-Review Checklist（writing-plans skill 要求）

| 檢查項 | 結果 |
|--------|------|
| Spec 涵蓋率：每個 spec 章節皆有對應 task | ✓ 介面/邏輯/管線 → Task 3；Testbench → Task 2；BD/合成/Vitis/板驗 → Tasks 5-9；強制規則 → Task 1, 9, 10 |
| Placeholder 掃描：無 TBD/TODO/「之後處理」 | ✓ 所有 code block 為完整可執行內容 |
| 型別/命名一致性：`AXI_Binarize` / `THRESHOLD` / `s_axis_video_*` 各 task 皆同 | ✓ |
| Test 通過標準明確 | ✓ 9 PASS, 0 FAIL（門 1）；WNS ≥ 0（門 2）；UART chip ID + HDMI 二值化（門 3） |
| 三道驗證門對齊 CLAUDE.md | ✓ 門 1=Task 3、門 2=Task 7、門 3=Task 9 |
| 強制等待使用者授權才合併 | ✓ Task 9 Step 3 → Task 10 之間明文 |
