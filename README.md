# Zybo-Z7-20 PCAM-5C — 灰階影像處理

Zybo Z7-20 + PCAM 5C（OV5640）影像處理專案，基於 Digilent 官方 Demo 移植版本，加入自訂影像處理 IP，最終目標為可在 HDMI 輸出切換顯示模式。

> **基底專案**：[willybb0120/Zybo-Z7-20-pcam-5c-vitis2025](https://github.com/willybb0120/Zybo-Z7-20-pcam-5c-vitis2025)（Vivado/Vitis 2025.2 移植版，已驗證 OV5640 + HDMI 正常）

---

## 開發路線圖

| 階段 | 功能 | 狀態 |
|------|------|------|
| Phase 1 | AXI_RGBToGray — BT.601 灰階輸出 | 🔨 進行中 |
| Phase 2 | 模式切換：彩色 / 灰階（AXI-Lite 控制） | 待開發 |
| Phase 3 | 二值化模式 + 開關選擇三種模式 | 待開發 |

---

## 環境需求

- Vivado 2025.2
- Vitis 2025.2
- 開發板：Digilent Zybo Z7-20
- 週邊：PCAM 5C（OV5640, MIPI CSI-2）
- HDMI 螢幕

---

## 硬體架構（Phase 1）

```
OV5640 (MIPI CSI-2)
    │
    ▼
MIPI D-PHY RX → MIPI CSI-2 RX → AXI_BayerToRGB → AXI_GammaCorrection
                                                            │
                                                            ▼
                                                    AXI_RGBToGray   ← 本專案新增
                                                            │
                                                            ▼
                                                  AXI VDMA → DDR3 Frame Buffer
                                                            │
                                                            ▼
                                                  rgb2dvi → HDMI Output
```

---

## 自訂 IP 說明

| IP 名稱 | 功能 | 來源 |
|---------|------|------|
| `AXI_BayerToRGB` | Bayer 格式轉 RGB（Demosaic） | Digilent |
| `AXI_GammaCorrection` | Gamma 校正（AXI-Lite 可調） | Digilent |
| `AXI_RGBToGray` | BT.601 灰階轉換，1-cycle pipeline | 本專案 |
| `MIPI_CSI_2_RX` | MIPI CSI-2 接收 | Digilent |
| `MIPI_D_PHY_RX` | MIPI D-PHY 物理層接收 | Digilent |
| `rgb2dvi` | RGB 轉 DVI/HDMI | Digilent |

---

## 目錄結構

```
├── src/                              # RTL 源碼（source of truth）
│   └── AXI_RGBToGray.v
├── sim/                              # Testbench
│   └── tb_AXI_RGBToGray.v
├── vivado_workspace/
│   ├── Zybo-Z7-20-pcam-5c.xpr      # Vivado 專案主檔
│   ├── Zybo-Z7-20-pcam-5c.srcs/    # Block Design、約束
│   └── Zybo-Z7-20-pcam-5c.ipdefs/ # 自訂 IP 定義
├── vitis_workspace/                  # Vitis 應用程式
│   └── pcam_app/src/
├── docs/
│   ├── porting_notes.md             # 移植踩坑記錄
│   └── superpowers/                 # 設計文件與實作計畫
└── CLAUDE.md                        # AI 開發規則與工作流程
```

---

## 使用方式

### 步驟一：Clone 專案

```bash
git clone <this-repo-url>
cd pcam-gray-bin
```

### 步驟二：開啟 Vivado 專案

1. 開啟 Vivado 2025.2
2. **File → Open Project** → 選擇 `vivado_workspace/Zybo-Z7-20-pcam-5c.xpr`
3. 若出現 IP 升級提示 → 選擇 **Upgrade**
4. 若找不到 Board File → Tcl Console 執行：
   ```tcl
   xhub::install [xhub::get_xitems *digilent.com:boards:zybo-z7-20*]
   ```
5. **Generate Output Products** → **Generate Bitstream**
6. **File → Export Hardware（Include Bitstream）** → 存到 `vivado_workspace/`

> 若路徑過長（Windows 260 字元限制），在 Tcl Console 執行：
> ```tcl
> save_project_as pcam C:/pcam -force
> ```

### 步驟三：開啟 Vitis 專案

1. 開啟 Vitis 2025.2 → **File → Switch Workspace** → 選擇 `vitis_workspace/`
2. 匯入 `.xsa` 建立 Platform
3. 將 `vitis_workspace/pcam_app/src/` 內所有檔案加入專案
4. **Build → Run**

詳細移植踩坑說明見 [`docs/porting_notes.md`](docs/porting_notes.md)。
