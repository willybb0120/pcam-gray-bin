# AXI_Binarize IP 設計規格

**日期**：2026-05-05
**專案**：Zybo-Z7-20 + PCAM 5C（延續 `AXI_RGBToGray` Phase 1）
**階段**：Phase 1 — 永遠輸出二值化影像（無控制介面、threshold 為 compile-time parameter）

---

## 目標

在 `AXI_RGBToGray` 之後、`AXI VDMA` 之前插入新 IP `AXI_Binarize`，將灰階影像依固定閾值二值化後輸出至 HDMI 螢幕。

**後續計畫（不在本次 scope）**
- 下一階段：為 `AXI_RGBToGray` 與 `AXI_Binarize` 各加 AXI-Lite bypass register、BD 加入 AXI GPIO（按鈕輸入）、Vitis main.cc 加 button polling，達成「原始 / 灰階 / 二值化」三模式按鈕切換

---

## 架構

```
AXI_GammaCorrection
       │ 24-bit AXI-Stream（[23:16]=R, [15:8]=B, [7:0]=G）
       ▼
  AXI_RGBToGray             （既有）
       │ 24-bit AXI-Stream（{Y, Y, Y}）
       ▼
  AXI_Binarize              ← 本次新增
       │ 24-bit AXI-Stream（24'h000000 或 24'hFFFFFF）
       ▼
  AXI VDMA (S2MM) → DDR3 → AXI VDMA (MM2S) → rgb2dvi → HDMI
```

**插入點理由**
- 上游已是 `{Y, Y, Y}` 灰階，直接讀任一 byte 即可，不需重算亮度
- 與 `AXI_RGBToGray` 同為 stream-only 變換，不需 frame buffer，符合既有風格
- VDMA、rgb2dvi 設定不變，下游一律當 24-bit RGB 處理

**IP 路徑**：`vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_Binarize/`

---

## AXI-Stream 介面

完全鏡射 `AXI_RGBToGray`，確保上下游接腳一致。

| 訊號 | 方向 | 寬度 | 說明 |
|------|------|------|------|
| `StreamClk` | in | 1 | Pixel clock（與上游共用） |
| `sStreamReset_n` | in | 1 | Active-low reset |
| `s_axis_video_tdata` | in | 24 | 來自 `AXI_RGBToGray`，已是 `{Y, Y, Y}` |
| `s_axis_video_tvalid` | in | 1 | |
| `s_axis_video_tready` | out | 1 | = `m_axis_video_tready`（透傳） |
| `s_axis_video_tuser` | in | 1 | Start of Frame |
| `s_axis_video_tlast` | in | 1 | End of Line |
| `m_axis_video_tdata` | out | 24 | `24'hFFFFFF` 或 `24'h000000` |
| `m_axis_video_tvalid` | out | 1 | |
| `m_axis_video_tready` | in | 1 | |
| `m_axis_video_tuser` | out | 1 | SOF（延遲 1 cycle） |
| `m_axis_video_tlast` | out | 1 | EOL（延遲 1 cycle） |

### Parameter

```verilog
parameter [7:0] THRESHOLD = 8'd128
```

- Compile-time 可調，預設 128（中性灰）
- Vivado IP GUI 暴露為 spinbox（0~255），改 threshold 不需動 RTL，但仍須重新合成
- testbench 透過 `defparam` 驗證不同 threshold 行為

### 灰階值取得

```verilog
wire [7:0] Y = s_axis_video_tdata[7:0];
```

- 上游 `{Y, Y, Y}` 三 byte 相同，取最低位 byte 最便宜
- 不依賴 R/B/G 順序，與 `AXI_RGBToGray` 的 R-B-G 排列無關

---

## 二值化邏輯

```verilog
wire        bin       = (Y >= THRESHOLD);
wire [23:0] pixel_out = bin ? 24'hFFFFFF : 24'h000000;
```

**閾值比較邊界**：採 `>=`，含閾值點為白。Y=128（中性灰）配合 `THRESHOLD=128` 時剛好歸為白，符合教科書慣例。

**輸出格式**：純黑或純白 24-bit RGB，相容下游 rgb2dvi。

---

## RTL 管線

| Cycle | 動作 |
|-------|------|
| N | 接收 s_axis tdata/tvalid/tuser/tlast |
| N+1 | 輸出 pixel_out（比較 + mux），tuser/tlast 同步延遲 1 cycle |

```verilog
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
```

- **延遲**：1 clock cycle
- **背壓**：`s_axis_tready = m_axis_tready`（直接透傳）
- **tvalid**：跟隨 s_axis_tvalid 延遲 1 cycle

---

## 檔案結構

**WSL 源碼（source of truth）**
```
src/
├── AXI_RGBToGray.v       （既有）
└── AXI_Binarize.v        ← 新增

sim/
├── tb_AXI_RGBToGray.v    （既有）
└── tb_AXI_Binarize.v     ← 新增
```

**Vivado IP repository**
```
ipdefs/repo_0/local/ip/AXI_Binarize/
├── hdl/
│   └── AXI_Binarize.v        # cp 目標 1
├── tb/
├── xgui/
│   └── AXI_Binarize_v1_0.tcl # 含 THRESHOLD spinbox（0~255）
└── component.xml
```

