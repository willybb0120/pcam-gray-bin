# AXI_ImageModeSelect IP 設計規格

**日期**：2026-05-05
**專案**：Zybo Z7-20 + PCAM 5C
**階段**：三模式顯示切換：原圖 / 灰階 / 二值化

## 目標

新增一顆 `AXI_ImageModeSelect` IP，用單一板上按鈕循環切換 HDMI 顯示模式：

| Mode | 顯示 | 輸出 |
|------|------|------|
| `0` | 原圖 | GammaCorrection 後的 24-bit RGB 直接輸出 |
| `1` | 灰階圖 | BT.601 灰階 `{Y, Y, Y}` |
| `2` | 灰階後二值化圖 | `24'h000000` 或 `24'hFFFFFF` |
| `3` | 保留 | 暫時等同原圖 |

既有 `AXI_RGBToGray` 與 `AXI_Binarize` 檔案保留，不刪除。新的 Block Design 會用 `AXI_ImageModeSelect` 取代目前 `AXI_RGBToGray -> AXI_Binarize` 這段串接，讓三模式選擇集中在一顆 IP 與一個 AXI-Lite register。

## 架構

目前 pipeline：

```text
AXI_GammaCorrection
  -> AXI_RGBToGray
  -> AXI_Binarize
  -> AXI VDMA
```

新 pipeline：

```text
AXI_GammaCorrection
  -> AXI_ImageModeSelect
  -> AXI VDMA
  -> DDR3 -> HDMI
```

選擇集中式 IP 的理由：

- Vitis 只需要寫入一個 `mode` register。
- RTL 只在一個地方決定輸出原圖、灰階或二值化。
- 三種輸出共享同一組 AXI-Stream handshake 與 1-cycle pipeline，行為一致。
- 後續若要把 threshold 改成 runtime register，可以在同一顆 IP 內擴充。

## AXI-Stream 介面

`AXI_ImageModeSelect` 的 video stream 介面沿用現有自訂 IP 命名，方便 Vivado `ipx::infer_bus_interfaces` 推斷：

| 訊號 | 方向 | 寬度 | 說明 |
|------|------|------|------|
| `StreamClk` | in | 1 | video stream clock |
| `sStreamReset_n` | in | 1 | active-low stream reset |
| `s_axis_video_tdata` | in | 24 | 來自 `AXI_GammaCorrection` |
| `s_axis_video_tvalid` | in | 1 | slave valid |
| `s_axis_video_tready` | out | 1 | 等於 `m_axis_video_tready` |
| `s_axis_video_tuser` | in | 1 | SOF |
| `s_axis_video_tlast` | in | 1 | EOL |
| `m_axis_video_tdata` | out | 24 | 選擇後輸出 |
| `m_axis_video_tvalid` | out | 1 | master valid |
| `m_axis_video_tready` | in | 1 | master ready |
| `m_axis_video_tuser` | out | 1 | SOF 延遲 1 cycle |
| `m_axis_video_tlast` | out | 1 | EOL 延遲 1 cycle |

背壓策略沿用現有 `AXI_RGBToGray` / `AXI_Binarize`：

```verilog
assign s_axis_video_tready = m_axis_video_tready;
```

當 `m_axis_video_tready == 0` 時，輸出暫存器保持不變。

## 影像處理邏輯

GammaCorrection 的 `tdata` bit ordering 維持專案既有定義：

```text
[23:16] = R
[15:8]  = B
[7:0]   = G
```

灰階公式沿用 `AXI_RGBToGray` 的 BT.601 定點近似：

```verilog
Y = (77*R + 150*G + 29*B) >> 8;
```

二值化公式沿用 `AXI_Binarize`：

```verilog
bin = (Y >= THRESHOLD);
pixel_bin = bin ? 24'hFFFFFF : 24'h000000;
```

`THRESHOLD` 第一版維持 compile-time parameter：

```verilog
parameter [7:0] THRESHOLD = 8'd128
```

本次不加入 runtime threshold register，避免把模式切換和閾值調整混成同一階段。

## AXI-Lite 控制

IP 新增 AXI-Lite slave 介面，用於 Vitis 寫入顯示模式。

第一版只需要一個 register：

| Offset | 名稱 | 位元 | 說明 |
|--------|------|------|------|
| `0x00` | `CTRL` | `[1:0] mode` | `0` 原圖、`1` 灰階、`2` 二值化、`3` 保留 |

Reset 後 `mode = 0`，預設顯示原圖。

`mode` register 由 AXI-Lite clock domain 寫入，video stream 在 `StreamClk` domain 使用。若 AXI-Lite clock 與 `StreamClk` 不同，RTL 需用雙級同步器把 `mode[1:0]` 同步到 `StreamClk` domain。同步後的 mode 在像素層級生效；切換瞬間可能有少量像素混合不同模式，這對手動按鈕切換可接受。

## Vitis 按鈕控制

Vitis 端使用單一按鈕做循環切換：

```text
原圖 -> 灰階 -> 二值化 -> 原圖
```

實作採 polling + debounce，不使用 interrupt。

預期流程：

1. 初始化 video pipeline 後，先寫 `mode = 0`。
2. 在主迴圈中讀取按鈕狀態。
3. 偵測「未按 -> 按下」邊緣。
4. debounce，例如延遲 30 ms 後再次確認仍為按下。
5. 更新 `mode = (mode + 1) % 3`。
6. `Xil_Out32(IMAGE_MODE_BASE_ADDR + 0x00, mode)`。
7. UART 印出目前模式，方便板上驗證。

