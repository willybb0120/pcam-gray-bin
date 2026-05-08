# AXI_ImageModeSelect Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a single AXI video IP controlled by one button to cycle HDMI output through original color, grayscale, and binarized grayscale.

**Architecture:** Add `AXI_ImageModeSelect`, a 24-bit AXI4-Stream video transform with one AXI-Lite control register at offset `0x00`. The IP replaces the current `AXI_RGBToGray -> AXI_Binarize` chain in Block Design while keeping the old IP source files for reference and rollback.

**Tech Stack:** Verilog 2001, iverilog/vvp, Vivado 2025.2 Tcl/IP packager, Vitis 2025.2 C++, Zybo Z7-20, PCAM 5C.

**Spec:** `docs/superpowers/specs/2026-05-05-image-mode-select-design.md`

---

## File Structure

| Path | Action | Responsibility |
|------|--------|----------------|
| `src/AXI_ImageModeSelect.v` | Create | RTL source of truth: AXI-Stream transform + AXI-Lite mode register |
| `sim/tb_AXI_ImageModeSelect.v` | Create | iverilog testbench covering modes, AXI-Lite writes, stream sidebands, and backpressure |
| `scripts/pkg_axi_image_mode_select.tcl` | Create | Repeatable Vivado IP packaging script |
| `vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_ImageModeSelect/hdl/AXI_ImageModeSelect.v` | Create by copy | Vivado IP hdl source |
| `vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_ImageModeSelect/component.xml` | Generate | IP metadata |
| `vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_ImageModeSelect/xgui/AXI_ImageModeSelect_v1_0.tcl` | Generate | IP GUI metadata |
| `vivado_workspace/Zybo-Z7-20-pcam-5c.srcs/constrs_1/imports/constraints/ZyboZ7_A.xdc` | Modify | Enable `btn[0]` K18 constraint |
| `vivado_workspace/Zybo-Z7-20-pcam-5c.srcs/sources_1/bd/system/system.bd` | Modify in Vivado | Replace old stream chain with new IP, add AXI GPIO for `btn[0]` |
| `vitis_workspace/app_gray/src/xparameters_compat.h` | Modify after XSA update | Add compatibility macros with explicit `#error` fallbacks for new ImageMode and AXI GPIO base addresses |
| `vitis_workspace/app_gray/src/main.cc` | Modify | Initialize mode register, replace the blocking UART menu with a live button polling loop, cycle mode |

## Task 1: Branch and Baseline Check

**Files:** none

- [ ] **Step 1: Confirm branch is not `main`**

Run:

```bash
git branch --show-current
```

Expected:

```text
feat/image-mode-select
```

If output is `main`, stop. Create the feature branch before modifying `src/`.

- [ ] **Step 2: Confirm clean worktree**

Run:

```bash
git status --short
```

Expected: no output.

- [ ] **Step 3: Run existing RTL simulations for baseline**

Run:

```bash
iverilog -o sim/sim_gray sim/tb_AXI_RGBToGray.v src/AXI_RGBToGray.v
vvp sim/sim_gray
iverilog -o sim/sim_bin sim/tb_AXI_Binarize.v src/AXI_Binarize.v
vvp sim/sim_bin
```

Expected:

```text
=== Results: 9 PASS, 0 FAIL ===
SIMULATION PASSED
=== Results: 9 PASS, 0 FAIL ===
SIMULATION PASSED
```

Do not proceed if either simulation fails.

## Task 2: TDD Testbench for `AXI_ImageModeSelect`

**Files:**
- Create: `sim/tb_AXI_ImageModeSelect.v`
- Later implementation target: `src/AXI_ImageModeSelect.v`

- [ ] **Step 1: Create the failing testbench**

Create `sim/tb_AXI_ImageModeSelect.v` with tests for default original mode, AXI-Lite mode writes, grayscale, binarization, sidebands, invalid cycles, and backpressure. Use this structure:

```verilog
`timescale 1ns / 1ps

module tb_AXI_ImageModeSelect;

reg StreamClk = 0;
reg AxiLiteClk = 0;
reg sStreamReset_n = 0;
reg aAxiLiteReset_n = 0;

