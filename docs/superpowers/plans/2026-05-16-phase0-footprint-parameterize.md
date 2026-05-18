# Phase 0：footprint RTL 參數化（1280x720）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 將 footprint RTL 從硬編碼 640x480 改成參數化，能跑 1280x720，舊 640x480 testbench 回歸**位元級一致**。**所有改動在 pcam-gray-bin repo 內**，原 `~/workspace/projects/footprint/` 完全不動。

**Architecture:** 從 footprint repo 複製 4 個 RTL + tb_top.v + 1 張測試圖到 pcam-gray-bin 的 `src/footprint/` 與 `sim/footprint/`；加 `WIDTH/HEIGHT` parameter 並向下傳遞；陣列尺寸與 bit width 對應放大；testbench 改為依 `WIDTH*HEIGHT` 計算 pixel 數；建立 golden baseline 後再開始改動。

**Tech Stack:** Verilog-2001、iverilog、Python（產生 1280x720 測試圖）

**對應 Spec：** `docs/superpowers/specs/2026-05-16-footprint-integration-design.md` 第 Phase 0 節

**Branch：** `feat/footprint-parameterize-1280x720`（從 pcam-gray-bin main 開）

---

## File Structure

所有路徑相對於 `/mnt/c/workspace-win/pcam-gray-bin/`：

| 檔案 | 動作 | 責任 |
|------|------|------|
| `src/footprint/cut.v` | Create | 從 footprint repo cp 後參數化 |
| `src/footprint/label3.v` | Create | 從 footprint repo cp 後改 bit width |
| `src/footprint/label2_forefoot.v` | Create | 從 footprint repo cp 後改 bit width |
| `src/footprint/footprint_top.v` | Create | 從 `top.v` 改名 cp，module name 改 `footprint_top` |
| `sim/footprint/tb_footprint_top.v` | Create | 從 `tb_top.v` 改名 cp，調用 `footprint_top` |
| `sim/footprint/input_files/input_IMG0001.txt` | Create | 640x480 baseline 測試圖 |
| `sim/footprint/input_files/input_IMG0001_1280x720.txt` | Create | Task 8 產生 |
| `scripts/gen_1280x720.py` | Create | 把 640x480 input 放大成 1280x720（nearest-neighbor） |
| `/tmp/baseline_640x480.log` | Create（不入版控） | 改動前的 12 座標 golden reference |

**重要**：
- `top.v` 改名為 `footprint_top.v` 避免與其他 IP 的 top 撞名；`module top` 改 `module footprint_top`，tb 內 instantiate 對應改
- 不複製 footprint repo 其他大檔（19 張測試圖、`output_files/`、`footdata/`、`model/` 等）
- baseline log 寫到 `/tmp/` 不放專案內，避免 git 追蹤

---

## Task 1：開 branch + cp 檔案 + 抓 baseline

**Files (create only in pcam-gray-bin)：**
- Create: `src/footprint/cut.v`
- Create: `src/footprint/label3.v`
- Create: `src/footprint/label2_forefoot.v`
- Create: `src/footprint/footprint_top.v`（從 footprint repo `top.v` 改名 + 改 module name）
- Create: `sim/footprint/tb_footprint_top.v`（從 footprint repo `tb_top.v` 改名 + 改 instantiate）
- Create: `sim/footprint/input_files/input_IMG0001.txt`
- Create: `/tmp/baseline_640x480.log`

**理由：** CLAUDE.md 規則 1 要 branch 才能改 `src/`。先建 branch、複製檔案進來、改 module 名稱、抓 baseline，後續 Task 才能改 RTL 且保有 regression 基準。

- [ ] **Step 1.1：確認當前 branch 並開 feature branch**

```bash
cd /mnt/c/workspace-win/pcam-gray-bin
git status   # 預期：clean working tree
git branch --show-current   # 預期：main
git checkout -b feat/footprint-parameterize-1280x720
git branch --show-current   # 預期：feat/footprint-parameterize-1280x720
```

- [ ] **Step 1.2：建立目錄結構**

```bash
mkdir -p src/footprint sim/footprint/input_files
ls -d src/footprint sim/footprint sim/footprint/input_files   # 確認三個目錄存在
```

- [ ] **Step 1.3：複製 RTL 與 tb**