按鈕來源固定使用 Zybo Z7-20 的 `btn[0]`。Block Design 新增一顆 AXI GPIO IP，設定為 1-bit input，外接 top-level `btn[0]` port。約束檔啟用既有 Zybo Z7 `btn[0]` 腳位：

```tcl
set_property -dict { PACKAGE_PIN K18 IOSTANDARD LVCMOS33 } [get_ports { btn[0] }]
```

Vitis 端使用 `XGpio` polling 讀取此 AXI GPIO。既有 PS GPIO/EMIO `cam_gpio` 保留給 camera 控制，不拿來接模式切換按鈕，避免影響 OV5640 初始化。

## IP 包裝流程

依 Obsidian 筆記 `自訂 IP 包裝指南 — Tcl 流程與除錯.md`，新 IP 包裝必須使用 Tcl，可重現、不走 GUI Wizard。

必要要求：

- 先確認不在 `main`。
- RTL 通過 iverilog 模擬後才進 Vivado 包裝。
- `src/AXI_ImageModeSelect.v` cp 到 `vivado_workspace/.../ipdefs/repo_0/local/ip/AXI_ImageModeSelect/hdl/`。
- Tcl 使用 `ipx::package_project`。
- 使用 `ipx::infer_bus_interfaces` 推斷 AXI-Stream。
- 使用單數 `ipx::infer_bus_interface` 推斷 clock/reset。
- 設定 reset `POLARITY = ACTIVE_LOW`。
- `StreamClk` 關聯 `s_axis_video` / `m_axis_video`。
- AXI-Lite bus interface 必須正確關聯其 clock/reset。
- 包裝後檢查 `component.xml` 內的 bus interface、`ASSOCIATED_BUSIF`、`ASSOCIATED_RESET`、`POLARITY`。

## Vivado 整合

Block Design 修改步驟：

1. Refresh IP Catalog。
2. 移除 `AXI_RGBToGray_0` 與 `AXI_Binarize_0` 到 VDMA 的現有串接。
3. 加入 `AXI_ImageModeSelect_0`。
4. 連線 `AXI_GammaCorrection_0/m_axis_video -> AXI_ImageModeSelect_0/s_axis_video`。
5. 連線 `AXI_ImageModeSelect_0/m_axis_video -> axi_vdma_0/S_AXIS_S2MM`。
6. 連線 `StreamClk` 與 `sStreamReset_n` 到既有 video stream clock/reset。
7. 將 `AXI_ImageModeSelect_0` 的 AXI-Lite slave 接到 PS AXI interconnect，分配 base address。
8. 加入 AXI GPIO，設定 1-bit input，外接 `btn[0]`。
9. 將 `btn[0]` 約束到 Zybo Z7-20 的 K18 腳位。
10. Validate Design。
11. Reset Output Products + Generate Output Products。
12. Generate Bitstream。
13. Export Hardware Include Bitstream 到 `vivado_workspace/system_wrapper.xsa`。

若板上行為與 bitstream 不一致，依 Obsidian 指南的 10 步決策樹檢查，尤其注意 Vitis 2025.2 `launch.json` 可能指向舊 bitstream。

## 測試計畫

新增 `sim/tb_AXI_ImageModeSelect.v`，測試下列情境：

| # | 場景 | 輸入 | 期望 |
|---|------|------|------|
| 1 | Reset default | reset 後 | `mode=0` 原圖 |
| 2 | 原圖模式 | 任意 R-B-G pixel | `tdata` 不變 |
| 3 | 灰階黑白 | 黑、白 | `{0,0,0}`、`{255,255,255}` |
| 4 | 灰階 R/G/B | 純紅、純綠、純藍 | 沿用既有 Y=76/149/28 |
| 5 | 二值化低於 threshold | Y=127 | 黑 |
| 6 | 二值化等於 threshold | Y=128 | 白 |
| 7 | 二值化高於 threshold | Y=129 | 白 |
| 8 | `tuser/tlast` | SOF/EOL | 延遲 1 cycle 後保留 |
| 9 | `tvalid=0` | invalid pixel | `m_tvalid=0` |
| 10 | backpressure | `m_tready=0` 時改 input | output hold |
| 11 | AXI-Lite write mode | 寫 `0/1/2/3` | mode select 正確 |

門 1 模擬至少包含：

```bash
iverilog -o sim/sim_mode sim/tb_AXI_ImageModeSelect.v src/AXI_ImageModeSelect.v
vvp sim/sim_mode
```

預期輸出為全 PASS、0 FAIL。改動若同時影響既有 `AXI_RGBToGray` 或 `AXI_Binarize`，也必須重跑各自 testbench。

## 板上驗證

板上驗證通過條件：

- UART 確認 OV5640 Chip ID = `0x5640`。
- HDMI 初始顯示原圖。
- 按一次按鈕切到灰階。
- 再按一次切到二值化。
- 再按一次回到原圖。
- UART 印出的 mode 與畫面一致。
- 畫面即時更新，無明顯 tearing、卡住或黑屏。

板上驗證完成後，依 `CLAUDE.md` 必須停下並詢問使用者是否「可以合併」。未得到明確同意前，不執行 squash merge、刪 branch 或 push。

## 非目標

- 不刪除 `AXI_RGBToGray` 與 `AXI_Binarize`。
- 不在本階段加入 runtime threshold 調整。
- 不改 camera sensor format 設定。
- 不改 VDMA frame buffer 架構。
- 不追求無縫 frame-boundary 切換；按鈕切換瞬間允許少量像素跨模式。
