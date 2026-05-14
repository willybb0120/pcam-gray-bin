# Zybo-Z7-20 PCAM-5C - 灰階 / 二值化影像處理

Zybo Z7-20 + PCAM 5C（OV5640）影像處理專案，基於 Digilent 官方 Demo 移植版本，加入自訂 AXI-Stream 影像處理 IP，支援 HDMI 輸出在彩色、灰階、二值化三種模式之間切換。

> **基底專案**：[willybb0120/Zybo-Z7-20-pcam-5c-vitis2025](https://github.com/willybb0120/Zybo-Z7-20-pcam-5c-vitis2025)（Vivado/Vitis 2025.2 移植版，已驗證 OV5640 + HDMI 正常）

---

## 功能狀態

| 功能 | 狀態 | 說明 |
|------|------|------|
| OV5640 影像輸入 | 已完成 | PCAM 5C MIPI CSI-2 輸入 |
| HDMI 影像輸出 | 已完成 | 1920x1080 輸出到 HDMI |
| 彩色模式 | 已完成 | 原始 RGB 畫面直通 |
| 灰階模式 | 已完成 | BT.601 係數轉換 |
| 二值化模式 | 已完成 | 固定門檻值 128 |
| BTN0 模式切換 | 已完成 | 彩色 -> 灰階 -> 二值化循環 |

目前可使用 `vitis_workspace/app_gray/boot/rgb-gray-bin-boot/BOOT.bin` 從 SD card 啟動完整三模式版本。

---

## 環境需求

- Vivado 2025.2
- Vitis 2025.2
- 開發板：Digilent Zybo Z7-20
- 週邊：PCAM 5C（OV5640, MIPI CSI-2）
- HDMI 螢幕

---

## 硬體架構

```
OV5640 (MIPI CSI-2)
    │
    ▼
MIPI D-PHY RX -> MIPI CSI-2 RX -> AXI_BayerToRGB -> AXI_GammaCorrection
                                                            │
                                                            ▼
                                                    AXI_ImageModeSelect
                                                    0: RGB passthrough
                                                    1: grayscale
                                                    2: binary
                                                            │
                                                            ▼
                                                  AXI VDMA -> DDR3 Frame Buffer
                                                            │
                                                            ▼
                                                  rgb2dvi -> HDMI Output
```

---

## 自訂 IP 說明

| IP 名稱 | 功能 | 來源 |
|---------|------|------|
| `AXI_BayerToRGB` | Bayer 格式轉 RGB（Demosaic） | Digilent |
| `AXI_GammaCorrection` | Gamma 校正（AXI-Lite 可調） | Digilent |
| `AXI_RGBToGray` | BT.601 灰階轉換，1-cycle pipeline | 本專案 |
| `AXI_Binarize` | 灰階影像固定門檻二值化 | 本專案 |
| `AXI_ImageModeSelect` | 彩色 / 灰階 / 二值化模式選擇，AXI-Lite 控制 | 本專案 |
| `MIPI_CSI_2_RX` | MIPI CSI-2 接收 | Digilent |
| `MIPI_D_PHY_RX` | MIPI D-PHY 物理層接收 | Digilent |
| `rgb2dvi` | RGB 轉 DVI/HDMI | Digilent |

---

## 目錄結構

```
├── src/                              # RTL 源碼（source of truth）
│   ├── AXI_RGBToGray.v
│   ├── AXI_Binarize.v
│   └── AXI_ImageModeSelect.v
├── sim/                              # Testbench
│   ├── tb_AXI_RGBToGray.v
│   ├── tb_AXI_Binarize.v
│   └── tb_AXI_ImageModeSelect.v
├── vivado_workspace/
│   ├── Zybo-Z7-20-pcam-5c.xpr      # Vivado 專案主檔
│   ├── Zybo-Z7-20-pcam-5c.srcs/    # Block Design、約束
│   └── Zybo-Z7-20-pcam-5c.ipdefs/ # 自訂 IP 定義
├── vitis_workspace/                  # Vitis 應用程式
│   └── app_gray/
│       ├── src/                      # Vitis application source
│       └── boot/
│           └── rgb-gray-bin-boot/    # 三模式 BOOT.bin
├── scripts/                          # IP packaging Tcl scripts
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
3. 將 `vitis_workspace/app_gray/src/` 內所有檔案加入專案
4. **Build → Run**

### SD Card 啟動

若只要執行目前已建立的三模式版本，將下列檔案複製到 SD card 的 FAT32 boot partition：

```text
vitis_workspace/app_gray/boot/rgb-gray-bin-boot/BOOT.bin
```

上電後 HDMI 會先顯示彩色畫面，按下 Zybo Z7-20 的 `BTN0` 依序切換：

```text
0: 彩色
1: 灰階
2: 二值化
```

詳細移植踩坑說明見 [`docs/porting_notes.md`](docs/porting_notes.md)。