reg [23:0] s_tdata = 0;
reg        s_tvalid = 0;
reg        s_tuser = 0;
reg        s_tlast = 0;
reg        m_tready = 1;
wire       s_tready;
wire [23:0] m_tdata;
wire       m_tvalid;
wire       m_tuser;
wire       m_tlast;

reg [3:0]  awaddr = 0;
reg        awvalid = 0;
wire       awready;
reg [31:0] wdata = 0;
reg [3:0]  wstrb = 4'hF;
reg        wvalid = 0;
wire       wready;
wire [1:0] bresp;
wire       bvalid;
reg        bready = 0;
reg [3:0]  araddr = 0;
reg        arvalid = 0;
wire       arready;
wire [31:0] rdata;
wire [1:0] rresp;
wire       rvalid;
reg        rready = 0;

AXI_ImageModeSelect dut (
    .StreamClk(StreamClk),
    .sStreamReset_n(sStreamReset_n),
    .AxiLiteClk(AxiLiteClk),
    .aAxiLiteReset_n(aAxiLiteReset_n),
    .s_axis_video_tready(s_tready),
    .s_axis_video_tdata(s_tdata),
    .s_axis_video_tvalid(s_tvalid),
    .s_axis_video_tuser(s_tuser),
    .s_axis_video_tlast(s_tlast),
    .m_axis_video_tready(m_tready),
    .m_axis_video_tdata(m_tdata),
    .m_axis_video_tvalid(m_tvalid),
    .m_axis_video_tuser(m_tuser),
    .m_axis_video_tlast(m_tlast),
    .s_axi_awaddr(awaddr),
    .s_axi_awvalid(awvalid),
    .s_axi_awready(awready),
    .s_axi_wdata(wdata),
    .s_axi_wstrb(wstrb),
    .s_axi_wvalid(wvalid),
    .s_axi_wready(wready),
    .s_axi_bresp(bresp),
    .s_axi_bvalid(bvalid),
    .s_axi_bready(bready),
    .s_axi_araddr(araddr),
    .s_axi_arvalid(arvalid),
    .s_axi_arready(arready),
    .s_axi_rdata(rdata),
    .s_axi_rresp(rresp),
    .s_axi_rvalid(rvalid),
    .s_axi_rready(rready)
);

always #5 StreamClk = ~StreamClk;
always #5 AxiLiteClk = ~AxiLiteClk;

integer pass_cnt = 0;
integer fail_cnt = 0;

