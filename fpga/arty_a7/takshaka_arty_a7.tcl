# =============================================================================
# takshaka_arty_a7.tcl — Vivado batch flow to a BITSTREAM for the Arty A7-100T.
#   vivado -mode batch -source takshaka_arty_a7.tcl -tclargs <BUILD_DIR>
# Build firmware first: cd sw && ./build_fpga_hello.sh && cp firmware.mem <BUILD_DIR>/
# =============================================================================
set fpga_dir  [file normalize [file dirname [info script]]]
set build_dir [expr {[llength $argv] >= 1 ? [lindex $argv 0] : "$fpga_dir/build"}]
set part      xc7a100tcsg324-1

file mkdir $build_dir
cd $build_dir

set fp [open $fpga_dir/takshaka_arty_a7.f r]
while {[gets $fp line] >= 0} {
  set line [string trim $line]
  if {$line eq "" || [string match "#*" $line] || [string match "//*" $line]} { continue }
  if {[string match "+incdir+*" $line]} {
    set incdir [string range $line 8 end]
    set_property include_dirs [list [file normalize "$fpga_dir/$incdir"]] [current_fileset]
    continue
  }
  read_verilog -sv [file normalize $fpga_dir/$line]
}
close $fp

read_xdc $fpga_dir/takshaka_arty_a7.xdc
set_property part $part [current_project]
set_property top takshaka_arty_a7 [current_fileset]

add_files -norecurse $build_dir/firmware.mem
set_property file_type {Memory Initialization Files} [get_files firmware.mem]

synth_design -top takshaka_arty_a7 -part $part
opt_design
place_design
route_design
report_utilization    -file $build_dir/util.rpt
report_timing_summary -file $build_dir/timing.rpt
write_checkpoint -force $build_dir/route.dcp
write_bitstream -force $build_dir/takshaka_arty_a7.bit
puts "DONE: $build_dir/takshaka_arty_a7.bit"
