# pkg_axi_binarize.tcl
#
# 在 Vivado Tcl Console 執行：
#   source C:/workspace-win/pcam-gray-bin/scripts/pkg_axi_binarize.tcl
#
# 目的：把 src/AXI_Binarize.v 打包成 Vivado IP，含 THRESHOLD spinbox（0~255，預設 128）。
# 副作用：會建立並關閉一個 in-memory project；現有專案會被切離 active 狀態，
#         結束後請自行 reopen 主 xpr（或保持原本的就好，本腳本只用 in-memory）。

set proj_root "C:/workspace-win/pcam-gray-bin"
set ip_dir    "$proj_root/vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_Binarize"
set hdl_file  "$ip_dir/hdl/AXI_Binarize.v"

# --- 前置檢查 ---
if {![file exists $hdl_file]} {
    error "RTL not found: $hdl_file"
}
puts "INFO: packaging from $hdl_file"

# --- 清理上次失敗的殘留檔案（除了 hdl/） ---
foreach stale [list "$ip_dir/component.xml" "$ip_dir/xgui"] {
    if {[file exists $stale]} {
        puts "INFO: removing previous $stale"
        file delete -force $stale
    }
}

# --- 建立暫存 in-memory 專案 ---
create_project -in_memory -part xc7z020clg400-1 -force AXI_Binarize_pkg

read_verilog $hdl_file
update_compile_order -fileset sources_1
set_property top AXI_Binarize [current_fileset]
update_compile_order -fileset sources_1

# --- 打包 ---
ipx::package_project -root_dir $ip_dir \
    -vendor local -library local -taxonomy /UserIP \
    -import_files -set_current true

set core [ipx::current_core]

# --- IP identification ---
set_property name           AXI_Binarize                                                   $core
set_property display_name   "AXI Binarize"                                                 $core
set_property description    "Fixed-threshold binarization for grayscale AXI4-Stream video" $core
set_property vendor         local                                                          $core
set_property library        local                                                          $core
set_property version        1.0                                                            $core
set_property core_revision  1                                                              $core
set_property supported_families {zynq Production}                                          $core

# --- 推斷 AXI4-Stream 介面（複數命令僅針對指定 abstraction） ---
catch {ipx::infer_bus_interfaces xilinx.com:interface:axis_rtl:1.0 $core} msg
puts "INFO: infer axis -> $msg"

# --- 推斷 clock / reset 介面（單數命令，逐個 port） ---
catch {ipx::infer_bus_interface StreamClk xilinx.com:signal:clock_rtl:1.0 $core} msg
puts "INFO: infer StreamClk as clock -> $msg"
catch {ipx::infer_bus_interface sStreamReset_n xilinx.com:signal:reset_rtl:1.0 $core} msg
puts "INFO: infer sStreamReset_n as reset -> $msg"

# --- reset polarity: active-low ---
set rst_bif [ipx::get_bus_interfaces sStreamReset_n -of_objects $core -quiet]
if {$rst_bif ne ""} {
    if {[ipx::get_bus_parameters POLARITY -of_objects $rst_bif -quiet] eq ""} {
        ipx::add_bus_parameter POLARITY $rst_bif
    }
    set_property value "ACTIVE_LOW" [ipx::get_bus_parameters POLARITY -of_objects $rst_bif]
    puts "INFO: set sStreamReset_n polarity = ACTIVE_LOW"
}

# --- 列出實際存在的 bus interface 名稱（除錯用） ---
puts "INFO: bus interfaces after inference:"
foreach bif [ipx::get_bus_interfaces -of_objects $core] {
    puts "  - [get_property name $bif] (type=[get_property abstraction_type_vlnv $bif])"
}

# --- 關聯 clock / reset 到 axis 介面 ---
foreach busif {s_axis_video m_axis_video} {
    if {[catch {ipx::associate_bus_interfaces -busif $busif -clock StreamClk $core} msg]} {
        puts "WARN: associate $busif with StreamClk failed: $msg"
    } else {
        puts "INFO: associated $busif with clock StreamClk"
    }
}
if {[catch {ipx::associate_bus_interfaces -clock StreamClk -reset sStreamReset_n $core} msg]} {
    puts "WARN: associate StreamClk reset sStreamReset_n failed: $msg"
} else {
    puts "INFO: associated StreamClk with reset sStreamReset_n"
}

# --- THRESHOLD 參數設定 ---
# user parameter（IP 客戶端可見的數值；強制成 long 讓 GUI 顯示十進位）
set thresh [ipx::get_user_parameters THRESHOLD -of_objects $core]
set_property value_format               long       $thresh
set_property value                      128        $thresh
set_property value_validation_type      range_long $thresh
set_property value_validation_range_minimum 0      $thresh
set_property value_validation_range_maximum 255    $thresh

# HDL parameter 不動：保留 RTL 推斷的 bitString 格式（"10000000"）。
# Vivado 會自動把 user 參數（long 128）轉換到 HDL 參數（bitString 8'b10000000）。
# 強制改 HDL value_format 為 long 會與 RTL 預設值衝突 (IP_Flow 19-343)。

# --- GUI 呈現：把 THRESHOLD 放到 Page 0、給友善顯示名稱 ---
set page0 [ipgui::get_pagespec -name "Page 0" -component $core -quiet]
if {$page0 eq ""} {
    set page0 [ipgui::add_page -name "Page 0" -component $core -display_name "Page 0"]
}

set thresh_gui [ipgui::get_guiparamspec -name THRESHOLD -component $core -quiet]
if {$thresh_gui eq ""} {
    ipgui::add_param -name THRESHOLD -component $core -parent $page0
    set thresh_gui [ipgui::get_guiparamspec -name THRESHOLD -component $core]
}
set_property display_name "Threshold (0-255)" $thresh_gui
set_property tooltip "Pixel value at and above which output is white (0xFFFFFF)" $thresh_gui

# --- 重新生成 xgui tcl ---
ipx::create_xgui_files $core

# --- 驗證並儲存 ---
ipx::check_integrity $core
ipx::save_core $core
ipx::unload_core $core

close_project

puts "===================="
puts "AXI_Binarize packaged at:"
puts "  $ip_dir"
puts "Files generated:"
puts "  component.xml"
puts "  xgui/AXI_Binarize_v1_0.tcl"
puts "===================="
puts "Next: 重新 open 主專案，IP Catalog Refresh 後即可在 BD 中找到 AXI_Binarize。"