```bash
cp ~/workspace/projects/footprint/rtl/cut.v             src/footprint/cut.v
cp ~/workspace/projects/footprint/rtl/label3.v          src/footprint/label3.v
cp ~/workspace/projects/footprint/rtl/label2_forefoot.v src/footprint/label2_forefoot.v
cp ~/workspace/projects/footprint/rtl/top.v             src/footprint/footprint_top.v
cp ~/workspace/projects/footprint/tb/tb_top.v           sim/footprint/tb_footprint_top.v
cp ~/workspace/projects/footprint/input_files/input_IMG0001.txt sim/footprint/input_files/input_IMG0001.txt
ls -l src/footprint/ sim/footprint/ sim/footprint/input_files/
```

預期：5 個 .v 檔（4 src + 1 tb）、1 個 input txt。

- [ ] **Step 1.4：把 footprint_top.v 內的 `module top` 改名為 `module footprint_top`**

用 `Edit` 工具改 `src/footprint/footprint_top.v`：

```
old_string: module top (
new_string: module footprint_top (
```

確認檔案內 `module top` 只出現一次（避免誤改）：

```bash
grep -n "^module " src/footprint/footprint_top.v
# 預期：1 行，且應為 module footprint_top (
```

- [ ] **Step 1.5：把 tb_footprint_top.v 內 instantiate `top uut` 改為 `footprint_top uut`，並改 module name `tb_top` → `tb_footprint_top`**

`sim/footprint/tb_footprint_top.v` 內：

```
old_string: module tb_top;
new_string: module tb_footprint_top;
```

與

```
old_string: top uut (
new_string: footprint_top uut (
```

驗證：

```bash
grep -n "^module " sim/footprint/tb_footprint_top.v   # 應有 tb_footprint_top
grep -n "footprint_top uut" sim/footprint/tb_footprint_top.v   # 應有 1 行
grep -n "top uut" sim/footprint/tb_footprint_top.v   # 應有 1 行（就是上面那行 footprint_top uut，因為 grep 子字串會 match）
```

- [ ] **Step 1.6：跑 baseline 模擬抓 golden reference**

```bash
cd /mnt/c/workspace-win/pcam-gray-bin/sim/footprint
cp input_files/input_IMG0001.txt input.txt
iverilog -o sim_out tb_footprint_top.v \
  ../../src/footprint/footprint_top.v \
  ../../src/footprint/cut.v \
  ../../src/footprint/label3.v \
  ../../src/footprint/label2_forefoot.v
vvp sim_out > /tmp/baseline_640x480.log
grep -A 20 "12 Key Coordinate Points" /tmp/baseline_640x480.log
```

預期：印出左腳 6 點 + 右腳 6 點座標，**所有數值非零**。

若 timeout 或無 12 Key 段落 → 報 BLOCKED。

- [ ] **Step 1.7：建立 .gitignore 條目（避免誤 commit baseline / sim 中間檔）**

確認 `.gitignore` 已含或追加：

```
# Simulation outputs
sim/**/sim_out
sim/**/sim_bin
sim/**/*.vvp
sim/**/*.vcd
sim/**/input.txt   # 臨時 cp 過去的測試圖，不入版控
```

若 `.gitignore` 已有部分項目，只追加缺漏的。

- [ ] **Step 1.8：commit 初始檔案**

```bash
cd /mnt/c/workspace-win/pcam-gray-bin
git add src/footprint/ sim/footprint/tb_footprint_top.v sim/footprint/input_files/input_IMG0001.txt .gitignore
git status   # 確認沒誤把 sim/footprint/input.txt 或 sim_out 加進去
git commit -m "feat: copy footprint RTL/tb into pcam-gray-bin for Phase 0 parameterization"
```

---

## Task 2：tb_footprint_top.v 參數化（先做 tb）

**Files:**
- Modify: `sim/footprint/tb_footprint_top.v`

**理由：** tb 是測試碼，先改不影響 RTL，是最低風險起點。要讓 tb 支援 1280x720，後面 RTL 改完才能驗證。

- [ ] **Step 2.1：加 ifdef macro 切換 WIDTH/HEIGHT**

`sim/footprint/tb_footprint_top.v` 開頭，把：

```verilog
module tb_footprint_top;

    // ========================================
```

改為：

```verilog
module tb_footprint_top;

    // 預設 640x480，可由 iverilog -DRES_1280x720 切換 1280x720
    localparam WIDTH  = `ifdef RES_1280x720 1280 `else 640  `endif;
    localparam HEIGHT = `ifdef RES_1280x720 720  `else 480  `endif;
    localparam PIXELS = WIDTH * HEIGHT;

    // ========================================
```

