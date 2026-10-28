# Run from the project root:
#   gw_sh scripts/build_fpga.tcl
open_project TangNano20K_RISCV_CNN.gprj
set_option -top_module tang_nano_20k_top
set_option -output_base_name TangNano20K_RISCV_CNN
set_option -verilog_std v2001
set_option -looplimit 8192
set_option -print_all_synthesis_warning 1
set_option -gen_text_timing_rpt 1
run all
