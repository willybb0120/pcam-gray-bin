# AXI_RGBToGray IP 設計規格

**日期**：2026-04-29  
**專案**：Zybo-Z7-20 + PCAM 5C（基於 willybb0120/Zybo-Z7-20-pcam-5c-vitis2025）  
**階段**：Phase 1 — 永遠輸出灰階（無控制介面）

---

## 目標

在現有 PCAM → HDMI pipeline 的 `AXI_GammaCorrection` 與 `AXI VDMA` 之間插入自訂 IP `AXI_RGBToGray`，將彩色影像轉為灰階後輸出至 HDMI 螢幕。

**後續計畫（不在本次 scope）**
- Phase 2：加入 AXI-Lite bypass 暫存器，支援彩色 / 灰階模式切換
- Phase 3：加入二值化（threshold）模式，透過開關選擇三種模式

---

## 架構

```
AXI_GammaCorrection
       │ m_axis_video (24-bit AXI-Stream)
       ▼
  AXI_RGBToGray          ← 本次新增
       │ m_axis_video (24-bit AXI-Stream)
       ▼
AXI VDMA (S2MM) → DDR3 → AXI VDMA (MM2S) → rgb2dvi → HDMI
```

**IP 路徑**：`vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_RGBToGray/`

---

## AXI-Stream 介面

| 訊號 | 方向 | 寬度 | 說明 |
|------|------|------|------|
| `StreamClk` | in | 1 | Pixel clock（與 GammaCorrection 共用） |
| `sStreamReset_n` | in | 1 | Active-low reset |
| `s_axis_video_tdata` | in | 24 | RGB 輸入 |
| `s_axis_video_tvalid` | in | 1 | |
| `s_axis_video_tready` | out | 1 | |
| `s_axis_video_tuser` | in | 1 | Start of Frame |
| `s_axis_video_tlast` | in | 1 | End of Line |
| `m_axis_video_tdata` | out | 24 | 灰階輸出 |
| `m_axis_video_tvalid` | out | 1 | |
| `m_axis_video_tready` | in | 1 | |
| `m_axis_video_tuser` | out | 1 | Start of Frame |
| `m_axis_video_tlast` | out | 1 | End of Line |

### Bit Ordering（由 BayerToRGB → GammaCorrection 原始碼確認）

| Bits | Channel |
|------|---------|
| `[23:16]` | R |
| `[15:8]` | B |
| `[7:0]` | G |

> 注意：排列為 R-B-G，非常見 R-G-B，係由 `BayerToRGB` 打包順序（`"00" & R & B & G`）決定。

---

## 灰階轉換

**公式**：BT.601 定點近似

```
Y = (77×R + 150×G + 29×B) >> 8
```

**係數驗證**
- 浮點對應：77/256≈0.301、150/256≈0.586、29/256≈0.113（BT.601: 0.299, 0.587, 0.114）
- 總和：77+150+29 = 256，保證不溢位
- 最大值：256×255 = 65280（16-bit），>> 8 = 255（8-bit）✓

**輸出格式**：保持 24-bit RGB，令 R=B=G=Y，即 `{Y[7:0], Y[7:0], Y[7:0]}`，相容下游 rgb2dvi。

---

## RTL 管線

| Cycle | 動作 |
|-------|------|
| N | 接收 s_axis tdata/tvalid/tuser/tlast |
| N+1 | 輸出 Y（乘加 + 移位），tuser/tlast 同步延遲 1 cycle |

- **延遲**：1 clock cycle
- **tready**：`s_axis_tready = m_axis_tready`（直接透傳，下游背壓直接傳遞）
- **tvalid**：跟隨 s_axis_tvalid 延遲 1 cycle

---

## 檔案結構

```
ipdefs/repo_0/local/ip/AXI_RGBToGray/
├── hdl/
│   └── AXI_RGBToGray.v        # 唯一 RTL 檔（Verilog）
├── xgui/
│   └── AXI_RGBToGray_v1_0.tcl # Vivado GUI 描述
└── component.xml               # IP 打包定義
```

---

## Block Design 整合步驟

1. IP Catalog → Refresh（`local/ip` 已在 repository list）
2. 斷開 `GammaCorrection.m_axis_video` → `VDMA.S_AXIS_S2MM` 連線
3. 加入 `AXI_RGBToGray` 實例
4. 連線：`GammaCorrection.m_axis_video` → `AXI_RGBToGray.s_axis_video`
5. 連線：`AXI_RGBToGray.m_axis_video` → `VDMA.S_AXIS_S2MM`
6. 連線：`StreamClk`、`sStreamReset_n`（與 GammaCorrection 共用）
7. Generate Output Products → Generate Bitstream → Export Hardware（含 Bitstream）

---

## Vitis 端變更

**Phase 1：無需修改。** 純硬體轉換，`main.cc` 不需任何更動。

---

## 資源預估

基線（demo 未加任何自訂模組）：LUT 15%、DSP 0%、BRAM 5.7%。

本 IP 預計新增：
- **LUT**：< 100（乘法器展開 + 加法器）
- **DSP**：0–3（Vivado 可能自動推斷，也可強制 LUT-only）
- **FF**：< 50（1 級管線暫存）

資源充裕，無壓力。
