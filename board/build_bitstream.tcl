# Rebuild FNN bitstream, forcing a fresh OOC synth of fpga_top.
# Usage:
#   source /tools/Xilinx/Vivado/<ver>/settings64.sh
#   vivado -mode batch -source board/build_bitstream.tcl \
#     -tclargs <vivado.xpr> <axi4lite_slave.v> <out.bit>
#
# Args: xpr_path  rtl_axi_slave  out_bit

if {$argc < 3} {
  puts "USAGE: vivado -mode batch -source build_bitstream.tcl -tclargs <xpr> <axi4lite_slave.v> <out.bit>"
  exit 1
}

set xpr      [lindex $argv 0]
set axi_src  [lindex $argv 1]
set out_bit  [lindex $argv 2]
set proj_dir [file dirname $xpr]
set proj_name [file rootname [file tail $xpr]]

open_project $xpr

# create_bd.tcl never generates output products, so ipshared does not exist
# until the BD is generated. Do it here if needed.
set bd_file [get_files -quiet fnn_bd.bd]
if {$bd_file eq ""} {
  puts "ERROR: fnn_bd.bd not in $xpr - run: make board-bd"
  exit 1
}

proc find_axi_in_ipshared {proj_dir} {
  foreach gen [glob -nocomplain -directory $proj_dir *.gen] {
    set ipshared [file join $gen sources_1 bd fnn_bd ipshared]
    if {![file isdirectory $ipshared]} continue
    foreach pat {*/src/axi4lite_slave.v */*/axi4lite_slave.v */*/*/axi4lite_slave.v} {
      set hits [glob -nocomplain -directory $ipshared $pat]
      if {[llength $hits]} { return [lindex $hits 0] }
    }
  }
  return ""
}

set target_file [find_axi_in_ipshared $proj_dir]
if {$target_file eq ""} {
  puts "INFO: ipshared missing - generating BD output products"
  update_ip_catalog -rebuild
  generate_target all $bd_file
  set target_file [find_axi_in_ipshared $proj_dir]
}
if {$target_file eq ""} {
  puts "ERROR: axi4lite_slave.v not found under $proj_dir/*.gen/sources_1/bd/fnn_bd/ipshared after generate_target"
  exit 1
}

puts "XPR=$xpr"
puts "AXI_SRC=$axi_src"
puts "IP_SRC_FILE=$target_file"
puts "OUT_BIT=$out_bit"

file copy -force $axi_src $target_file

# Empty cache dir so packaged-IP edits are actually synthesised
# (must run after open_project — config_ip_cache needs an active project)
set cache_dir [file join /tmp fnn_ip_cache_[pid]]
file mkdir $cache_dir
config_ip_cache -use_cache_location $cache_dir

update_compile_order -fileset sources_1

# Reset OOC synth for fpga_top if that run exists (name from BD instance)
foreach r [get_runs -quiet *_fpga_top_*_synth_1] {
  reset_run $r
  launch_runs $r -jobs 8
  wait_on_run $r
}

reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

set impl_dir [get_property DIRECTORY [get_runs impl_1]]
set gen_bit  [file join $impl_dir fnn_bd_wrapper.bit]
if {![file exists $gen_bit]} {
  # Fall back to any wrapper .bit produced by impl
  set bits [glob -nocomplain -directory $impl_dir *_wrapper.bit]
  if {[llength $bits]} {
    set gen_bit [lindex $bits 0]
  }
}
if {![file exists $gen_bit]} {
  puts "ERROR: bitstream not found under $impl_dir"
  exit 1
}
file mkdir [file dirname $out_bit]
file copy -force $gen_bit $out_bit
puts "BITSTREAM_OK=$out_bit"
exit 0