# PCAM 5C 驗證筆記
> Zybo Z7-20 + PCAM 5C，使用 Digilent 原版 demo 確認硬體可正常運作

---

## 1. 目的與環境

**目的**：在加入自訂灰階/二值化模組之前，先確認 PCAM 硬體、MIPI 介面、HDMI 輸出都能正常跑起來。

**硬體**
- Zybo Z7-20（Zynq-7000 SoC）
- PCAM 5C（OV5640 感光元件，MIPI CSI-2 2-lane）
- HDMI 螢幕

**工具版本**
- Vivado 2025.2
- Vitis Unified IDE 2025.2

**參考來源**
- Digilent/Zybo-Z7-20-pcam-5c（官方 repo，最新 release：v2019.1-1）
- 注意：官方只維護到 2019.1，2025.2 需自行移植

---

## 2. Demo Pipeline

資料從相機到螢幕的流向：

```
PCAM 5C (OV5640)
  ↓ MIPI CSI-2 (2-lane, 差分訊號)
MIPI D-PHY RX      ← 處理電氣層
  ↓
MIPI CSI-2 RX      ← 處理協定層，解出 Bayer raw data
  ↓
AXI_BayerToRGB     ← demosaic，Bayer → RGB888（每像素 24-bit）
  ↓
AXI_GammaCorrection ← 亮度伽瑪校正，AXI-Lite 可調
  ↓
AXI VDMA (S2MM)    ← 把 AXI-Stream 寫入 DDR3 frame buffer
  ↓
DDR3 (0x0A000000)  ← 存三個 frame
  ↑
AXI VDMA (MM2S)    ← 從 DDR3 讀出送往 HDMI
  ↓
rgb2dvi + VTC      ← 產生 HDMI 時序與訊號
  ↓
HDMI TX
```

**PS（ARM）端的工作**
- I2C → 初始化 OV5640 暫存器（解析度、幀率、AWB）
- GPIO → 相機 reset
- AXI-Lite → 寫 Gamma 校正係數
- VDMA driver → 設定 frame buffer 位址、啟動讀寫通道

**啟動順序原則：back-to-front**
先設定下游（VDMA、HDMI），再啟動上游（CSI-2、相機），避免資料進來時下游還沒準備好。

---

## 3. Vivado 2025.2 移植踩坑

### 坑 1：IP Upgrade 對話框
- **問題**：開啟 2019.1 的 .xpr，Vivado 跳出 IP upgrade 詢問
- **解法**：直接點 OK，讓 Vivado 自動升級

### 坑 2：目錄結構遷移
- **問題**：Vivado 詢問是否遷移為新版目錄結構（srcs/gen 分開）
- **原因**：遷移不可逆，且 Digilent 自訂 IP 不會被包含在遷移中
- **解法**：選 **No**，維持原始目錄結構

### 坑 3：Windows 路徑超過 260 字元
- **問題**：`ERROR: [Common 17-680] Path length exceeds 260-Byte maximum`
- **原因**：專案路徑太深，合成時寫 .dcp checkpoint 失敗
- **解法**：用 Tcl Console 移專案
  ```tcl
  save_project_as pcam C:/pcam -force
  ```

### 坑 4：Board Files 未安裝
- **問題**：`WARNING: Board part '' set for the project is not found`
- **原因**：Vivado 2025.2 找不到 Zybo Z7-20 的 board 定義
- **解法**：安裝 Digilent board files
  ```tcl
  xhub::install [xhub::get_xitems *digilent.com:boards:zybo-z7-20*]
  ```
  或手動下載 vivado-boards repo，複製 `zybo-z7-20` 資料夾到 Vivado board store 目錄

### 坑 5：Timing Violations（可接受）
- **問題**：impl 完成後 WNS = -2.450ns，2 個 failing endpoints
- **原因**：違反只發生在 `dphy_hs_clock_p` domain（MIPI D-PHY 實體輸入）；MIPI 是 source-synchronous 介面，實際對齊靠 IDELAYE2 tap 值，靜態時序分析在這裡不準確
- **解法**：直接燒進去試，實際硬體上不影響功能；若出現畫面問題再加 `set_false_path`

---

## 4. Vitis 2025.2 建置踩坑

