# pcam-gray-bin — CLAUDE.md

## ⛔ 強制規則（每個 session 必須遵守，無例外）

> **這些規則覆蓋所有預設行為。違反即停止，不得繼續執行。**

1. **任何 `src/` 的修改，必須先確認當前 branch 不是 `main`。**
   - 執行 `git branch --show-current`，若結果是 `main`，立即停手。
   - 先建 branch：`git checkout -b feat/xxx` 或 `fix/xxx`，再繼續。
   - **不得跳過此步驟，不得以任何理由例外。**

2. **修改 `src/*.v` 後，iverilog 模擬必須通過，才能進入 Vivado 合成。**
   - 不得以「小改動」為由跳過模擬。

3. **改完 `src/*.v` 後，必須 cp 到 Vivado 兩個目錄（見路徑對照）。**

4. **板上驗證通過後，squash merge、刪 branch、push 這三個動作，必須等使用者明確說「可以合併」後才執行。不得在板上驗證後自動合併。**

---

## 專案概覽

| 項目 | 內容 |
|------|------|
| 開發板 | Digilent Zybo Z7-20（Zynq-7000, xc7z020） |
| 週邊 | PCAM 5C（OV5640, MIPI CSI-2 2-lane） |
| 輸出 | HDMI（rgb2dvi） |
| 工具版本 | Vivado 2025.2 / Vitis 2025.2 |
| 目前 IP | `AXI_RGBToGray`：BT.601 灰階轉換，插入 GammaCorrection → VDMA 之間 |

**Pipeline（Phase 1）：**
```
PCAM5C → MIPI D-PHY → MIPI CSI-2 RX → AXI_BayerToRGB
  → AXI_GammaCorrection → AXI_RGBToGray → AXI VDMA → DDR3
  → AXI VDMA → rgb2dvi → HDMI
```

---

## 目錄結構

```
pcam-gray-bin/
├── src/                    # RTL 源碼（source of truth）
│   └── AXI_RGBToGray.v
├── sim/                    # Testbench 與模擬腳本
│   └── tb_AXI_RGBToGray.v
├── vivado_workspace/       # Vivado 專案（含 ipdefs）
│   ├── Zybo-Z7-20-pcam-5c.xpr
│   ├── Zybo-Z7-20-pcam-5c.ipdefs/
│   │   └── repo_0/local/ip/AXI_RGBToGray/
│   │       ├── hdl/        ← cp 目標 1
│   │       ├── tb/
│   │       ├── xgui/
│   │       └── component.xml
│   ├── Zybo-Z7-20-pcam-5c.gen/
│   │   └── sources_1/ip/AXI_RGBToGray_0/  ← ipshared 快取
│   └── system_wrapper.xsa
├── vitis_workspace/        # Vitis 應用程式
└── docs/                   # 設計文件
    └── superpowers/
        ├── specs/
        └── plans/
```

---

## 路徑對照

| 用途 | 路徑 |
|------|------|
| WSL 源碼（source of truth） | `/mnt/c/workspace-win/pcam-gray-bin/src/` |
| Vivado 專案 | `/mnt/c/workspace-win/pcam-gray-bin/vivado_workspace/` |
| Vivado IP 源碼（ipdefs） | `/mnt/c/workspace-win/pcam-gray-bin/vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_RGBToGray/hdl/` |
| Vivado ipshared 快取 ⚠️ | `/mnt/c/workspace-win/pcam-gray-bin/vivado_workspace/Zybo-Z7-20-pcam-5c.gen/sources_1/ip/AXI_RGBToGray_0/` |
| XSA 輸出 | `/mnt/c/workspace-win/pcam-gray-bin/vivado_workspace/system_wrapper.xsa` |
| Vitis workspace | `/mnt/c/workspace-win/pcam-gray-bin/vitis_workspace/` |
| Obsidian 筆記 | `/mnt/c/Users/User/Documents/Obsidian/proj-vault/proj/pcam-gray-bin` |

