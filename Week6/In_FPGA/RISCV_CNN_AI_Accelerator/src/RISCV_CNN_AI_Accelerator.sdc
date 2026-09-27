//Copyright (C)2014-2026 GOWIN Semiconductor Corporation.
//All rights reserved.
//File Title: Timing Constraints file
//Tool Version: V1.9.11.03 Education 
//Created Time: 2026-09-24 10:50:56
create_clock -name sys_clk -period 37.037 -waveform {0 18.519} [get_ports {sys_clk}]
create_generated_clock -name soc_clk -source [get_ports {sys_clk}] -divide_by 5 -multiply_by 1 -duty_cycle 50 [get_pins {u_clkdiv/CLKOUT}]