### 背景差異
| 項目 | 2019.1 | 2025.2 |
|------|--------|--------|
| IDE | Xilinx SDK | Vitis Unified IDE |
| 建置系統 | Makefile | CMake + Ninja |
| 參數定義 | DEVICE_ID 為整數索引 | SDT mode：改用 base address |

---

### 坑 1：linker_files/lscript_a9.ld.in 不存在
- **問題**：`CMake Error: File .../linker_files/lscript_a9.ld.in does not exist`
- **原因**：Vitis 2025.2 CMake 流程需要 linker script 模板，舊 SDK 用的是直接的 `lscript.ld`
- **解法**：從 platform 複製模板到 `src/linker_files/`
  ```bash
  # 模板位置
  platform_zyboz7/zynq_fsbl/linker_files/lscript_a9.ld.in
  # 複製到
  app_pcam/src/linker_files/lscript_a9.ld.in
  ```
- **注意**：`linker_gen()` 執行後會自動刪掉這個資料夾，是設計行為，不是 bug

### 坑 2：USER_LINKER_SCRIPT 未定義
- **問題**：`set_target_properties called with incorrect number of arguments`
- **原因**：`linker_gen()` 生成 `lscript.ld` 但沒有設定 `USER_LINKER_SCRIPT` 變數
- **解法**：在 `src/UserConfig.cmake` 加入：
  ```cmake
  set(USER_LINKER_SCRIPT "${CMAKE_SOURCE_DIR}/lscript.ld")
  ```

### 坑 3：platform.c / OV5640.cpp 沒被編譯
- **問題**：`undefined reference to 'init_platform()'`
- **原因**：CMake 只掃頂層 `src/`，子目錄的 .c/.cpp 需手動加
- **解法**：在 `UserConfig.cmake` 加入：
  ```cmake
  set(USER_COMPILE_SOURCES
      "${CMAKE_CURRENT_SOURCE_DIR}/platform/platform.c"
      "${CMAKE_CURRENT_SOURCE_DIR}/ov5640/OV5640.cpp"
  )
  set(USER_INCLUDE_DIRECTORIES
      "${CMAKE_CURRENT_SOURCE_DIR}/ov5640"
      "${CMAKE_CURRENT_SOURCE_DIR}/hdmi"
      "${CMAKE_CURRENT_SOURCE_DIR}/platform"
  )
  ```

### 坑 4：XPAR_* 常數全部改名（SDT mode）
- **問題**：大量 `was not declared in this scope` 編譯錯誤
- **原因**：Vitis 2025.2 啟用 SDT（System Device Tree），`*_LookupConfig()` 改用 base address 而非整數 device ID
- **解法**：建立 `src/xparameters_compat.h`，並在 `main.cc` 改 include：

  | 舊名（2019.1） | 新名（2025.2） |
  |----------------|----------------|
  | `XPAR_PS7_SCUGIC_0_DEVICE_ID` | `XPAR_XSCUGIC_0_BASEADDR` |
  | `XPAR_PS7_GPIO_0_DEVICE_ID` | `XPAR_XGPIOPS_0_BASEADDR` |
  | `XPAR_PS7_GPIO_0_INTR` | `52U`（GIC SPI #52，硬體不變） |
  | `XPAR_PS7_I2C_0_DEVICE_ID` | `XPAR_XIICPS_0_BASEADDR` |
  | `XPAR_PS7_I2C_0_INTR` | `57U`（GIC SPI #57，硬體不變） |
  | `XPAR_AXIVDMA_0_DEVICE_ID` | `XPAR_AXI_VDMA_0_BASEADDR` |
  | `XPAR_FABRIC_AXI_VDMA_0_MM2S_INTROUT_INTR` | `XPAR_FABRIC_AXI_VDMA_0_INTR` |
  | `XPAR_FABRIC_AXI_VDMA_0_S2MM_INTROUT_INTR` | `XPAR_FABRIC_AXI_VDMA_0_INTR_1` |
  | `XPAR_VTC_0_DEVICE_ID` | `XPAR_XVTC_0_BASEADDR` |
  | `XPAR_VIDEO_DYNCLK_DEVICE_ID` | `XPAR_VIDEO_DYNCLK_BASEADDR` |
  | `XPAR_DDR_MEM_BASEADDR` | `XPAR_PS7_DDR_0_BASEADDRESS` |
  | `XPAR_MIPI_CSI_2_RX_0_S_AXI_LITE_BASEADDR` | `XPAR_MIPI_CSI_2_RX_0_BASEADDR` |
  | `XPAR_MIPI_D_PHY_RX_0_S_AXI_LITE_BASEADDR` | `XPAR_MIPI_D_PHY_RX_0_BASEADDR` |