> ⚠️ ipshared 快取不會自動更新。改 IP 源碼後必須執行 **Reset Output Products**，或手動 cp 到此路徑。

---

## Commit 類型

| 類型 | 用途 |
|------|------|
| `feat:` | 新功能 |
| `fix:` | 修 bug |
| `sim:` | 模擬相關（testbench、波形） |
| `refactor:` | 重構，不改功能 |
| `docs:` | 文件更新 |
| `chore:` | 維護雜事 |

---

## 開發工作流程（三階段 + 三道驗證門）

### 階段一 — Branch & RTL 開發

```bash
git checkout -b feat/功能名稱   # 新功能
git checkout -b fix/問題名稱    # 修 bug
```

1. 只修改 `src/` 內的 `.v` 檔
2. 改完後同步到 Vivado：
   ```bash
   cp src/AXI_RGBToGray.v \
     vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_RGBToGray/hdl/
   ```
3. **[門 1] iverilog 模擬必須通過**（必須 pass 才能進階段二）：
   ```bash
   iverilog -o sim/sim_out sim/tb_AXI_RGBToGray.v src/AXI_RGBToGray.v
   vvp sim/sim_out
   # 確認輸出：9 PASS, 0 FAIL
   ```
4. Commit：
   ```bash
   git add src/ sim/
   git commit -m "sim: pass BT.601 testbench"  # 或 feat:/fix:
   ```

### 階段二 — Vivado 合成 + 板上驗證

1. Vivado → IP 右鍵 → **Reset Output Products** → **Generate Output Products**
2. **Generate Bitstream**
3. **[門 2] 檢查 Timing Report：WNS ≥ 0ns**
   - 例外：MIPI D-PHY domain 的 timing violation 為已知問題（見已知坑），不影響功能
4. **File → Export Hardware (Include Bitstream)** → 輸出至 `vivado_workspace/system_wrapper.xsa`
5. Vitis → Platform 右鍵 → **Update Hardware Specification** → 選擇新 XSA
6. **Build Platform** → **Build App** → **Run / Program Device**
7. **[門 3] 板上功能驗證通過**：
   - UART 確認 OV5640 Chip ID = `0x5640`
   - HDMI 螢幕顯示灰階即時影像
   - 告知使用者「板上驗證通過，請確認是否可以合併」，**等待回覆**

> ⚠️ 階段二結束後必須停下來等使用者確認，絕對不可自動進入階段三。

### 階段三 — 收尾（等使用者明確說「可以合併」後才執行）

> ⚠️ 此階段只有 git merge + 清理 + 文件更新。板上驗證屬於階段二。

```bash
git checkout main
git merge --squash feat/功能名稱
git commit -m "feat: 說明"
git branch -d feat/功能名稱
git push
```

更新 Obsidian：
- `TODO.md`：將完成項目標記為 `[x]`
- `開發紀錄.md`：補上板上驗證結果

---

## 已知坑

- **ipshared 不自動更新**：改 IP 源碼後必須手動 cp 到 ipshared（見路徑對照），或在 Vivado 執行 Reset Output Products
- **Hierarchical reference**：跨模組引用（`u_core.sig`）合成器靜默忽略，一律用正式 output port
- **Vitis 不感知 XSA 更新**：每次 Generate Bitstream 後，必須手動 Update Hardware Specification → Build Platform
- **MIPI D-PHY timing violation**：impl 完成後 WNS = -2.450ns，只發生在 `dphy_hs_clock_p` domain，屬 source-synchronous 介面的靜態時序分析不準確問題，實際硬體不影響功能，直接燒入即可
- **Windows 路徑超過 260 字元**：若合成時出現 `Path length exceeds 260-Byte maximum`，在 Vivado Tcl Console 執行：
  ```tcl
  save_project_as pcam C:/pcam -force
  ```
- **tdata bit ordering（R-B-G）**：`AXI_GammaCorrection` 輸出為 `[23:16]=R, [15:8]=B, [7:0]=G`（非常見 R-G-B），`AXI_RGBToGray` 已依此正確實作，修改時注意