- [ ] **Step 2.2：把 3 處 `307200` 改為 `PIXELS`**

`tb_footprint_top.v` 內 `for (i = 0; i < 307200; i = i + 1)` 共 3 處（Phase 1/2/3 各一），全部改 `for (i = 0; i < PIXELS; i = i + 1)`。

`$display` 中含 `307200` 的字串與計算（如 `(i * 100.0) / 307200`）也對應改用 `PIXELS`。

驗證：

```bash
grep -c "307200" sim/footprint/tb_footprint_top.v   # 預期：0
grep -c "PIXELS" sim/footprint/tb_footprint_top.v   # 預期：≥ 6（3 個 for + 3 個 display）
```

- [ ] **Step 2.3：放寬 RESET 等待與超時保護**

把：
```verilog
        // 最長需要 640 cycles = 6400ns
        #7000;
```
改為：
```verilog
        // 最長需要 WIDTH cycles for cut.v RESET
        #(WIDTH * 12 + 1000);
```

把：
```verilog
        #150000000; // 150ms 超時 (增加時間因為有第三階段)
```
改為：
```verilog
        #(PIXELS * 60); // 約 3x PIXELS cycles 緩衝
```

- [ ] **Step 2.4：跑 640x480 回歸確認 tb 沒搞壞**

```bash
cd /mnt/c/workspace-win/pcam-gray-bin/sim/footprint
cp input_files/input_IMG0001.txt input.txt
iverilog -o sim_out tb_footprint_top.v \
  ../../src/footprint/footprint_top.v ../../src/footprint/cut.v \
  ../../src/footprint/label3.v ../../src/footprint/label2_forefoot.v
vvp sim_out > /tmp/tb_test.log
grep -A 20 "12 Key Coordinate Points" /tmp/tb_test.log > /tmp/tb_test_coords.log
grep -A 20 "12 Key Coordinate Points" /tmp/baseline_640x480.log > /tmp/baseline_coords.log
diff /tmp/tb_test_coords.log /tmp/baseline_coords.log
```

預期：`diff` 無輸出（位元級一致）。

- [ ] **Step 2.5：Commit**

```bash
git add sim/footprint/tb_footprint_top.v
git commit -m "sim: parameterize tb_footprint_top with WIDTH/HEIGHT macros"
```

---

## Task 3：cut.v 參數化

**Files:**
- Modify: `src/footprint/cut.v`

**理由：** cut.v 硬編碼最多（640/480/307200/320/639），先處理。

- [ ] **Step 3.1：加 parameter 到 module header**

把：
```verilog
module cut (
    input wire clk,
```
改為：
```verilog
module cut #(
    parameter WIDTH  = 640,
    parameter HEIGHT = 480
)(
    input wire clk,
```

- [ ] **Step 3.2：加 localparam 計算衍生常數**

在 module port 宣告之後、`reg [8:0] col_count` 之前，加：

```verilog
    localparam PIXELS    = WIDTH * HEIGHT;
    localparam COL_BITS  = $clog2(WIDTH);
    localparam ROW_BITS  = $clog2(HEIGHT);
    localparam PIX_BITS  = $clog2(PIXELS + 1);
    localparam CNT_BITS  = $clog2(HEIGHT + 1);
    localparam HALF_W    = WIDTH >> 1;
```

- [ ] **Step 3.3：陣列與 reg 寬度全部改成 parameter 化**

| 原宣告 | 改為 |
|--------|------|
| `reg [8:0] col_count [0:639];` | `reg [CNT_BITS-1:0] col_count [0:WIDTH-1];` |
| `reg [18:0] pixel_count;` | `reg [PIX_BITS-1:0] pixel_count;` |
| `reg [9:0] current_col;` | `reg [COL_BITS-1:0] current_col;` |
| `reg [8:0] current_row;` | `reg [ROW_BITS-1:0] current_row;` |
| `reg [9:0] search_col;` | `reg [COL_BITS-1:0] search_col;` |
| `reg [9:0] max_col_left;` | `reg [COL_BITS-1:0] max_col_left;` |
| `reg [8:0] max_val_left;` | `reg [CNT_BITS-1:0] max_val_left;` |
| `reg [9:0] max_col_right;` | `reg [COL_BITS-1:0] max_col_right;` |
| `reg [8:0] max_val_right;` | `reg [CNT_BITS-1:0] max_val_right;` |
| `reg [9:0] reset_idx;` | `reg [COL_BITS-1:0] reset_idx;` |

