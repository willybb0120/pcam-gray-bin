# pkg_axi_image_mode_select.tcl
#
# Run from the Vivado Tcl Console:
#   source C:/workspace-win/pcam-gray-bin/scripts/pkg_axi_image_mode_select.tcl
#
# Packages hdl/AXI_ImageModeSelect.v as a reusable Vivado IP.
# Side effect: creates and closes an in-memory project; any existing project will
#              be detached from active state. Reopen the main xpr after running
#              this script if needed.

set script_dir [file dirname [file normalize [info script]]]
set proj_root  [file normalize [file join $script_dir ".."]]
set ip_dir    "$proj_root/vivado_workspace/Zybo-Z7-20-pcam-5c.ipdefs/repo_0/local/ip/AXI_ImageModeSelect"
set hdl_file  "$ip_dir/hdl/AXI_ImageModeSelect.v"

if {![file exists $hdl_file]} {
    error "RTL not found: $hdl_file"
}
puts "INFO: packaging from $hdl_file"

foreach stale [list "$ip_dir/component.xml" "$ip_dir/xgui"] {
    if {[file exists $stale]} {
        puts "INFO: removing previous $stale"
        file delete -force $stale
    }
}

create_project -in_memory -part xc7z020clg400-1 -force AXI_ImageModeSelect_pkg

read_verilog $hdl_file
update_compile_order -fileset sources_1
set_property top AXI_ImageModeSelect [current_fileset]
update_compile_order -fileset sources_1

ipx::package_project -root_dir $ip_dir \
    -vendor local -library local -taxonomy /UserIP \
    -import_files -set_current true

set core [ipx::current_core]

set_property name              AXI_ImageModeSelect                                      $core
set_property display_name      "AXI Image Mode Select"                                  $core
set_property description       "AXI4-Stream video mode selector with AXI-Lite control"  $core
set_property vendor            local                                                    $core
set_property library           local                                                    $core
set_property version           1.0                                                      $core
set_property core_revision     1                                                        $core
set_property supported_families {zynq Production}                                       $core

proc require_step {label body} {
    if {[catch {uplevel 1 $body} msg]} {
        error "Required IP metadata step failed ($label): $msg"
    }
    puts "INFO: $label -> $msg"
}

proc require_bus_interface {core busif_name expected_abs} {
    set busif [ipx::get_bus_interfaces $busif_name -of_objects $core -quiet]
    if {$busif eq ""} {
        error "Required bus interface missing: $busif_name"
    }
    set actual_abs [get_property abstraction_type_vlnv $busif]
    if {$expected_abs ne "" && $actual_abs ne $expected_abs} {
        error "Bus interface $busif_name has abstraction $actual_abs, expected $expected_abs"
    }
    return $busif
}

proc require_bus_type {busif expected_type} {
    set busif_name [get_property name $busif]
    set actual_type [get_property bus_type_vlnv $busif]
    if {$actual_type ne $expected_type} {
        error "Bus interface $busif_name has bus type $actual_type, expected $expected_type"
    }
}

proc ensure_axilite_protocol {busif} {
    set busif_name [get_property name $busif]
    set protocol [ipx::get_bus_parameters PROTOCOL -of_objects $busif -quiet]
    if {$protocol eq ""} {
        ipx::add_bus_parameter PROTOCOL $busif
        set protocol [ipx::get_bus_parameters PROTOCOL -of_objects $busif]
        puts "INFO: added missing PROTOCOL bus parameter to $busif_name"
    }
    set_property value "AXI4LITE" $protocol
    set actual_protocol [get_property value $protocol]
    if {$actual_protocol ne "AXI4LITE"} {
        error "Bus interface $busif_name declares PROTOCOL=$actual_protocol, expected AXI4LITE"
    }
    puts "INFO: $busif_name declares PROTOCOL=AXI4LITE"
}

