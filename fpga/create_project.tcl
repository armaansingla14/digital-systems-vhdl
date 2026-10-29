# create_project.tcl - create a Vivado project for the 16-bit CPU SoC.
#
#   vivado -mode batch -source fpga/create_project.tcl -tclargs [basys3] [program]
#
# NOT RUN HERE: Vivado is not installed in this environment. The script is
# provided for building on a machine with Vivado 2020.2 or newer.

set board   [expr {[llength $argv] > 0 ? [lindex $argv 0] : "basys3"}]
set program [expr {[llength $argv] > 1 ? [lindex $argv 1] : "hello"}]

set root   [file normalize [file join [file dirname [info script]] ..]]
set projd  [file join $root vivado_proj $board]

switch -- $board {
  basys3 { set part xc7a35tcpg236-1; set xdc basys3.xdc }
  default { error "unknown board '$board'" }
}

# Assemble the program image that initialises the block RAM.
set hex [file join $root build ${program}.hex]
file mkdir [file join $root build]
exec python3 [file join $root tools asm.py] [file join $root programs ${program}.asm] -o $hex

create_project cpu16_soc $projd -part $part -force
set_property target_language VHDL [current_project]

set rtl_files {
  cpu_pkg.vhd alu.vhd regfile.vhd counter.vhd fifo.vhd control_unit.vhd
  datapath.vhd cpu.vhd sync_sram.vhd sram_ctrl.vhd baud_gen.vhd uart_tx.vhd
  uart_rx.vhd uart_ctrl.vhd soc_top.vhd fpga_top.vhd
}
foreach f $rtl_files {
  add_files -norecurse [file join $root rtl $f]
}
set_property file_type {VHDL 2008} [get_files *.vhd]
add_files -fileset constrs_1 -norecurse [file join $root fpga $xdc]

# Simulation sources (Vivado xsim can run the same testbenches)
foreach f {tb_pkg.vhd tb_soc.vhd} {
  add_files -fileset sim_1 -norecurse [file join $root tb $f]
}
set_property file_type {VHDL 2008} [get_files -of_objects [get_filesets sim_1] *.vhd]
set_property top tb_soc [get_filesets sim_1]

set_property top fpga_top [current_fileset]
set_property generic "INIT_FILE=$hex BAUD_DIVISOR=54" [current_fileset]

puts "Project created in $projd (part $part, program $program)"