### 坑 5：Digilent wrapper 型別溢位
- **問題**：`conversion from 'unsigned int' to 'uint16_t' changes value` warning，執行期 LookupConfig 失敗
- **原因**：Digilent wrapper class 的 constructor 參數是 `uint16_t`，但新版要傳入 32-bit base address
- **解法**：把以下 header 的 `uint16_t dev_id` 改成 `UINTPTR dev_id`
  - `ScuGicInterruptController.h`
  - `PS_GPIO.h`
  - `PS_IIC.h`
  - `AXI_VDMA.h`（同時把 `uint16_t rd_irpt_id, wr_irpt_id` 改成 `uint32_t`）

### 坑 6：ps7_init 找不到
- **問題**：`invalid command name "ps7_init"`
- **原因**：Vitis 沒有自動找到 PS 初始化 TCL 腳本
- **解法**：`Run → Run Configurations → Target Setup → PS Initialization file`，填入：
  ```
  C:\vitis_workspace\Project_zyboz7_pcam\app_pcam\_ide\psinit\ps7_init.tcl
  ```

---

## 5. 驗證結果

### OV5640 Chip ID 確認
UART 連接（baud rate 115200），在 menu 按 `f`：
```
輸入 300a → 回傳 56  ✓
輸入 300b → 回傳 40  ✓
```
完整 chip ID = `0x5640` = OV5640，PCAM 接通，I2C 正常。

### HDMI 確認
螢幕有即時相機畫面，pipeline 全通。

**結論：PCAM 驗證通過。**

---

## 6. Demo 資源基線

加入自訂模組前的參考數據（Zybo Z7-20 / xc7z020）：

| 資源 | 使用量 | 可用量 | 使用率 |
|------|--------|--------|--------|
| LUT | 7,896 | 53,200 | 14.84% |
| Flip-Flop | 10,965 | 106,400 | 10.31% |
| Slice | 3,975 | 13,300 | 29.89% |
| BRAM 36K | 8 | 140 | 5.71% |
| DSP | 0 | 220 | 0% |
| MMCM | 2 | 4 | 50% |

| 功耗項目 | 數值 |
|----------|------|
| 總功耗 | 1.931 W |
| 動態功耗 | 1.779 W |
| 晶片溫度 | 47.3°C |

**結論**：LUT 只用 15%，DSP 完全空著，加自訂影像處理模組資源完全充裕。MMCM 用了 50%，新增時鐘源要注意（還剩 2 顆）。

---

## 7. 這次的貢獻點

- 完成 Vivado 2019.1 → 2025.2 的移植（無現成教學，全靠錯誤訊息推導）
- 建立 Vitis 2025.2 SDT mode 完整相容修改清單，可重複使用
- 確認 Zybo Z7-20 + PCAM 5C 在新工具鏈下硬體正常
- 建立資源使用基線，提供後續判斷依據

---

## 8. 如何接著用

已完成的部分不需要重做，直接在上面加：

| 項目 | 位置 | 下一步怎麼改 |
|------|------|-------------|
| Vivado 專案 | `C:\pcam\` | 在 Block Design 加入自訂 AXI-Stream IP |
| Vitis 專案 | `C:\vitis_workspace\Project_zyboz7_pcam\` | 加功能只需改 `main.cc` |
| SDT 相容層 | `src/xparameters_compat.h` | 新 IP 的 base address 直接加進去 |
| CMake 來源 | `src/UserConfig.cmake` | 新 .cpp 加一行 `USER_COMPILE_SOURCES` |
| 插入點 | GammaCorrection 輸出 → VDMA 輸入 | 資料格式：AXI-Stream RGB888（24-bit） |