並把 module output port：
```verilog
    output reg [9:0] x_cut,
    output reg [9:0] r_high,
    output reg [9:0] l_high
```
改為：
```verilog
    output reg [COL_BITS-1:0] x_cut,
    output reg [COL_BITS-1:0] r_high,
    output reg [COL_BITS-1:0] l_high
```

- [ ] **Step 3.4：硬編碼數字改 parameter**

| 原始 | 改為 | 位置 |
|------|------|------|
| `639`（4 處：RESET 結束、RECEIVE current_col 換行、FIND_PEAK 結束、相關註解） | `WIDTH-1` | always 區塊內 |
| `307200`（RECEIVE pixel_count 比對） | `PIXELS` | always 區塊內 |
| `320`（FIND_PEAK 左右半邊分界） | `HALF_W` | always 區塊內 |

註解中的 `(0-639)`、`(0-479)`、`最大480` 也順手更新。

- [ ] **Step 3.5：跑 640x480 回歸驗證 cut.v 沒搞壞**

```bash
cd /mnt/c/workspace-win/pcam-gray-bin/sim/footprint
cp input_files/input_IMG0001.txt input.txt
iverilog -o sim_out tb_footprint_top.v \
  ../../src/footprint/footprint_top.v ../../src/footprint/cut.v \
  ../../src/footprint/label3.v ../../src/footprint/label2_forefoot.v
vvp sim_out > /tmp/cut_test.log
grep -A 20 "12 Key Coordinate Points" /tmp/cut_test.log > /tmp/cut_coords.log
diff /tmp/cut_coords.log /tmp/baseline_coords.log
```

預期：`diff` 無輸出。

> 此時 footprint_top.v 還在用「`cut u_cut (...)` 不傳 parameter」的舊呼叫法，但 cut.v default 仍是 640/480，結果不變。Task 6 才把 footprint_top.v 改為向下傳。

- [ ] **Step 3.6：Commit**

```bash
git add src/footprint/cut.v
git commit -m "feat: parameterize cut.v with WIDTH/HEIGHT (default 640/480)"
```

---

## Task 4：label3.v 改 bit width

**Files:**
- Modify: `src/footprint/label3.v`

**理由：** label3.v 已有 WIDTH/HEIGHT parameter，但 bit width 與哨兵寫死，1280 寬度會溢位。

- [ ] **Step 4.1：加 localparam（緊接 parameter 宣告之後、state 宣告之前）**

```verilog
    localparam X_BITS      = $clog2(WIDTH);
    localparam HIST_BITS   = $clog2(WIDTH + 1);
    localparam SMOOTH_BITS = $clog2(3*WIDTH + 1);
    localparam X_SENTINEL  = {X_BITS{1'b1}};
```

- [ ] **Step 4.2：陣列宣告改寬**

| 原宣告 | 改為 |
|--------|------|
| `reg [9:0] histogram   [0:HEIGHT-1];` | `reg [HIST_BITS-1:0]   histogram   [0:HEIGHT-1];` |
| `reg [10:0] smooth_hist [0:HEIGHT-1];` | `reg [SMOOTH_BITS-1:0] smooth_hist [0:HEIGHT-1];` |
| `reg [9:0] first_x [0:HEIGHT-1];` | `reg [X_BITS-1:0]      first_x [0:HEIGHT-1];` |
| `reg [9:0] last_x  [0:HEIGHT-1];` | `reg [X_BITS-1:0]      last_x  [0:HEIGHT-1];` |

- [ ] **Step 4.3：smooth_sum wire 改寬與字面常數**

把：
```verilog
    wire [10:0] smooth_sum;
    assign smooth_sum = histogram[smooth_idx] +
                        ((smooth_idx > 0) ? histogram[smooth_idx - 1] : 10'd0) +
                        ((smooth_idx < HEIGHT-1) ? histogram[smooth_idx + 1] : 10'd0);
```
改為：
```verilog
    wire [SMOOTH_BITS-1:0] smooth_sum;
    assign smooth_sum = histogram[smooth_idx] +
                        ((smooth_idx > 0) ? histogram[smooth_idx - 1] : {HIST_BITS{1'b0}}) +
                        ((smooth_idx < HEIGHT-1) ? histogram[smooth_idx + 1] : {HIST_BITS{1'b0}});
```

- [ ] **Step 4.4：哨兵 10'h3FF 全改 X_SENTINEL**