---

## 開發流程（依 CLAUDE.md 三階段 + 三道驗證門）

### 階段一 — Branch & RTL 開發

```bash
git checkout -b feat/axi-binarize
```

1. 寫 `src/AXI_Binarize.v` 與 `sim/tb_AXI_Binarize.v`
2. cp 到 Vivado IP 路徑：
   ```bash
   cp src/AXI_Binarize.v \
     vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_Binarize/hdl/
   ```
3. **[門 1] iverilog 模擬必須通過**：
   ```bash
   iverilog -o sim/sim_bin sim/tb_AXI_Binarize.v src/AXI_Binarize.v
   vvp sim/sim_bin
   # 確認輸出：9 PASS, 0 FAIL
   ```
4. Commit：`feat: add AXI_Binarize IP for fixed-threshold binarization`

### 階段二 — Vivado 合成 + 板上驗證

1. Tools → Create and Package New IP（AXI4-Stream 範本）
2. 編輯 xgui tcl，將 `THRESHOLD` 暴露為 0~255 spinbox
3. IP Catalog → Refresh
4. 斷開 `AXI_RGBToGray.m_axis_video` → `VDMA.S_AXIS_S2MM`
5. 加入 `AXI_Binarize` 實例（`THRESHOLD = 128`）
6. 連線：`AXI_RGBToGray.m_axis_video` → `AXI_Binarize.s_axis_video`
7. 連線：`AXI_Binarize.m_axis_video` → `VDMA.S_AXIS_S2MM`
8. 連線 `StreamClk`、`sStreamReset_n`
9. Generate Output Products → Generate Bitstream
10. **[門 2] Timing**：pixel clock domain WNS ≥ 0；MIPI D-PHY domain 既有 violation 維持不變（已知坑）
11. Export Hardware（含 Bitstream） → Vitis Update HW Spec → Build Platform → Build App → Run
12. **[門 3] 板上驗證**：
    - UART 顯示 `OV5640 chip ID = 0x5640`
    - HDMI 螢幕呈現純黑白二值化即時影像
    - 鏡頭對亮處 → 白；遮住 → 黑；對人臉 → 高反差剪影
    - 移動鏡頭即時跟隨，無延遲、無畫面撕裂
13. 通報「板上驗證通過，請確認是否可以合併」，等待使用者明確同意

### 階段三 — 收尾

> 等使用者明確說「可以合併」後才執行。

```bash
git checkout main
git merge --squash feat/axi-binarize
git commit -m "feat: add AXI_Binarize IP for fixed-threshold binarization"
git branch -d feat/axi-binarize
git push
```

---

## Testbench 計畫（門 1）

延用 `tb_AXI_RGBToGray.v` 的 PASS/FAIL 計數結構：

| # | 場景 | 輸入 | 期望輸出 |
|---|------|------|----------|
| 1 | 純黑 | tdata=`24'h000000`（Y=0） | `24'h000000` |
| 2 | 純白 | tdata=`24'hFFFFFF`（Y=255） | `24'hFFFFFF` |
| 3 | 閾值邊界（=） | Y=128 | `24'hFFFFFF` |
| 4 | 閾值下緣（−1） | Y=127 | `24'h000000` |
| 5 | 閾值上緣（+1） | Y=129 | `24'hFFFFFF` |
| 6 | tuser/tlast 透傳 | SOF+EOL | 1-cycle 後 m_tuser=1, m_tlast=1 |
| 7 | tvalid=0 透傳 | s_tvalid=0 | m_tvalid=0 |
| 8 | 背壓 hold | tready=0 期間改變輸入 | 輸出維持上一筆 |
| 9 | Parameter 可重組性 | 另一 DUT 實例 `THRESHOLD=200`，測 Y=199、Y=200 | 199→黑、200→白 |

通過標準：**9 PASS, 0 FAIL**。

---

## 資源預估

| 項目 | 預估增量 |
|------|----------|
| LUT | < 20（8-bit 比較器 + 24-bit mux） |
| FF | ≈ 50（1 級管線：24-bit tdata + tvalid + tuser + tlast） |
| DSP | 0 |
| BRAM | 0 |
| Critical path | 比較器延遲，遠低於 pixel clock 週期 |

對比 `AXI_RGBToGray` 約少 80%（無乘法器），實質可忽略。

---

## 已知坑與注意事項

- **ipshared 不自動更新**：改 IP 源碼後須 Reset Output Products 或手動 cp 到 `Zybo-Z7-20-pcam-5c.gen/sources_1/ip/AXI_Binarize_0/`
- **MIPI D-PHY timing violation**：屬上游既有問題，本 IP 不在該 clock domain，不會新增 violation
- **不可在 main branch 直接改 src/**：依 CLAUDE.md 強制規則 1，必須先 `git checkout -b feat/axi-binarize`
- **Phase 2 已預留**：本 IP 介面與 `AXI_RGBToGray` 對稱，下階段加入 AXI-Lite bypass 時兩顆 IP 改動模式相同
