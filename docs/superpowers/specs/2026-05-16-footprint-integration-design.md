# Footprint 標記模組整合設計規格

**日期**：2026-05-16
**專案**：Zybo-Z7-20 + PCAM 5C（延續 `AXI_Binarize` Phase 1）
**階段**：Phase 2 — 在二值化輸出後加上 footprint 座標分析，UART 印 + HDMI overlay

---

## 目標

將既有 footprint 標記模組（`~/workspace/projects/footprint/`）整合進 pcam-gray-bin pipeline：

- BTN0 按下 → 凍結當前 binary frame
- footprint 模組分析該 frame，輸出 **6 個解剖學標記點 × 2 腳 = 12 個點**（實際 20 個 32-bit 座標數值，見下表）
- UART 印出座標數值（除錯 / log）
- HDMI 螢幕上將 12 個點以「軟體畫點」方式 overlay 顯示

**最終用途**：座標將作為 ANN 預測模型輸入（本 spec 不含 ANN，僅做到座標輸出 + overlay）。

**不在本次 scope**：
- ANN 推論整合
- 多 frame 連續座標追蹤
- 座標濾波 / 平滑

---

## 架構

```
PCAM5C → MIPI CSI-2 → AXI_BayerToRGB → AXI_GammaCorrection
       → AXI_RGBToGray → AXI_Binarize → AXI VDMA (S2MM, 寫)
                                              │
                                              ▼
                                       DDR3 frame buffer
                              ┌───────────────┼───────────────┐
                              │ (HP1, 讀)      │ (HP0, 讀)      │ (write back, 寫)
                              ▼               ▼               │
                       AXI VDMA (MM2S)   AXI_Footprint (新)   │
                              │           AXI master 讀 DDR3  │
                              ▼           AXI-Lite slave      │
                       rgb2dvi → HDMI         │ done IRQ       │
                                              ▼               │
                                       PS (Cortex-A9) ────────┘
                                       ├─ UART 印座標
                                       └─ 軟體寫 DDR3 畫 overlay
```

> 重點：AXI_Footprint **不經過 VDMA**，自己當 AXI master 走 HP0 port 讀 DDR3；VDMA(MM2S) 走另一個 HP port 餵 HDMI。兩個 master 同時讀 DDR3（硬體層 OK），但「讀什麼 buffer / 何時讀」需 CPU 同步（見 Phase 3）。

**核心決策**：

| 決策 | 選擇 | 為什麼 |
|------|------|--------|
| Resolution 不匹配（footprint 原為 640×480，PCAM 為 1280×720） | 改 footprint 參數化吃 1280×720 | 降採樣會掉精度；裁切會丟資訊 |
| Footprint 需掃 3 遍 | DDR3 存 frame，CPU 控制 AXI master 重讀 | footprint 內部本就是 3-pass，不改其架構最簡單 |
| 包裝形式 | 單顆 `AXI_Footprint` IP 封裝整個 `top.v` | 拆 3 顆要重做 inter-IP 控制；維持單體最快 |
| 觸發 | BTN0 凍結 + 算 | 連續算耗 IRQ 與算力；單張即可給 ANN |
| 輸出 | UART + HDMI overlay 雙路 | UART 給開發者除錯，overlay 給使用者肉眼驗證 |
| Overlay 畫法 | CPU 直接寫 DDR3（軟體畫） | 不需新 RTL；座標只有 12 點，CPU 開銷可忽略 |

---

## footprint 模組現況（讀過）

**Repo**：`~/workspace/projects/footprint/`
**檔案**：`rtl/top.v`、`cut.v`、`label3.v`、`label2_forefoot.v`、`tb/tb_top.v`

**處理 pipeline（3-pass）**：
1. **Pass 1（cut）**：垂直直方圖找左右腳分割線 `x_cut`
2. **Pass 2（label3 × 2）**：左右腳各做水平直方圖、平滑、找峰值 / 谷值、邊界（toe / heel）
3. **Pass 3（label2_forefoot × 2）**：以 `min_line_mid` 為界，找前腳掌左右邊界

**輸出（每腳）**：

| 來源 | 訊號 | 數量 | 意義 |
|------|------|------|------|
| label3 | `toe_x, toe_y` | 2 | 腳趾邊界中心 |
| label3 | `heel_x, heel_y` | 2 | 腳跟邊界中心 |
| label3 | `last3_left_x, last3_right_x` | 2 | 後三分之一峰值行左右邊界（只 x） |
| label2_forefoot | `forefoot_left_x, forefoot_left_y` | 2 | 前腳掌左邊界 |
| label2_forefoot | `forefoot_right_x, forefoot_right_y` | 2 | 前腳掌右邊界 |
| label3 (中間值) | `max_line_half, min_line_mid, max_line_last3, max_ones_half, min_ones_mid, max_ones_last3` | 6 | 除錯用，可選擇暴露 |