task check_pixel;
    input [23:0] expected;
    input [7:0] test_num;
    begin
        if (m_tdata === expected && m_tvalid === 1'b1) begin
            $display("PASS Test %0d: out=0x%06X", test_num, m_tdata);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("FAIL Test %0d: expected 0x%06X valid=1, got 0x%06X valid=%b",
                     test_num, expected, m_tdata, m_tvalid);
            fail_cnt = fail_cnt + 1;
        end
    end
endtask

task axi_write;
    input [3:0] addr;
    input [31:0] data;
    begin
        @(posedge AxiLiteClk);
        awaddr <= addr;
        wdata <= data;
        awvalid <= 1'b1;
        wvalid <= 1'b1;
        bready <= 1'b1;
        wait (awready && wready);
        @(posedge AxiLiteClk);
        awvalid <= 1'b0;
        wvalid <= 1'b0;
        wait (bvalid);
        @(posedge AxiLiteClk);
        bready <= 1'b0;
        repeat (3) @(posedge StreamClk);
    end
endtask

initial begin
    repeat (4) @(posedge StreamClk);
    sStreamReset_n = 1'b1;
    aAxiLiteReset_n = 1'b1;
    repeat (4) @(posedge StreamClk);

    s_tdata = 24'hAA55CC; s_tvalid = 1'b1; s_tuser = 1'b1; s_tlast = 1'b0;
    @(posedge StreamClk); #1;
    check_pixel(24'hAA55CC, 8'd1);

    axi_write(4'h0, 32'd1);
    s_tdata = 24'hFF0000; s_tvalid = 1'b1; s_tuser = 1'b0; s_tlast = 1'b0;
    @(posedge StreamClk); #1;
    check_pixel(24'h4C4C4C, 8'd2);

    s_tdata = 24'h0000FF;
    @(posedge StreamClk); #1;
    check_pixel(24'h959595, 8'd3);

    s_tdata = 24'h00FF00;
    @(posedge StreamClk); #1;
    check_pixel(24'h1C1C1C, 8'd4);

    axi_write(4'h0, 32'd2);
    s_tdata = 24'h808080;
    @(posedge StreamClk); #1;
    check_pixel(24'hFFFFFF, 8'd5);

    s_tdata = 24'h7F7F7F;
    @(posedge StreamClk); #1;
    check_pixel(24'h000000, 8'd6);

    s_tdata = 24'h818181;
    @(posedge StreamClk); #1;
    check_pixel(24'hFFFFFF, 8'd7);

    axi_write(4'h0, 32'd3);
    s_tdata = 24'h123456; s_tuser = 1'b1; s_tlast = 1'b1;
    @(posedge StreamClk); #1;
    check_pixel(24'h123456, 8'd8);

    if (m_tuser === 1'b1 && m_tlast === 1'b1) begin
        $display("PASS Test 9: tuser/tlast pass-through");
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("FAIL Test 9: tuser=%b tlast=%b", m_tuser, m_tlast);
        fail_cnt = fail_cnt + 1;
    end

    s_tvalid = 1'b0; s_tuser = 1'b0; s_tlast = 1'b0;
    @(posedge StreamClk); #1;
    if (m_tvalid === 1'b0) begin
        $display("PASS Test 10: invalid propagated");
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("FAIL Test 10: expected m_tvalid=0, got %b", m_tvalid);
        fail_cnt = fail_cnt + 1;
    end

    axi_write(4'h0, 32'd0);
    m_tready = 1'b1;
    s_tdata = 24'hABCDEF; s_tvalid = 1'b1;
    @(posedge StreamClk); #1;
    m_tready = 1'b0;
    s_tdata = 24'h000000;
    @(posedge StreamClk); #1;
    if (m_tdata === 24'hABCDEF) begin
        $display("PASS Test 11: backpressure holds output");
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("FAIL Test 11: expected held 0xABCDEF, got 0x%06X", m_tdata);
        fail_cnt = fail_cnt + 1;
    end
    m_tready = 1'b1;

    $display("=== Results: %0d PASS, %0d FAIL ===", pass_cnt, fail_cnt);
    if (fail_cnt > 0) $display("SIMULATION FAILED");
    else              $display("SIMULATION PASSED");
    $finish;
end

endmodule
```

- [ ] **Step 2: Run test and confirm it fails before implementation**

Run:

```bash
iverilog -o sim/sim_mode sim/tb_AXI_ImageModeSelect.v src/AXI_ImageModeSelect.v
```

Expected:

```text
src/AXI_ImageModeSelect.v: No such file or directory
```

- [ ] **Step 3: Commit failing testbench**

Run:

```bash
git add sim/tb_AXI_ImageModeSelect.v
git commit -m "sim: add image mode select testbench"
```

## Task 3: Implement `AXI_ImageModeSelect` RTL

**Files:**
- Create: `src/AXI_ImageModeSelect.v`

- [ ] **Step 1: Add RTL module**

Create `src/AXI_ImageModeSelect.v`. The module must expose these exact ports so the testbench and IP packager agree:

```verilog
module AXI_ImageModeSelect #(
    parameter [7:0] THRESHOLD = 8'd128
) (
    input wire StreamClk,
    input wire sStreamReset_n,
    input wire AxiLiteClk,
    input wire aAxiLiteReset_n,
    output wire s_axis_video_tready,
    input wire [23:0] s_axis_video_tdata,
    input wire s_axis_video_tvalid,
    input wire s_axis_video_tuser,
    input wire s_axis_video_tlast,
    input wire m_axis_video_tready,
    output reg [23:0] m_axis_video_tdata,
    output reg m_axis_video_tvalid,
    output reg m_axis_video_tuser,
    output reg m_axis_video_tlast,
    input wire [3:0] s_axi_awaddr,
    input wire s_axi_awvalid,
    output wire s_axi_awready,
    input wire [31:0] s_axi_wdata,
    input wire [3:0] s_axi_wstrb,
    input wire s_axi_wvalid,
    output wire s_axi_wready,
    output wire [1:0] s_axi_bresp,
    output reg s_axi_bvalid,
    input wire s_axi_bready,
    input wire [3:0] s_axi_araddr,
    input wire s_axi_arvalid,
    output wire s_axi_arready,
    output reg [31:0] s_axi_rdata,
    output wire [1:0] s_axi_rresp,
    output reg s_axi_rvalid,
    input wire s_axi_rready
);
```

Implementation requirements:

- `s_axis_video_tready = m_axis_video_tready`.
- AXI-Lite register `mode_reg[1:0]` resets to `0`.
- A write to address `4'h0` updates `mode_reg` with `s_axi_wdata[1:0]`.
- Unsupported AXI-Lite addresses return OKAY and read as zero.
- Synchronize `mode_reg` into `StreamClk` with two flops.
- Mode `0` outputs original `s_axis_video_tdata`.
- Mode `1` outputs `{Y, Y, Y}`.
- Mode `2` outputs `24'hFFFFFF` when `Y >= THRESHOLD`, otherwise `24'h000000`.
- Mode `3` outputs original `s_axis_video_tdata`.

- [ ] **Step 2: Run mode select simulation**

Run:

```bash
iverilog -o sim/sim_mode sim/tb_AXI_ImageModeSelect.v src/AXI_ImageModeSelect.v
vvp sim/sim_mode
```

Expected:

```text
=== Results: 11 PASS, 0 FAIL ===
SIMULATION PASSED
```

- [ ] **Step 3: Run existing RTL simulations**

Run:

```bash
iverilog -o sim/sim_gray sim/tb_AXI_RGBToGray.v src/AXI_RGBToGray.v
vvp sim/sim_gray
iverilog -o sim/sim_bin sim/tb_AXI_Binarize.v src/AXI_Binarize.v
vvp sim/sim_bin
```

Expected: both existing simulations show `9 PASS, 0 FAIL`.

- [ ] **Step 4: Commit RTL**

Run:

```bash
git add src/AXI_ImageModeSelect.v sim/tb_AXI_ImageModeSelect.v
git commit -m "feat: add AXI image mode select RTL"
```

## Task 4: Package the New IP with Tcl

**Files:**
- Create: `scripts/pkg_axi_image_mode_select.tcl`
- Create by copy: `vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_ImageModeSelect/hdl/AXI_ImageModeSelect.v`
- Generate: `vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_ImageModeSelect/component.xml`
- Generate: `vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_ImageModeSelect/xgui/AXI_ImageModeSelect_v1_0.tcl`

- [ ] **Step 1: Copy RTL to IP hdl directory**

Run:

```bash
mkdir -p vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_ImageModeSelect/hdl
cp src/AXI_ImageModeSelect.v vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_ImageModeSelect/hdl/
```

- [ ] **Step 2: Create packaging script**

Create `scripts/pkg_axi_image_mode_select.tcl` based on `scripts/pkg_axi_binarize.tcl` with:

```tcl
set proj_root "C:/workspace-win/pcam-gray-bin"
set ip_dir    "$proj_root/vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_ImageModeSelect"
set hdl_file  "$ip_dir/hdl/AXI_ImageModeSelect.v"
```

Required script differences from `pkg_axi_binarize.tcl`:

- top module is `AXI_ImageModeSelect`.
- display name is `AXI Image Mode Select`.
- infer AXI-Stream interfaces with `ipx::infer_bus_interfaces`.
- infer `StreamClk`, `sStreamReset_n`, `AxiLiteClk`, and `aAxiLiteReset_n` with singular `ipx::infer_bus_interface`.
- set `sStreamReset_n` and `aAxiLiteReset_n` polarity to `ACTIVE_LOW`.
- associate `s_axis_video` and `m_axis_video` with `StreamClk`.
- associate AXI-Lite interface with `AxiLiteClk` and `aAxiLiteReset_n`.
- set `THRESHOLD` user parameter to long range `0..255`, but do not force the HDL model parameter format to long.

- [ ] **Step 3: Package in Vivado Tcl Console**

In Vivado Tcl Console:

```tcl
source C:/workspace-win/pcam-gray-bin/scripts/pkg_axi_image_mode_select.tcl
```

Expected:

```text
AXI_ImageModeSelect packaged at:
  C:/workspace-win/pcam-gray-bin/vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_ImageModeSelect
```

- [ ] **Step 4: Verify generated IP metadata from WSL**

Run:

```bash
rg -n "s_axis_video|m_axis_video|StreamClk|sStreamReset_n|AxiLiteClk|aAxiLiteReset_n|ASSOCIATED_BUSIF|ASSOCIATED_RESET|POLARITY|THRESHOLD" vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_ImageModeSelect/component.xml
```

Expected:

- `s_axis_video` and `m_axis_video` bus interfaces exist.
- `StreamClk` and `sStreamReset_n` bus interfaces exist.
- AXI-Lite bus interface exists and is associated with `AxiLiteClk`.
- Both resets show `ACTIVE_LOW`.
- `THRESHOLD` exists as a user parameter with range `0..255`.

- [ ] **Step 5: Commit packaged IP files**

Run:

```bash
git add scripts/pkg_axi_image_mode_select.tcl vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_ImageModeSelect
git commit -m "feat: package AXI image mode select IP"
```

## Task 5: Update Block Design and Constraints

**Files:**
- Modify: `vivado_workspace/Zybo-Z7-20-pcam-5c.srcs/sources_1/bd/system/system.bd`
- Modify: `vivado_workspace/Zybo-Z7-20-pcam-5c.srcs/constrs_1/imports/constraints/ZyboZ7_A.xdc`
- Generate/update: Vivado generated outputs and bitstream

- [ ] **Step 1: Enable button constraint**

Edit `vivado_workspace/Zybo-Z7-20-pcam-5c.srcs/constrs_1/imports/constraints/ZyboZ7_A.xdc` and uncomment only `btn[0]`:

```tcl
set_property -dict { PACKAGE_PIN K18   IOSTANDARD LVCMOS33 } [get_ports { btn[0] }]; #IO_L12N_T1_MRCC_35 Sch=btn[0]
```

Leave `btn[1]`, `btn[2]`, and `btn[3]` commented.

- [ ] **Step 2: Modify BD in Vivado**

In Vivado:

1. Open `vivado_workspace/Zybo-Z7-20-pcam-5c.xpr`.
2. Refresh IP Catalog.
3. Remove the stream connection chain `AXI_GammaCorrection_0 -> AXI_RGBToGray_0 -> AXI_Binarize_0 -> axi_vdma_0/S_AXIS_S2MM`.
4. Add `AXI_ImageModeSelect`.
5. Connect `AXI_GammaCorrection_0/m_axis_video` to `AXI_ImageModeSelect_0/s_axis_video`.
6. Connect `AXI_ImageModeSelect_0/m_axis_video` to `axi_vdma_0/S_AXIS_S2MM`.
7. Connect `AXI_ImageModeSelect_0/StreamClk` to the existing video stream clock net.
8. Connect `AXI_ImageModeSelect_0/sStreamReset_n` to the same active-low video stream reset used by old stream IPs.
9. Connect `AXI_ImageModeSelect_0/s_axil` to the PS AXI interconnect.
10. Connect `AXI_ImageModeSelect_0/AxiLiteClk` and `aAxiLiteReset_n` to the existing AXI-Lite clock/reset net.
11. Add AXI GPIO, configure channel 1 as 1-bit input.
12. Make AXI GPIO `gpio_io_i[0:0]` external as top-level `btn[0:0]`.
13. Connect AXI GPIO AXI-Lite to the PS AXI interconnect.
14. Assign addresses for `AXI_ImageModeSelect_0` and AXI GPIO.

- [ ] **Step 3: Validate and regenerate**

In Vivado:

```tcl
validate_bd_design
reset_target all [get_files vivado_workspace/Zybo-Z7-20-pcam-5c.srcs/sources_1/bd/system/system.bd]
generate_target all [get_files vivado_workspace/Zybo-Z7-20-pcam-5c.srcs/sources_1/bd/system/system.bd]
launch_runs impl_1 -to_step write_bitstream
wait_on_run impl_1
write_hw_platform -fixed -include_bit -force -file C:/workspace-win/pcam-gray-bin/vivado_workspace/system_wrapper.xsa
```

Expected:

- BD validation successful.
- Bitstream generation completes.
- Timing WNS is non-negative except the known MIPI D-PHY domain exception from `CLAUDE.md`.
- `vivado_workspace/system_wrapper.xsa` is updated.

- [ ] **Step 4: Confirm BD contains new IP and GPIO**

Run:

```bash
rg -n "AXI_ImageModeSelect|axi_gpio|btn|AXI_RGBToGray|AXI_Binarize" vivado_workspace/Zybo-Z7-20-pcam-5c.srcs/sources_1/bd/system/system.bd
```

Expected:

- `AXI_ImageModeSelect_0` exists.
- AXI GPIO instance exists.
- `AXI_GammaCorrection_0/m_axis_video` connects to `AXI_ImageModeSelect_0/s_axis_video`.
- `AXI_ImageModeSelect_0/m_axis_video` connects to `axi_vdma_0/S_AXIS_S2MM`.
- Old `AXI_RGBToGray_0` and `AXI_Binarize_0` are not in the active stream path.

- [ ] **Step 5: Commit BD and constraint changes**

Run:

```bash
git add vivado_workspace/Zybo-Z7-20-pcam-5c.srcs/sources_1/bd/system/system.bd vivado_workspace/Zybo-Z7-20-pcam-5c.srcs/constrs_1/imports/constraints/ZyboZ7_A.xdc vivado_workspace/system_wrapper.xsa
git commit -m "feat: integrate image mode select in block design"
```

## Task 6: Add Vitis Button Polling and Mode Register Writes

**Files:**
- Modify: `vitis_workspace/app_gray/src/xparameters_compat.h`
- Modify: `vitis_workspace/app_gray/src/main.cc`

- [ ] **Step 1: Update compatibility macros**

After updating hardware spec in Vitis, add compatibility macros to `vitis_workspace/app_gray/src/xparameters_compat.h`. The plan supports the likely generated names and fails at compile time if Vivado generates a different name:

```c
#if defined(XPAR_AXI_IMAGE_MODE_SELECT_0_BASEADDR)
#define IMAGE_MODE_SELECT_BASEADDR XPAR_AXI_IMAGE_MODE_SELECT_0_BASEADDR
#elif defined(XPAR_AXI_IMAGEMODESELECT_0_BASEADDR)
#define IMAGE_MODE_SELECT_BASEADDR XPAR_AXI_IMAGEMODESELECT_0_BASEADDR
#elif defined(XPAR_AXI_IMAGE_MODE_SELECT_BASEADDR)
#define IMAGE_MODE_SELECT_BASEADDR XPAR_AXI_IMAGE_MODE_SELECT_BASEADDR
#else
#error "Missing AXI_ImageModeSelect base address macro in xparameters.h"
#endif

#if defined(XPAR_AXI_GPIO_BUTTONS_BASEADDR)
#define BUTTON_GPIO_BASEADDR XPAR_AXI_GPIO_BUTTONS_BASEADDR
#elif defined(XPAR_AXI_GPIO_0_BASEADDR)
#define BUTTON_GPIO_BASEADDR XPAR_AXI_GPIO_0_BASEADDR
#else
#error "Missing AXI GPIO button base address macro in xparameters.h"
#endif
```

Do not add the old names below; they are examples of the names the compatibility block replaces:

```c
#define XPAR_AXI_IMAGE_MODE_SELECT_0_BASEADDR XPAR_AXI_IMAGEMODESELECT_0_BASEADDR
#define XPAR_AXI_GPIO_BUTTONS_BASEADDR XPAR_AXI_GPIO_0_BASEADDR
```

- [ ] **Step 2: Add includes and constants to `main.cc`**

Modify `vitis_workspace/app_gray/src/main.cc`:

```cpp
#include "xgpio.h"
#include "sleep.h"

#define IMAGE_MODE_BASE_ADDR IMAGE_MODE_SELECT_BASEADDR
#define IMAGE_MODE_CTRL_OFFSET 0x00U
#define BUTTON_MASK 0x1U
```

- [ ] **Step 3: Initialize image mode and button state**

After `pipeline_mode_change(...)` in `main()`, add:

```cpp
XGpio button_gpio;
XGpio_Initialize(&button_gpio, BUTTON_GPIO_BASE_ADDR);
XGpio_SetDataDirection(&button_gpio, 1, BUTTON_MASK);

uint32_t image_mode = 0;
uint32_t button_prev = 0;
Xil_Out32(IMAGE_MODE_BASE_ADDR + IMAGE_MODE_CTRL_OFFSET, image_mode);
xil_printf("Image mode: 0 original\r\n");
```

- [ ] **Step 4: Poll button in the main loop**

Replace the existing blocking UART menu loop with a live button polling loop for this feature branch. Keep the existing menu code in git history; do not try to make `getchar()` nonblocking in the same change.

Use this loop after initialization:

```cpp
while (1) {
    uint32_t button_now = XGpio_DiscreteRead(&button_gpio, 1) & BUTTON_MASK;
    if (button_now && !button_prev) {
        usleep(30000);
        button_now = XGpio_DiscreteRead(&button_gpio, 1) & BUTTON_MASK;
        if (button_now) {
            image_mode = (image_mode + 1U) % 3U;
            Xil_Out32(IMAGE_MODE_BASE_ADDR + IMAGE_MODE_CTRL_OFFSET, image_mode);
            if (image_mode == 0U) {
                xil_printf("Image mode: 0 original\r\n");
            } else if (image_mode == 1U) {
                xil_printf("Image mode: 1 grayscale\r\n");
            } else {
                xil_printf("Image mode: 2 binary\r\n");
            }
            while ((XGpio_DiscreteRead(&button_gpio, 1) & BUTTON_MASK) != 0U) {
                usleep(1000);
            }
        }
    }
    button_prev = button_now;
    usleep(1000);
}
```

- [ ] **Step 5: Build Vitis platform and app**

In Vitis 2025.2:

1. Update Hardware Specification using `vivado_workspace/system_wrapper.xsa`.
2. Build Platform.
3. Build App.

Expected: build succeeds without missing `XPAR_*` macros or `XGpio` symbols.

- [ ] **Step 6: Commit Vitis changes**

Run:

```bash
git add vitis_workspace/app_gray/src/xparameters_compat.h vitis_workspace/app_gray/src/main.cc
git commit -m "feat: add button-controlled image mode switching"
```

## Task 7: Full Verification and Board Test

**Files:** no planned source changes unless verification reveals a defect

- [ ] **Step 1: Run all available simulations**

Run:

```bash
iverilog -o sim/sim_gray sim/tb_AXI_RGBToGray.v src/AXI_RGBToGray.v
vvp sim/sim_gray
iverilog -o sim/sim_bin sim/tb_AXI_Binarize.v src/AXI_Binarize.v
vvp sim/sim_bin
iverilog -o sim/sim_mode sim/tb_AXI_ImageModeSelect.v src/AXI_ImageModeSelect.v
vvp sim/sim_mode
```

Expected:

- RGBToGray: `9 PASS, 0 FAIL`
- Binarize: `9 PASS, 0 FAIL`
- ImageModeSelect: `11 PASS, 0 FAIL`

- [ ] **Step 2: Verify packaged IP metadata**

Run:

```bash
rg -n "AXI_ImageModeSelect|s_axis_video|m_axis_video|s_axil|StreamClk|AxiLiteClk|ACTIVE_LOW|THRESHOLD" vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_ImageModeSelect/component.xml
```

Expected: all listed interfaces and parameter metadata are present.

- [ ] **Step 3: Verify generated bitstream and XSA timestamps**

Run:

```bash
ls -l vivado_workspace/system_wrapper.xsa
find vivado_workspace -path "*impl_1*" -name "*.bit" -ls
```

Expected: XSA and bitstream timestamps are newer than the BD change.

- [ ] **Step 4: Program and validate board**

Board validation checklist:

- UART shows OV5640 Chip ID `0x5640`.
- HDMI initial output is original color.
- Press `btn[0]` once: output changes to grayscale and UART prints mode 1.
- Press `btn[0]` again: output changes to black/white binary and UART prints mode 2.
- Press `btn[0]` again: output returns to original color and UART prints mode 0.
- No black screen, frozen image, or persistent tearing.

- [ ] **Step 5: Stop for merge approval**

After board validation passes, report:

```text
板上驗證通過，請確認是否可以合併。
```

Do not squash merge, delete the branch, or push until the user explicitly says `可以合併`.