proc require_bus_parameter_value {busif param_name expected_value} {
    set param [ipx::get_bus_parameters $param_name -of_objects $busif -quiet]
    set busif_name [get_property name $busif]
    if {$param eq ""} {
        error "Bus interface $busif_name is missing bus parameter $param_name"
    }
    set actual_value [get_property value $param]
    if {$actual_value ne $expected_value} {
        error "Bus interface $busif_name parameter $param_name is $actual_value, expected $expected_value"
    }
}

proc force_bus_parameter_value {busif param_name expected_value} {
    set param [ipx::get_bus_parameters $param_name -of_objects $busif -quiet]
    if {$param eq ""} {
        ipx::add_bus_parameter $param_name $busif
        set param [ipx::get_bus_parameters $param_name -of_objects $busif]
    }
    set_property value $expected_value $param
    require_bus_parameter_value $busif $param_name $expected_value
}

proc require_associated_busif_contains {clock_busif expected_busif} {
    set param [ipx::get_bus_parameters ASSOCIATED_BUSIF -of_objects $clock_busif -quiet]
    set clock_name [get_property name $clock_busif]
    if {$param eq ""} {
        error "Clock interface $clock_name is missing ASSOCIATED_BUSIF"
    }
    set actual [get_property value $param]
    if {[lsearch -exact [split $actual ":"] $expected_busif] < 0} {
        error "Clock interface $clock_name ASSOCIATED_BUSIF is $actual, expected to include $expected_busif"
    }
}

proc ensure_memory_map_with_address_block {core map_name old_map_name} {
    set mmap [ipx::get_memory_maps $map_name -of_objects $core -quiet]
    if {$mmap eq ""} {
        set old_mmap [ipx::get_memory_maps $old_map_name -of_objects $core -quiet]
        if {$old_mmap ne ""} {
            set_property name $map_name $old_mmap
            set_property display_name $map_name $old_mmap
            puts "INFO: renamed AXI-Lite memory map $old_map_name to $map_name"
            set mmap [ipx::get_memory_maps $map_name -of_objects $core -quiet]
        }
    }
    if {$mmap eq ""} {
        error "AXI-Lite metadata missing: memory map $map_name was not generated for s_axil"
    }
    set blocks [ipx::get_address_blocks -of_objects $mmap -quiet]
    if {$blocks eq ""} {
        error "AXI-Lite metadata missing: memory map $map_name has no address block"
    }
    return $mmap
}

proc set_active_low_reset {core reset_name} {
    set rst_bif [require_bus_interface $core $reset_name "xilinx.com:signal:reset_rtl:1.0"]
    if {[ipx::get_bus_parameters POLARITY -of_objects $rst_bif -quiet] eq ""} {
        ipx::add_bus_parameter POLARITY $rst_bif
    }
    set_property value "ACTIVE_LOW" [ipx::get_bus_parameters POLARITY -of_objects $rst_bif]
    require_bus_parameter_value $rst_bif POLARITY ACTIVE_LOW
    puts "INFO: set $reset_name polarity = ACTIVE_LOW"
}

require_step "infer axis interfaces" {ipx::infer_bus_interfaces xilinx.com:interface:axis_rtl:1.0 $core}
require_step "infer AXI memory-mapped interfaces" {ipx::infer_bus_interfaces xilinx.com:interface:aximm_rtl:1.0 $core}

require_step "infer StreamClk as clock" {ipx::infer_bus_interface StreamClk xilinx.com:signal:clock_rtl:1.0 $core}
require_step "infer sStreamReset_n as reset" {ipx::infer_bus_interface sStreamReset_n xilinx.com:signal:reset_rtl:1.0 $core}
require_step "infer AxiLiteClk as clock" {ipx::infer_bus_interface AxiLiteClk xilinx.com:signal:clock_rtl:1.0 $core}
require_step "infer aAxiLiteReset_n as reset" {ipx::infer_bus_interface aAxiLiteReset_n xilinx.com:signal:reset_rtl:1.0 $core}