兩處：
```verilog
first_x[reset_idx] <= 10'h3FF;
...
if (first_x[row] == 10'h3FF) begin
```
改為：
```verilog
first_x[reset_idx] <= X_SENTINEL;
...
if (first_x[row] == X_SENTINEL) begin
```

- [ ] **Step 4.5：跑 640x480 回歸**

```bash
cd /mnt/c/workspace-win/pcam-gray-bin/sim/footprint
cp input_files/input_IMG0001.txt input.txt
iverilog -o sim_out tb_footprint_top.v \
  ../../src/footprint/footprint_top.v ../../src/footprint/cut.v \
  ../../src/footprint/label3.v ../../src/footprint/label2_forefoot.v
vvp sim_out > /tmp/l3_test.log
grep -A 20 "12 Key Coordinate Points" /tmp/l3_test.log > /tmp/l3_coords.log
diff /tmp/l3_coords.log /tmp/baseline_coords.log
```

預期：`diff` 無輸出。

- [ ] **Step 4.6：Commit**

```bash
git add src/footprint/label3.v
git commit -m "feat: parameterize label3.v bit widths for WIDTH up to 1280"
```

---

## Task 5：label2_forefoot.v 改 bit width

**Files:**
- Modify: `src/footprint/label2_forefoot.v`

**理由：** 同 label3.v，已有 parameter 但 9-bit 陣列與 `9'h1FF` 哨兵在 720 高度會溢位。

- [ ] **Step 5.1：加 localparam**

緊接 parameter 宣告之後：

```verilog
    localparam Y_BITS     = $clog2(HEIGHT);
    localparam VHIST_BITS = $clog2(HEIGHT + 1);
    localparam Y_SENTINEL = {Y_BITS{1'b1}};
```

- [ ] **Step 5.2：陣列改寬**

| 原宣告 | 改為 |
|--------|------|
| `reg [8:0] vertical_hist [0:WIDTH-1];` | `reg [VHIST_BITS-1:0] vertical_hist [0:WIDTH-1];` |
| `reg [8:0] first_y [0:WIDTH-1];` | `reg [Y_BITS-1:0]     first_y [0:WIDTH-1];` |
| `reg [8:0] last_y  [0:WIDTH-1];` | `reg [Y_BITS-1:0]     last_y  [0:WIDTH-1];` |

- [ ] **Step 5.3：哨兵 9'h1FF 全改 Y_SENTINEL**

兩處：
```verilog
first_y[reset_idx] <= 9'h1FF;
...
if (first_y[col] == 9'h1FF) begin
```
改為：
```verilog
first_y[reset_idx] <= Y_SENTINEL;
...
if (first_y[col] == Y_SENTINEL) begin
```

- [ ] **Step 5.4：跑 640x480 回歸**

```bash
cd /mnt/c/workspace-win/pcam-gray-bin/sim/footprint
cp input_files/input_IMG0001.txt input.txt
iverilog -o sim_out tb_footprint_top.v \
  ../../src/footprint/footprint_top.v ../../src/footprint/cut.v \
  ../../src/footprint/label3.v ../../src/footprint/label2_forefoot.v
vvp sim_out > /tmp/l2_test.log
grep -A 20 "12 Key Coordinate Points" /tmp/l2_test.log > /tmp/l2_coords.log
diff /tmp/l2_coords.log /tmp/baseline_coords.log
```

預期：`diff` 無輸出。

- [ ] **Step 5.5：Commit**

```bash
git add src/footprint/label2_forefoot.v
git commit -m "feat: parameterize label2_forefoot.v bit widths for HEIGHT up to 720"
```

---

## Task 6：footprint_top.v 加 parameter 並向下傳

**Files:**
- Modify: `src/footprint/footprint_top.v`

**理由：** 三子模組都改完，footprint_top 必須能傳遞 WIDTH/HEIGHT，並把自己內部的 `current_col[9:0]`、硬編碼 `639` 改寬。default 改為 1280x720（主要使用情境）。

- [ ] **Step 6.1：加 module parameter（並把 default 改 1280x720）**

把：
```verilog
module footprint_top (
    input wire clk,
```
改為：
```verilog
module footprint_top #(
    parameter WIDTH  = 1280,
    parameter HEIGHT = 720
)(
    input wire clk,
```

- [ ] **Step 6.2：加 localparam**

緊接 module ports 宣告之後加：
```verilog
    localparam COL_BITS = $clog2(WIDTH);
    localparam ROW_BITS = $clog2(HEIGHT);
```

- [ ] **Step 6.3：output port 寬度對應**