**小計**：
- 關鍵座標（餵 ANN）：每腳 **10 個 32-bit**，左右合計 **20 個**
- 含中間值：每腳 **16 個 32-bit**，左右合計 **32 個**

「12 個點」是指 6 個解剖學標記 × 2 腳，但每個點不一定都有 x/y（如 `last3_left/right` 只有 x），所以暫存器需要 20–32 個 word，視是否暴露中間值。

**現況限制**（必須改）：
- `cut.v`：`col_count [0:639]` 寫死，`pixel_count` 19-bit（最大 307200）
- `label3.v`：`histogram` 10-bit（max 640），`first_x / last_x` 10-bit，哨兵 `10'h3FF`
- `label2_forefoot.v`：`vertical_hist` 9-bit（max 480），哨兵 `9'h1FF`
- `top.v`：`current_col` 10-bit、`current_row` 9-bit，硬編碼 `639`

---

## AXI_Footprint IP 介面

### AXI-Stream / AXI4 介面

**沒有 AXI-Stream 輸入**（與前面三顆 IP 不同）。資料來源是 AXI master 讀 DDR3。

| 訊號群 | 方向 | 用途 |
|--------|------|------|
| AXI4 master（讀） | out | 讀 DDR3 frame buffer，餵給內部 `top.v` 當 pixel stream |
| AXI-Lite slave | in | PS 寫 CTRL、讀 STATUS 與 12 座標 |
| `done_irq` | out | 處理完成中斷訊號接到 PS IRQ |

### AXI-Lite 暫存器圖

| Offset | R/W | 名稱 | 用途 |
|--------|-----|------|------|
| 0x00 | RW | CTRL | bit[0]=start (write 1 啟動), bit[1]=irq_en, bit[2]=irq_clear |
| 0x04 | R | STATUS | bit[0]=done, bit[1]=busy |
| 0x08 | RW | FB_ADDR | DDR3 frame buffer 起始位址（byte address） |
| 0x0C | RW | FB_STRIDE | bytes/row（預設 1280） |
| 0x10–0x3C | R | LEFT_COORDS[0..11] | 左腳 12 個 32-bit（10 關鍵 + 6 中間值，預留 12 slot） |
| 0x40–0x6C | R | RIGHT_COORDS[0..11] | 右腳 12 個 32-bit（同上） |

> 暫存器 layout 細節在 Phase 1 實作時定稿；上表為 baseline，**已預留 12 slot/腳** 容納 10 關鍵座標 + 2 個中間值（max_line_half, min_line_mid），其餘中間值如需要可再擴展。

### 內部行為

1. AXI-Lite 寫 `CTRL.start=1` → state machine 啟動
2. AXI master 從 `FB_ADDR` 開始按列線性讀 1280×720 bytes
3. 每讀進一 byte，取 `bit[0]` 當 binary pixel 餵 `top.v`，重複 3 遍（cut → label3 → label2_forefoot）
4. 全部完成 → 12 座標寫入暫存器、設 `STATUS.done`、發 IRQ
5. PS 讀走座標、寫 `CTRL` 清 done

---

## DDR3 Memory Map

| 範圍 | 大小 | 用途 |
|------|------|------|
| 0x00000000–0x000FFFFF | 1 MB | FSBL |
| 0x00100000–0x0FFFFFFF | ~255 MB | Vitis app heap / stack |
| 0x10000000–0x100E0FFF | ~900 KB（page-aligned 0xE1000） | Frame buffer 0 |
| 0x10100000–0x101E0FFF | ~900 KB | Frame buffer 1 |
| 0x10200000–0x102E0FFF | ~900 KB | Frame buffer 2 |

**Pixel address 公式**：
```
byte_address(x, y) = FB_BASE + y * FB_STRIDE + x
                     （FB_STRIDE = 1280，與 width 相同，無 padding）
byte value: bit[0] = binary pixel
            0xFF = white, 0x00 = black（與 AXI_Binarize 輸出一致）
```

**Cache coherency 規則**：
- CPU 寫完 overlay → `Xil_DCacheFlushRange(fb_addr, size)` 才能讓 AXI_Footprint / VDMA 讀到
- AXI_Footprint 處理完 → `Xil_DCacheInvalidateRange(fb_addr, size)` 才能讓 CPU 讀到最新（如果 CPU 要再看 frame）

---

## Phase 拆分

### Phase 0：footprint RTL 參數化改造（純模擬，在 footprint repo）

**改動**：

