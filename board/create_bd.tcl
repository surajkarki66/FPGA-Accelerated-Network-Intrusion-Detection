# Create ZCU104 Vivado project + FNN block design from terminal.
#
# Topology matches the working vivado_fnn_zcu104 BD:
#   HPM0_FPD + HPM1_FPD → AXI SmartConnect → fpga_top @ 0x400000000 (64K)
#   pl_clk0 @ 100 MHz, proc_sys_reset → rst_n / aresetn
#
# Usage:
#   vivado -mode batch -source board/create_bd.tcl -tclargs \
#     <proj_dir> <ip_repo> <board_part> <fpga_part> <base_addr> [bd_name]
#
# Requires a packaged IP at <ip_repo> (board/package_fpga_top.sh).

if {$argc < 5} {
  puts "USAGE: create_bd.tcl -tclargs <proj_dir> <ip_repo> <board_part> <part> <base_addr> \[bd_name\]"
  exit 1
}

set proj_dir   [file normalize [lindex $argv 0]]
set ip_repo    [file normalize [lindex $argv 1]]
set board_part [lindex $argv 2]
set part       [lindex $argv 3]
set base_addr  [lindex $argv 4]
set bd_name    [expr {$argc >= 6 ? [lindex $argv 5] : "fnn_bd"}]

set proj_name  [file tail $proj_dir]
set xpr        [file join $proj_dir ${proj_name}.xpr]
set comp_xml   [file join $ip_repo component.xml]

if {![file exists $comp_xml]} {
  puts "ERROR: missing $comp_xml — run board/package_fpga_top.sh first"
  exit 1
}

puts "Creating project $xpr"
puts "  IP_REPO=$ip_repo"
puts "  BOARD=$board_part PART=$part"
puts "  FNN_BASE=$base_addr BD=$bd_name"

file mkdir $proj_dir
create_project $proj_name $proj_dir -part $part -force
set_property board_part $board_part [current_project]
set_property target_language Verilog [current_project]
set_property ip_repo_paths [list $ip_repo] [current_project]
update_ip_catalog -rebuild

create_bd_design $bd_name
current_bd_design $bd_name

# --- Zynq UltraScale+ PS with ZCU104 board preset ---
create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.5 zynq_ultra_ps_e_0
apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e \
  -config {apply_board_preset "1"} [get_bd_cells zynq_ultra_ps_e_0]

set_property -dict [list \
  CONFIG.PSU__USE__M_AXI_GP0 {1} \
  CONFIG.PSU__USE__M_AXI_GP1 {1} \
  CONFIG.PSU__USE__M_AXI_GP2 {0} \
  CONFIG.PSU__FPGA_PL0_ENABLE {1} \
  CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100} \
] [get_bd_cells zynq_ultra_ps_e_0]

# --- FNN IP ---
create_bd_cell -type ip -vlnv user.org:user:fpga_top:1.0 fpga_top_0

# AXI automation: HPM0 → new SmartConnect → fpga_top (also wires clock/reset)
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config [list \
  Clk_master {Auto} \
  Clk_slave {Auto} \
  Clk_xbar {Auto} \
  Master {/zynq_ultra_ps_e_0/M_AXI_HPM0_FPD} \
  Slave {/fpga_top_0/interface_aximm} \
  ddr_seg {Auto} \
  intc_ip {New AXI SmartConnect} \
  master_apm {0} \
] [get_bd_intf_pins fpga_top_0/interface_aximm]

# Attach HPM1 (needed for 0x4_0000_0000 aperture) to the same SmartConnect
set smc [get_bd_cells -quiet axi_smc]
if {$smc eq ""} {
  set smc [get_bd_cells -quiet -filter {VLNV =~ "*smartconnect*"}]
}
if {$smc eq ""} {
  puts "ERROR: SmartConnect cell not found after HPM0 automation"
  exit 1
}
set smc_name [get_property NAME $smc]

apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config [list \
  Clk_master {Auto} \
  Clk_slave {Auto} \
  Clk_xbar {Auto} \
  Master {/zynq_ultra_ps_e_0/M_AXI_HPM1_FPD} \
  Slave {/fpga_top_0/interface_aximm} \
  ddr_seg {Auto} \
  intc_ip [list /$smc_name] \
  master_apm {0} \
] [get_bd_intf_pins zynq_ultra_ps_e_0/M_AXI_HPM1_FPD]

# Address map: force the known Linux/host base used by fnn_bench / host stubs
assign_bd_address -force
set segs [get_bd_addr_segs -quiet -filter {NAME =~ "*fpga_top*"}]
if {[llength $segs] == 0} {
  set segs [get_bd_addr_segs */*/SEG_fpga_top_0_reg0]
}
foreach s $segs {
  # Only PS Data space segments need the high aperture
  if {[string match "*zynq_ultra_ps_e_0*" $s] || [string match "*/Data/*" $s]} {
    set_property offset $base_addr $s
    set_property range 64K $s
    puts "ADDR $s offset=$base_addr range=64K"
  }
}

regenerate_bd_layout
validate_bd_design
save_bd_design

# HDL wrapper as top
set wrapper [make_wrapper -files [get_files ${bd_name}.bd] -top]
add_files -norecurse $wrapper
set_property top ${bd_name}_wrapper [current_fileset]
update_compile_order -fileset sources_1

save_bd_design
puts "XPR_OK=$xpr"
puts "TOP=${bd_name}_wrapper"
exit 0
