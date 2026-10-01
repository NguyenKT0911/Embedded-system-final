`timescale 1ns / 1ps

module ricsv_cpu(clk, reset, mem_read_data, mem_addr, mem_write_data, mem_write, mem_funct3, loader_addr, loader_data, loader_we, debug_pc);
	input wire clk, reset;
	
	input wire [31:0] mem_read_data;
    // loader
    input wire        loader_we;
    input wire [7:0]  loader_addr;
    input wire [31:0] loader_data;

    output wire [31:0] mem_addr;
    output wire [31:0] mem_write_data;
    output wire mem_write;
    output wire [2:0] mem_funct3;

    
	// nap gia tri tu ben ngoai
	// internal cpu
	
	wire [31:0] pc, instr, alu_result, read_data1, read_data2;
	wire [31:0] next_pc;

    // debug pc
	output wire [31:0] debug_pc;

    assign debug_pc = pc;
	// data_path
	data_path dp1(.clk(clk), .pc(pc), .instr(instr), .alu_result(alu_result), .read_data1(read_data1), .read_data2(read_data2), .next_pc(next_pc),
					  .mem_read_data(mem_read_data), .mem_addr(mem_addr), .mem_write_data(mem_write_data), .mem_write(mem_write), .mem_funct3(mem_funct3));
	
	// instruction_memory
    instruction_memory im1(.clk(clk), .address(pc), .instr(instr), .loader_we(loader_we), .loader_addr(loader_addr), .loader_data(loader_data));
//	instruction_memory im1(.address(pc), .instr(instr));
	
	// program_counter
	program_counter pc1(.clk(clk), .reset(reset), .pc(pc), .next_pc(next_pc));
endmodule