| 檔案 | 改動內容 |
|------|---------|
| `cut.v` | 加 `WIDTH/HEIGHT` parameter；`col_count [0:WIDTH-1]`；`pixel_count` 19→21-bit；硬編碼 `320/639/307200/480` 全參數化 |
| `label3.v` | `histogram` 10→11-bit；`smooth_hist` 11→12-bit；`first_x/last_x` 10→11-bit；哨兵 `10'h3FF` → `11'h7FF` |
| `label2_forefoot.v` | `vertical_hist/first_y/last_y` 9→10-bit；哨兵 `9'h1FF` → `10'h3FF` |
| `top.v` | 加 `WIDTH/HEIGHT` parameter（default 1280/720）並向下傳；`current_col` 10→11-bit；`current_row` 9→10-bit；硬編碼 `639` → `WIDTH-1` |
| `tb_top.v` | 加 1280×720 測試向量；保留 640×480 舊向量做回歸 |

**Exit criteria**：
- iverilog 編譯無 warning
- 舊 640×480 testbench 12 座標**位元級一致**（回歸）
- 新 1280×720 testbench 12 座標肉眼合理

**Deliverables**：footprint repo branch `feat/parameterize-1280x720`

---

### Phase 1：AXI_Footprint IP 包裝 + IP-level 模擬

**改動**（pcam-gray-bin repo branch `feat/axi-footprint-ip`）：

| 檔案 | 內容 |
|------|------|
| `src/AXI_Footprint.v`（新） | 頂層 wrapper：AXI4 master + AXI-Lite slave + 內嵌 `top.v` |
| `src/footprint_top.v / cut.v / label3.v / label2_forefoot.v` | 從 footprint repo copy 改造後版本 |
| `sim/tb_AXI_Footprint.v`（新） | AXI master BFM 模擬 DDR3；AXI-Lite 寫 start、讀 12 座標 |

**Exit criteria**：
- iverilog 含 AXI BFM 通過
- 12 座標與 Phase 0 純模擬**位元級一致**
- AXI 協議無 violation
- cp 到 Vivado 兩個目錄、Reset Output Products、IP package 成功

---

### Phase 2：AXI_Footprint 獨立上板測試（不接 PCAM）

**改動**：

| 項目 | 內容 |
|------|------|
| Vivado BD | 新增 `AXI_Footprint`：AXI master → HP0、AXI-Lite → GP0、IRQ → PS IRQ |
| Vitis app | (1) CPU 寫測試圖到 `0x10000000` (2) `Xil_DCacheFlushRange` (3) AXI-Lite 寫 FB_ADDR、start (4) 等 IRQ (5) UART 印 12 座標 |

**Exit criteria**：
- Vivado timing：WNS ≥ 0ns（D-PHY domain 例外照舊）
- 板上 UART 印的 12 座標 = Phase 1 模擬結果（**0 誤差**）
- 多張測試圖（左偏 / 右偏 / 無腳）正確處理且不 hang
- IRQ 觸發正常

---

### Phase 3：整合 PCAM live pipeline

**核心問題**：VDMA(S2MM) 正在持續寫 DDR3 frame buffer，AXI_Footprint 要「讀一張穩定的 frame」做分析。兩者操作同一塊 DDR3 區域，必須同步避免「讀到一半寫一半的 frame」（tearing）。

**3 個候選同步方案**（Phase 3 開頭再走一輪 brainstorming 選定）：

| 方案 | 做法 | 優點 | 風險 |
|------|------|------|------|
| A | VDMA Park Mode：BTN0 → CPU 把 VDMA 鎖定在「下一張寫完的 buffer」、停止輪替 → footprint 讀該 buffer → 完成後解鎖 | 不會 tear；HDMI 持續顯示同一張 | HDMI 在分析期間畫面凍結（~1 秒） |
| B | Triple buffer + frame counter：VDMA 三 buffer 自動輪替；CPU 取「上一張剛寫完的 buffer」給 footprint，VDMA 繼續寫其他兩張 | HDMI 不凍結 | 邏輯較複雜，需確認 VDMA 不會回頭寫該 buffer |
| C | VDMA 全停 + 重啟：BTN0 → 停 VDMA(S2MM) → footprint 讀 → 重啟 VDMA | 最簡單 | HDMI 在分析期間黑屏或顯示舊畫面 |

> **預設傾向 B**（triple buffer 已在 DDR3 layout 預留 3 個 buffer，符合此方案）。Phase 3 開頭確認 VDMA park 行為後再定。

**改動**（block design + Vitis app，**不動 RTL**）：
- BD：串好 PCAM → Binarize → VDMA → DDR3；AXI_Footprint master 接 HP0（與 VDMA HP1 分開），AXI-Lite 接 GP0
- App 主迴圈：BTN0 → 同步取得 stable buffer → flush cache → 啟動 footprint → 等 IRQ → 印座標

