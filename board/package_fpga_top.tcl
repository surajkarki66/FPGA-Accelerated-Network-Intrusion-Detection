# Package rtl/ as AXI4-Lite IP: user.org:user:fpga_top:1.0
#
# Usage:
#   vivado -mode batch -source board/package_fpga_top.tcl \
#     -tclargs <repo_root> <ip_repo_dir> [fpga_part]
#
# Copies accelerator + peripheral RTL, fnn_params.vh, and weight ROMs into
# <ip_repo>/src, rewrites MEM_FILE defaults to those local ROMs, then runs
# ipx::package_project with AXI / clock / reset / memory-map metadata.

if {$argc < 2} {
  puts "USAGE: vivado -mode batch -source package_fpga_top.tcl -tclargs <repo_root> <ip_repo> \[part\]"
  exit 1
}

set repo_root [file normalize [lindex $argv 0]]
set ip_repo   [file normalize [lindex $argv 1]]
set part      [expr {$argc >= 3 ? [lindex $argv 2] : "xczu7ev-ffvc1156-2-e"}]

set rtl_rel {
  rtl/accel/mac_unit.v
  rtl/accel/relu.v
  rtl/accel/argmax.v
  rtl/accel/act_mem.v
  rtl/accel/weight_mem.v
  rtl/accel/shared_mac_engine.v
  rtl/accel/layer_controller.v
  rtl/accel/fnn_top.v
  rtl/peripheral/axi4lite_slave.v
  rtl/peripheral/fpga_top.v
}

set params_src [file join $repo_root rtl include fnn_params.vh]
set w_mem_src  [file join $repo_root weights generated weights.mem]
set b_mem_src  [file join $repo_root weights generated biases.mem]

foreach f [list $params_src $w_mem_src $b_mem_src] {
  if {![file exists $f]} {
    puts "ERROR: missing $f (run make deploy first)"
    exit 1
  }
}

set stage [file join [file dirname $ip_repo] _fpga_top_stage_[pid]]
file delete -force $stage
file mkdir $stage

foreach rel $rtl_rel {
  set src [file join $repo_root $rel]
  if {![file exists $src]} {
    puts "ERROR: missing $src"
    exit 1
  }
  file copy -force $src [file join $stage [file tail $src]]
}
file copy -force $params_src [file join $stage fnn_params.vh]
file copy -force $w_mem_src  [file join $stage weights.mem]
file copy -force $b_mem_src  [file join $stage biases.mem]

# Point ROM $readmemh paths at the packaged copies (absolute → synth-safe).
set fnn_top_staged [file join $stage fnn_top.v]
set w_abs [file join $ip_repo src weights.mem]
set b_abs [file join $ip_repo src biases.mem]
set fh [open $fnn_top_staged r]
set body [read $fh]
close $fh
regsub -all {parameter\s+W_MEM_FILE\s*=\s*"[^"]*"} $body \
  "parameter W_MEM_FILE    = \"$w_abs\"" body
regsub -all {parameter\s+BIAS_MEM_FILE\s*=\s*"[^"]*"} $body \
  "parameter BIAS_MEM_FILE = \"$b_abs\"" body
set fh [open $fnn_top_staged w]
puts -nonewline $fh $body
close $fh

file delete -force $ip_repo
file mkdir $ip_repo

set tmp_proj [file join [file dirname $ip_repo] _fpga_top_pkg_[pid]]
puts "Packaging fpga_top → $ip_repo (part=$part)"

create_project pkg_fpga_top $tmp_proj -part $part -force
set_property target_language Verilog [current_project]

add_files -norecurse [glob -directory $stage *.v *.vh *.mem]
set_property file_type {Verilog Header} [get_files fnn_params.vh]
# Keep headers next to sources (same fileset) — avoid include_dirs that would
# bake a deleted staging path into component.xml <spirit:dependency>.
set_property is_global_include true [get_files fnn_params.vh]
set_property top fpga_top [current_fileset]
update_compile_order -fileset sources_1

ipx::package_project -root_dir $ip_repo -vendor user.org -library user \
  -taxonomy /UserIP -import_files -set_current true -force

set core [ipx::current_core]
set_property name fpga_top $core
set_property version {1.0} $core
set_property display_name {FNN AXI4-Lite} $core
set_property description {INT8 FNN accelerator with AXI4-Lite MMIO} $core
set_property vendor_display_name {user.org} $core
set_property company_url {https://user.org} $core
set_property core_revision 1 $core
set_property supported_families {zynquplus Production} $core

# package_project already inferred clk / rst_n / interface_aximm; tighten metadata.
ipx::infer_bus_interface clk xilinx.com:signal:clock_rtl:1.0 $core
ipx::infer_bus_interface rst_n xilinx.com:signal:reset_rtl:1.0 $core

set bif [ipx::get_bus_interfaces interface_aximm -of_objects $core]
if {$bif eq ""} {
  puts "ERROR: expected inferred bus interface 'interface_aximm'"
  exit 1
}
ipx::add_bus_parameter PROTOCOL $bif
set_property value AXI4LITE [ipx::get_bus_parameters PROTOCOL -of_objects $bif]
ipx::associate_bus_interfaces -busif interface_aximm -clock clk $core

set rst_bif [ipx::get_bus_interfaces rst_n -of_objects $core]
if {$rst_bif ne ""} {
  ipx::add_bus_parameter POLARITY $rst_bif
  set_property value ACTIVE_LOW [ipx::get_bus_parameters POLARITY -of_objects $rst_bif]
}

# Memory map so Address Editor can place the slave (64 KiB window).
foreach mm [ipx::get_memory_maps -of_objects $core] {
  ipx::remove_memory_map [get_property NAME $mm] $core
}
ipx::add_memory_map interface_aximm $core
set_property slave_memory_map_ref interface_aximm $bif
ipx::add_address_block reg0 [ipx::get_memory_maps interface_aximm -of_objects $core]
set ab [ipx::get_address_blocks reg0 -of_objects [ipx::get_memory_maps interface_aximm -of_objects $core]]
set_property range {65536} $ab
set_property width {32} $ab
set_property usage register $ab

ipx::create_xgui_files $core
ipx::update_checksums $core
ipx::save_core $core

close_project -delete
file delete -force $stage
file delete -force $tmp_proj

set comp [file join $ip_repo component.xml]
if {![file exists $comp]} {
  puts "ERROR: packaging failed — no component.xml in $ip_repo"
  exit 1
}
# Strip any leftover absolute staging <spirit:dependency> paths.
set fh [open $comp r]
set xml [read $fh]
close $fh
regsub -all {<spirit:dependency>[^<]*_fpga_top_stage_[^<]*</spirit:dependency>\n?} $xml {} xml
set fh [open $comp w]
puts -nonewline $fh $xml
close $fh

puts "IP_OK=$ip_repo (user.org:user:fpga_top:1.0)"
exit 0