把：
```verilog
    output wire [9:0] x_cut,
    output wire [9:0] r_high,
    output wire [9:0] l_high,
```
改為：
```verilog
    output wire [COL_BITS-1:0] x_cut,
    output wire [COL_BITS-1:0] r_high,
    output wire [COL_BITS-1:0] l_high,
```

- [ ] **Step 6.4：內部 reg 改寬**

把：
```verilog
    reg [9:0] current_col;
    reg [8:0] current_row;
```
改為：
```verilog
    reg [COL_BITS-1:0] current_col;
    reg [ROW_BITS-1:0] current_row;
```

- [ ] **Step 6.5：三個子模組 instantiate 加 #(WIDTH, HEIGHT)**

`cut u_cut (...)` → `cut #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) u_cut (...)`

兩個 `label3 #(.WIDTH(640), .HEIGHT(480)) u_label3_xxx (...)` → `label3 #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) u_label3_xxx (...)`

兩個 `label2_forefoot #(.WIDTH(640), .HEIGHT(480)) u_label2_forefoot_xxx (...)` → `label2_forefoot #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) u_label2_forefoot_xxx (...)`

- [ ] **Step 6.6：硬編碼 639 全改 WIDTH-1**

`always` 區塊內共兩處 `if (current_col == 639) begin` 都改為 `if (current_col == WIDTH-1) begin`。

- [ ] **Step 6.7：iverilog 編譯確認（暫不跑 vvp）**

```bash
cd /mnt/c/workspace-win/pcam-gray-bin
iverilog -o /tmp/syn_check.out \
  src/footprint/footprint_top.v src/footprint/cut.v \
  src/footprint/label3.v src/footprint/label2_forefoot.v
echo "Exit: $?"
```

預期：Exit 0，無錯誤。

> 此時 tb 還沒 override top 的 parameter，跑 tb 會用 default 1280x720 但只送 307200 pixels（640x480 圖）→ 不夠，會 timeout。Task 7 處理。

- [ ] **Step 6.8：Commit**

```bash
git add src/footprint/footprint_top.v
git commit -m "feat: parameterize footprint_top.v, default 1280x720, propagate to submodules"
```

---

## Task 7：tb override footprint_top parameter + 第一道 Gate

**Files:**
- Modify: `sim/footprint/tb_footprint_top.v`

**理由：** footprint_top default 改成 1280x720 後，tb 必須在 640x480 模式時 override 回 640x480；同時改 instantiate 寫法。

- [ ] **Step 7.1：tb 內 footprint_top instantiate 加 #(WIDTH, HEIGHT)**

把：
```verilog
    footprint_top uut (
        .clk(clk),
```
改為：
```verilog
    footprint_top #(
        .WIDTH(WIDTH),
        .HEIGHT(HEIGHT)
    ) uut (
        .clk(clk),
```

- [ ] **Step 7.2：x_cut / r_high / l_high wire 改動態寬度**

tb 內：
```verilog
    wire [9:0] x_cut;
    wire [9:0] r_high;
    wire [9:0] l_high;
```
改為：
```verilog
    wire [$clog2(WIDTH)-1:0] x_cut;
    wire [$clog2(WIDTH)-1:0] r_high;
    wire [$clog2(WIDTH)-1:0] l_high;
```

- [ ] **Step 7.3：跑 640x480 位元級回歸（Gate 1）**

```bash
cd /mnt/c/workspace-win/pcam-gray-bin/sim/footprint
cp input_files/input_IMG0001.txt input.txt
iverilog -o sim_out tb_footprint_top.v \
  ../../src/footprint/footprint_top.v ../../src/footprint/cut.v \
  ../../src/footprint/label3.v ../../src/footprint/label2_forefoot.v
vvp sim_out > /tmp/top_test.log
grep -A 20 "12 Key Coordinate Points" /tmp/top_test.log > /tmp/top_coords.log
diff /tmp/top_coords.log /tmp/baseline_coords.log
```

**預期：`diff` 無輸出（位元級一致）**。這是 Phase 0 第一道 Gate，所有 RTL 改完後 640x480 必須 0 誤差。

- [ ] **Step 7.4：Commit**

```bash
git add sim/footprint/tb_footprint_top.v
git commit -m "sim: override footprint_top parameters in tb, complete 640x480 regression"
```

---

## Task 8：產生 1280x720 測試圖

**Files:**
- Create: `scripts/gen_1280x720.py`
- Create: `sim/footprint/input_files/input_IMG0001_1280x720.txt`

