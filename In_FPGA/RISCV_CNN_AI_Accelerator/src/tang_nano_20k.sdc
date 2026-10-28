// Tang Nano 20K SoC + HDMI clock constraints.
create_clock -name sys_clk -period 37.037 -waveform {0 18.519} [get_ports {sys_clk}] -add
create_clock -name soc_clk -period 185.185 -waveform {0 92.592} [get_pins {u_soc_clkdiv/CLKOUT}]
create_clock -name serial_clk -period 7.407 -waveform {0 3.704} [get_pins {u_hdmi/u_hdmi_pll/CLKOUT}]
create_clock -name pixel_clk -period 37.037 -waveform {0 18.519} [get_pins {u_hdmi/u_clkdiv_pixel/CLKOUT}]

// The prediction/result handoff uses explicit two-flop synchronizers.
set_false_path -from [get_clocks {soc_clk}] -to [get_cells {prediction_meta*}]
set_false_path -from [get_clocks {soc_clk}] -to [get_cells {confidence_meta*}]
set_false_path -from [get_clocks {soc_clk}] -to [get_cells {prediction_valid_meta*}]
set_false_path -from [get_clocks {soc_clk}] -to [get_cells {image_valid_meta*}]

// Button controls are stable toggle/data values with explicit synchronizers.
set_false_path -from [get_clocks {sys_clk}] -to [get_cells {selected_sample_meta*}]
set_false_path -from [get_clocks {sys_clk}] -to [get_cells {run_toggle_soc*}]
