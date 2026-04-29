# Zybo-Z7-20 PCAM-5C — 官方 Demo 移植至 Vitis 2025

> **本專案基於 Digilent 官方 Demo**
> [Zybo-Z7-20-pcam-5c](https://github.com/Digilent/Zybo-Z7-20-pcam-5c)（原為 Vivado 2019.1 + SDK）
> **移植至 Vivado / Vitis 2025.2**，解決舊版 Xilinx SDK 停止支援後無法開啟的問題。

Zybo-Z7-20 開發板搭配 OV5640（PCAM-5C）攝影機的完整專案，包含 Vivado 硬體設計與 Vitis 應用程式原始碼。

## 環境需求

- Vivado 2025.2
- Vitis 2025.2
- 開發板：Digilent Zybo-Z7-20

---

## 目錄結構

```
├── vivado_workspace/                         # Vivado 專案
│   ├── Zybo-Z7-20-pcam-5c.xpr              # 專案主檔（雙擊開啟）
│   ├── Zybo-Z7-20-pcam-5c.srcs/            # 原始碼
│   │   ├── sources_1/bd/system/system.bd   # Block Design
│   │   ├── sources_1/imports/hdl/          # HDL 包裝
│   │   └── constrs_1/imports/constraints/  # 腳位/時序約束
│   └── Zybo-Z7-20-pcam-5c.ipdefs/         # 自訂 IP（MIPI, BayerToRGB 等）
│
├── vitis_workspace/                          # Vitis 應用程式
│   └── pcam_app/
│       ├── lscript.ld                       # 連結腳本
│       └── src/
│           ├── main.cc                      # 主程式
│           ├── ov5640/                      # OV5640 攝影機驅動
│           ├── hdmi/                        # HDMI 輸出
│           └── platform/                   # 平台初始化
│
└── docs/
    └── porting_notes.md                     # 移植說明
```

---

## 使用方式

### 步驟一：Clone 專案

```bash
git clone https://github.com/willybb0120/Zybo-Z7-20-pcam-5c-vitis2025.git
cd Zybo-Z7-20-pcam-5c-vitis2025
```

### 步驟二：開啟 Vivado 專案

1. 開啟 Vivado 2025.2
2. **File → Open Project**
3. 選擇 `vivado_workspace/Zybo-Z7-20-pcam-5c.xpr`
4. 若出現 IP 升級提示 → 選擇 **Upgrade**
5. 在 Sources 面板右鍵 `system.bd` → **Generate Output Products**
6. 執行 **Generate Bitstream**
7. 完成後 **File → Export → Export Hardware（Include Bitstream）**，存到 `vivado_workspace/`

### 步驟三：開啟 Vitis 專案

1. 開啟 Vitis 2025.2
2. **File → Switch Workspace** → 選擇 `vitis_workspace/`
3. **File → New → Application Project**
4. Platform：匯入上一步驟導出的 `.xsa` 檔
5. 將 `vitis_workspace/pcam_app/src/` 內所有檔案加入專案
6. 使用 `vitis_workspace/pcam_app/lscript.ld` 作為連結腳本
7. **Build → Run**

---

## 硬體架構

```
OV5640 (MIPI CSI-2)
    │
    ▼
MIPI D-PHY RX → MIPI CSI-2 RX → Bayer to RGB → Gamma Correction
                                                        │
                                                        ▼
                                              AXI VDMA → Frame Buffer (DDR)
                                                        │
                                                        ▼
                                              AXI4-Stream to Video → rgb2dvi → HDMI Output
```

## 自訂 IP 說明

| IP 名稱 | 功能 |
|---------|------|
| `AXI_BayerToRGB` | Bayer 格式轉 RGB |
| `AXI_GammaCorrection` | Gamma 校正 |
| `MIPI_CSI_2_RX` | MIPI CSI-2 接收 |
| `MIPI_D_PHY_RX` | MIPI D-PHY 物理層接收 |
| `rgb2dvi` | RGB 轉 DVI/HDMI |
