// Tang Nano 20K onboard oscillator: 27 MHz.
create_clock -name sys_clk -period 37.037 -waveform {0 18.5185} [get_ports {sys_clk}]

// CLKDIV output: 27 MHz / 5 = 5.4 MHz.
create_clock -name soc_clk -period 185.185 -waveform {0 92.5925} [get_pins {u_clkdiv/CLKOUT}]
