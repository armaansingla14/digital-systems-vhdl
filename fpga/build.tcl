# build.tcl - non-project-mode synthesis, implementation and bitstream.
#
#   vivado -mode batch -source fpga/build.tcl -tclargs [basys3] [program]
#
# Writes utilisation/timing reports and the bitstream to build/vivado_<board>/.
# NOT RUN HERE: Vivado is not installed in this environment, so no
# utilisation or timing numbers are claimed in the README.

set board   [expr {[llength $argv] > 0 ? [lindex $argv 0] : "basys3"}]
set program [expr {[llength $argv] > 1 ? [lindex $argv 1] : "hello"}]
set root    [file normalize [file join [file dirname [info script]] ..]]
set outd    [file join $root build vivado_$board]
file mkdir $outd

switch -- $board {
  basys3 { set part xc7a35tcpg236-1; set xdc basys3.xdc }
  default { error "unknown board '$board'" }
}

set hex [file join $root build ${program}.hex]
exec python3 [file join $root tools asm.py] [file join $root programs ${program}.asm] -o $hex

foreach f {cpu_pkg alu regfile counter fifo control_unit datapath cpu sync_sram
           sram_ctrl baud_gen uart_tx uart_rx uart_ctrl soc_top fpga_top} {
  read_vhdl -vhdl2008 [file join $root rtl $f.vhd]
}
read_xdc [file join $root fpga $xdc]

synth_design -top fpga_top -part $part \
  -generic INIT_FILE=$hex -generic BAUD_DIVISOR=54
write_checkpoint -force [file join $outd post_synth.dcp]
report_utilization -file [file join $outd utilization_synth.rpt]

opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force [file join $outd post_route.dcp]

report_utilization    -file [file join $outd utilization_route.rpt]
report_timing_summary -file [file join $outd timing_summary.rpt] -max_paths 10
report_power          -file [file join $outd power.rpt]
report_drc            -file [file join $outd drc.rpt]

write_bitstream -force [file join $outd cpu16_soc_${board}.bit]
puts "Bitstream: [file join $outd cpu16_soc_${board}.bit]"