**理由：** 沒有現成 1280x720 測試圖，最簡單做法是把 640x480 nearest-neighbor 放大到 1280x720。

- [ ] **Step 8.1：寫 scripts/gen_1280x720.py**

```python
#!/usr/bin/env python3
"""把 640x480 二值化文字檔放大成 1280x720（nearest-neighbor）。

Usage: python3 gen_1280x720.py <input_640x480.txt> <output_1280x720.txt>
"""
import sys

SRC_W, SRC_H = 640, 480
DST_W, DST_H = 1280, 720

def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <in_640x480.txt> <out_1280x720.txt>", file=sys.stderr)
        sys.exit(1)

    src_path, dst_path = sys.argv[1], sys.argv[2]
    with open(src_path) as f:
        pixels = [int(line.strip()) for line in f if line.strip() != ""]
    assert len(pixels) == SRC_W * SRC_H, f"Expected {SRC_W*SRC_H} pixels, got {len(pixels)}"

    src = [pixels[r*SRC_W:(r+1)*SRC_W] for r in range(SRC_H)]

    with open(dst_path, "w") as f:
        for y in range(DST_H):
            sy = (y * SRC_H) // DST_H
            for x in range(DST_W):
                sx = (x * SRC_W) // DST_W
                f.write(f"{src[sy][sx]}\n")

    print(f"Wrote {dst_path} ({DST_W * DST_H} pixels)")

if __name__ == "__main__":
    main()
```

- [ ] **Step 8.2：產生 1280x720 測試圖**

```bash
cd /mnt/c/workspace-win/pcam-gray-bin
python3 scripts/gen_1280x720.py \
  sim/footprint/input_files/input_IMG0001.txt \
  sim/footprint/input_files/input_IMG0001_1280x720.txt
wc -l sim/footprint/input_files/input_IMG0001_1280x720.txt
# 預期：921600
```

- [ ] **Step 8.3：Commit**

```bash
git add scripts/gen_1280x720.py sim/footprint/input_files/input_IMG0001_1280x720.txt
git commit -m "feat: add 1280x720 test vector generator and first test image"
```

---

## Task 9：跑 1280x720 模擬 + 座標檢查（Gate 2）

**Files:**
- 不改檔，只跑模擬

- [ ] **Step 9.1：cp 1280x720 input 到 sim 目錄**

```bash
cd /mnt/c/workspace-win/pcam-gray-bin/sim/footprint
cp input_files/input_IMG0001_1280x720.txt input.txt
wc -l input.txt
# 預期：921600
```

- [ ] **Step 9.2：iverilog 帶 macro 編譯 1280x720 mode**

```bash
iverilog -DRES_1280x720 -o sim_out tb_footprint_top.v \
  ../../src/footprint/footprint_top.v ../../src/footprint/cut.v \
  ../../src/footprint/label3.v ../../src/footprint/label2_forefoot.v
echo "Exit: $?"
```

預期：Exit 0，無 warning。

- [ ] **Step 9.3：跑模擬（可能數十秒至幾分鐘）**

```bash
vvp sim_out > /tmp/sim_1280x720.log
echo "Exit: $?"
tail -50 /tmp/sim_1280x720.log
```

預期：Exit 0、無 TIMEOUT、結尾有 "SIMULATION COMPLETE" 與 12 Key Coordinate Points。

- [ ] **Step 9.4：肉眼檢查座標合理性**

```bash
grep -A 20 "12 Key Coordinate Points" /tmp/sim_1280x720.log
```

人工檢查：

| 檢查項 | 預期 |
|--------|------|
| 所有 X 座標 | 在 `[0, 1279]` 範圍 |
| 所有 Y 座標 | 在 `[0, 719]` 範圍 |
| 左腳 X 都 `< x_cut` | 從 log 開頭抓 x_cut 值對比 |
| 右腳 X 都 `>= x_cut` | 同上 |
| toe_y < heel_y | 兩腳皆成立 |
| 與 640x480 結果比例 | x ≈ 2x、y ≈ 1.5x |

- [ ] **Step 9.5：再跑一次 640x480 確認沒回歸**

```bash
cp input_files/input_IMG0001.txt input.txt
iverilog -o sim_out tb_footprint_top.v \
  ../../src/footprint/footprint_top.v ../../src/footprint/cut.v \
  ../../src/footprint/label3.v ../../src/footprint/label2_forefoot.v
vvp sim_out > /tmp/final_640.log
grep -A 20 "12 Key Coordinate Points" /tmp/final_640.log > /tmp/final_640_coords.log
diff /tmp/final_640_coords.log /tmp/baseline_coords.log
```

