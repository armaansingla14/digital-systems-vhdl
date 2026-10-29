# program_board.tcl - download a bitstream over JTAG.
#   vivado -mode batch -source fpga/program_board.tcl -tclargs build/vivado_basys3/cpu16_soc_basys3.bit
# NOT RUN HERE: no Vivado or board in this environment.
set bit [lindex $argv 0]
open_hw_manager
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices xc7a35t*] 0]
current_hw_device $dev
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
close_hw_manager