require_bus_interface $core s_axis_video "xilinx.com:interface:axis_rtl:1.0"
require_bus_interface $core m_axis_video "xilinx.com:interface:axis_rtl:1.0"
require_bus_interface $core StreamClk "xilinx.com:signal:clock_rtl:1.0"
require_bus_interface $core sStreamReset_n "xilinx.com:signal:reset_rtl:1.0"
require_bus_interface $core AxiLiteClk "xilinx.com:signal:clock_rtl:1.0"
require_bus_interface $core aAxiLiteReset_n "xilinx.com:signal:reset_rtl:1.0"

set_active_low_reset $core sStreamReset_n
set_active_low_reset $core aAxiLiteReset_n

set axil_busif ""
foreach bif [ipx::get_bus_interfaces -of_objects $core] {
    set bif_name [get_property name $bif]
    set bif_abs  [get_property abstraction_type_vlnv $bif]
    if {$bif_abs eq "xilinx.com:interface:aximm_rtl:1.0"} {
        set axil_busif $bif
        if {$bif_name ne "s_axil"} {
            set_property name s_axil $bif
            puts "INFO: renamed AXI-Lite bus interface $bif_name to s_axil"
        }
        break
    }
}
if {$axil_busif eq ""} {
    error "Required AXI-Lite bus interface was not inferred"
}
set axil_busif [require_bus_interface $core s_axil "xilinx.com:interface:aximm_rtl:1.0"]
require_bus_type $axil_busif "xilinx.com:interface:aximm:1.0"
ensure_axilite_protocol $axil_busif

puts "INFO: bus interfaces after inference:"
foreach bif [ipx::get_bus_interfaces -of_objects $core] {
    puts "  - [get_property name $bif] (type=[get_property abstraction_type_vlnv $bif])"
}

foreach busif {s_axis_video m_axis_video} {
    require_step "associate $busif with StreamClk" {ipx::associate_bus_interfaces -busif $busif -clock StreamClk $core}
}
require_step "associate StreamClk reset sStreamReset_n" {ipx::associate_bus_interfaces -clock StreamClk -reset sStreamReset_n $core}
require_step "associate s_axil with AxiLiteClk" {ipx::associate_bus_interfaces -busif s_axil -clock AxiLiteClk $core}
require_step "associate AxiLiteClk reset aAxiLiteReset_n" {ipx::associate_bus_interfaces -clock AxiLiteClk -reset aAxiLiteReset_n $core}

set stream_clk [require_bus_interface $core StreamClk "xilinx.com:signal:clock_rtl:1.0"]
set axil_clk [require_bus_interface $core AxiLiteClk "xilinx.com:signal:clock_rtl:1.0"]
require_associated_busif_contains $stream_clk s_axis_video
require_associated_busif_contains $stream_clk m_axis_video
force_bus_parameter_value $stream_clk ASSOCIATED_RESET sStreamReset_n
require_associated_busif_contains $axil_clk s_axil
force_bus_parameter_value $axil_clk ASSOCIATED_RESET aAxiLiteReset_n
ensure_memory_map_with_address_block $core s_axil s_axi

set thresh [ipx::get_user_parameters THRESHOLD -of_objects $core -quiet]
if {$thresh eq ""} {
    error "THRESHOLD user parameter was not inferred"
}
set_property value_format                      long       $thresh
set_property value                             128        $thresh
set_property value_validation_type             range_long $thresh
set_property value_validation_range_minimum    0          $thresh
set_property value_validation_range_maximum    255        $thresh

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
set_property tooltip "Pixel value at and above which binarized mode outputs white (0xFFFFFF)" $thresh_gui

ipx::create_xgui_files $core

ipx::check_integrity $core
ipx::save_core $core
ipx::unload_core $core

close_project

puts "===================="
puts "AXI_ImageModeSelect packaged at:"
puts "  $ip_dir"
puts "Files generated:"
puts "  component.xml"
puts "  xgui/AXI_ImageModeSelect_v1_0.tcl"
puts "===================="
puts "Next: reopen the main project, refresh the IP Catalog, and add AXI Image Mode Select in BD."