**Exit criteria**：
- HDMI live 不受 footprint 啟動影響
- BTN0 按一次，UART 印出當前 frame 的 12 座標
- 腳放不同位置（左 / 中 / 右）座標肉眼合理
- 連續按 BTN0 100 次無 hang、無記憶體洩漏

---

### Phase 4：HDMI overlay（軟體畫點）

**改動**（只動 Vitis app）：

| 函數 | 行為 |
|------|------|
| `draw_dot(fb, x, y, r)` | 在 binary buffer 對應座標寫 0xFF 畫 N×N 點 |
| `draw_overlay(coords[12])` | 對 12 座標各呼叫 `draw_dot`，畫完 `Xil_DCacheFlushRange` |
| main loop | footprint done → 拿座標 → overlay → 下一幀 HDMI 自動帶 marker |

**Exit criteria**：
- HDMI 上 12 個亮點位置正確
- 標記不出畫面、不破壞底圖
- BTN0 重觸發時舊標記能正確清掉（重畫前先從 binary IP 拉 clean frame）

---

## 工作量總表

| Phase | 工作量 | 風險 | Branch |
|-------|--------|------|--------|
| 0 | 1-2 天 | 低 | footprint repo: `feat/parameterize-1280x720` |
| 1 | 2-3 天 | 中（AXI master 新介面） | `feat/axi-footprint-ip` |
| 2 | 1-2 天 | 中 | `feat/footprint-standalone-test`（或併入 Phase 1 branch） |
| 3 | 2-3 天 | **高**（VDMA 競爭） | `feat/footprint-live-integration` |
| 4 | 1 天 | 低 | `feat/hdmi-overlay` |
| **總計** | **7–11 天** | — | — |

---

## 已知風險

| 風險 | 機率 | 緩解 |
|------|------|------|
| VDMA(S2MM) 寫入與 AXI_Footprint 讀取 frame buffer 衝突造成 tearing | 高 | Phase 3 開頭 brainstorming 三同步方案（park / triple buffer / 全停） |
| AXI master 讀 DDR3 時序錯（burst length / address align） | 中 | Phase 1 用 AXI BFM 詳模擬，Phase 2 單獨上板驗證 |
| Cache coherency 漏 flush/invalidate 讀到舊資料 | 中 | Phase 2 即驗證 flush 流程，Phase 3 沿用 |
| 1280×720 footprint 內部記憶體變大導致 LUT/BRAM 不夠 | 低 | Phase 0 模擬完後估算（histogram/first_x/last_x 陣列尺寸） |
| Footprint 演算法在實拍 1280×720 binary 上效果不如 640×480 訓練資料 | 中 | 演算法本身不在本 spec scope；屆時若需要再 brainstorming 改進 |
| HP0/HP1 兩 master 同時讀 DDR3 造成 bandwidth 競爭，HDMI 掉幀 | 低 | DDR3 頻寬足夠（HP port 各 ~1.2 GB/s），但 Phase 3 觀察 HDMI 行為 |

---

## 路徑速查

| 用途 | 路徑 |
|------|------|
| Footprint 原始 RTL（read-only 參考） | `~/workspace/projects/footprint/rtl/` |
| pcam-gray-bin RTL | `/mnt/c/workspace-win/pcam-gray-bin/src/` |
| Vivado IP 目錄 | `vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_Footprint/hdl/` |
| Vivado ipshared 快取 | `vivado_workspace/Zybo-Z7-20-pcam-5c.gen/sources_1/ip/AXI_Footprint_0/` |
| Vitis app | `vitis_workspace/` |

---

## 開放問題（Phase 開始前需決定）

1. **AXI_Footprint 是否要支援多 frame buffer 自動切換**？目前設計是 CPU 寫 `FB_ADDR` 後啟動單張處理。如果要支援 triple buffer 自動切換，AXI-Lite 需要加 `FB_ADDR_NEXT` 或 ping-pong 邏輯。**預設**：先做單張，triple buffer 由 CPU 控制。
2. **IRQ 還是 polling**？AXI-Lite 暫存器圖兩者都支援。**預設**：兩者都實作，使用者選。
3. **Overlay 標記樣式**：實心點還是十字？大小？顏色（在 binary buffer 上只能 0/1，沒有顏色）。**預設**：實心 5×5 方塊，值 0xFF。
4. **Phase 3 的 frame buffer 同步方案 A/B/C 哪一個**：預設傾向 B（triple buffer + frame counter），但需 Phase 3 開頭確認 VDMA park / interrupt-on-frame-done 行為後再鎖定。