預期：`diff` 無輸出。

- [ ] **Step 9.6：working tree 確認 clean**

```bash
cd /mnt/c/workspace-win/pcam-gray-bin
git status
# 預期：clean（sim 中間檔被 .gitignore 排除）
```

---

## Task 10（選擇性）：多張 640x480 回歸

**Files:**
- 不改檔，跑多張驗證

- [ ] **Step 10.1：cp 多張 input 跑回歸**

從 footprint repo 暫時 cp 多張到 sim/footprint/input_files/（測完不入版控）：

```bash
cd /mnt/c/workspace-win/pcam-gray-bin/sim/footprint
for IMG in 0002 0005 0010; do
  cp ~/workspace/projects/footprint/input_files/input_IMG${IMG}.txt input.txt
  iverilog -o sim_out tb_footprint_top.v \
    ../../src/footprint/footprint_top.v ../../src/footprint/cut.v \
    ../../src/footprint/label3.v ../../src/footprint/label2_forefoot.v
  echo "=== input_IMG${IMG} ==="
  vvp sim_out | grep -A 20 "12 Key Coordinate Points"
done
```

預期：每張都印出 12 點且座標範圍合理。

可跳過直接進 Task 11。

---

## Task 11：收尾 smoke test + 等使用者確認

- [ ] **Step 11.1：git log 確認所有 commit 在 branch 上**

```bash
cd /mnt/c/workspace-win/pcam-gray-bin
git log --oneline main..HEAD
# 預期：能看到 Task 1-9 共 ~8 個 commit
```

- [ ] **Step 11.2：final smoke test（640 + 1280）**

```bash
cd /mnt/c/workspace-win/pcam-gray-bin/sim/footprint

# 640x480
cp input_files/input_IMG0001.txt input.txt
iverilog -o sim_out tb_footprint_top.v \
  ../../src/footprint/footprint_top.v ../../src/footprint/cut.v \
  ../../src/footprint/label3.v ../../src/footprint/label2_forefoot.v
vvp sim_out > /tmp/smoke_640.log
echo "640x480 exit: $?"

# 1280x720
cp input_files/input_IMG0001_1280x720.txt input.txt
iverilog -DRES_1280x720 -o sim_out tb_footprint_top.v \
  ../../src/footprint/footprint_top.v ../../src/footprint/cut.v \
  ../../src/footprint/label3.v ../../src/footprint/label2_forefoot.v
vvp sim_out > /tmp/smoke_1280.log
echo "1280x720 exit: $?"

grep -c "12 Key Coordinate" /tmp/smoke_640.log /tmp/smoke_1280.log
```

預期：兩個 exit 0，兩個 log 各有 1 個 "12 Key Coordinate" 段落。

- [ ] **Step 11.3：報告使用者**

向使用者報告：
- 已完成檔案改動列表
- 640x480 回歸位元級一致
- 1280x720 第一張測試圖座標合理
- branch 上有約 8 個 commit
- **不要自動 merge 或 push，等使用者確認**

---

## Self-Review

**1. Spec 覆蓋**：
- [x] 4 RTL 改動 + 1 tb 改動：Task 3/4/5/6 + Task 2/7
- [x] 1280x720 測試向量：Task 8
- [x] iverilog 編譯無 warning：每 Task 都有編譯步驟
- [x] 640x480 回歸位元級一致：Task 2/3/4/5/7/9 都有 diff 比對
- [x] 1280x720 座標肉眼合理：Task 9.4
- [x] module 改名 `top` → `footprint_top`：Task 1.4/1.5

**2. CLAUDE.md 規則一致性**：
- [x] 規則 1（branch）：Task 1.1
- [x] 規則 2（iverilog 必須過）：每 Task 都有
- [x] 規則 3（cp Vivado 兩目錄）：本 Phase 不適用（純模擬）
- [x] 規則 4（不自動 merge）：Task 11.3

**3. 命名一致性**：
- `WIDTH/HEIGHT` parameter、`COL_BITS/ROW_BITS/HIST_BITS/SMOOTH_BITS/X_BITS/Y_BITS/VHIST_BITS`、`X_SENTINEL/Y_SENTINEL` 全 plan 一致

---

## Execution Handoff

Plan saved at `docs/superpowers/plans/2026-05-16-phase0-footprint-parameterize.md`. Use subagent-driven-development to execute.
