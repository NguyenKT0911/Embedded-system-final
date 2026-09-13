`timescale 1ns / 1ps

module program_counter(clk, reset, next_pc, pc);
	input wire clk, reset;
	input wire [31:0] next_pc;
	output reg [31:0] pc;
	
	always @(posedge clk, posedge reset)
		if(reset) pc <= 32'd0;
		else pc <= next_pc;
		
endmodule
