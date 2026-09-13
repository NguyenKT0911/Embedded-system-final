`timescale 1ns / 1ps

module data_memory(clk, mem_write, address, write_data, read_data);
	input wire clk, mem_write; // cho phep ghi hay ko
	input wire [31:0] address, write_data;
	output wire [31:0] read_data;
	
	reg [31:0] memory[0:255];
	// Read 
	assign read_data = memory[address[9:2]];
	// Write
	always @(posedge clk)
		if(mem_write)
			memory[address[9:2]] <= write_data;
			
endmodule
