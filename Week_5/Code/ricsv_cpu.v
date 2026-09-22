`timescale 1ns / 1ps

module ricsv_cpu(clk, reset, pc, instr, alu_result, read_data1, read_data2);
	input wire clk, reset;
	// nap gia tri tu ben ngoai
	// output
	output wire [31:0] pc, instr, alu_result, read_data1, read_data2;
	wire [31:0] next_pc;
	
	data_path dp1(.clk(clk), .pc(pc), .instr(instr), .alu_result(alu_result), .read_data1(read_data1), .read_data2(read_data2), .next_pc(next_pc));
	
	instruction_memory im1(.address(pc), .instr(instr));
	
	program_counter pc1(.clk(clk), .reset(reset), .pc(pc), .next_pc(next_pc));
endmodule
