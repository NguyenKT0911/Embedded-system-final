`timescale 1ns / 1ps
module data_path(clk, pc, instr, alu_result, read_data1, read_data2, next_pc);
	input wire clk;
	input wire [31:0] instr, pc;
	output wire [31:0] alu_result, read_data1, read_data2, next_pc;
	// tach instruction
	wire [6:0] opcode;
	wire [4:0] rd, rs1, rs2;
	wire [2:0] funct3;
	wire [6:0] funct7;
	
	assign opcode = instr[6:0];
	assign rd = 	 instr[11:7];
	assign funct3 = instr[14:12];
	assign rs1 =    instr[19:15];
	assign rs2 = 	 instr[24:20];
	assign funct7 = instr[31:25];
	// control_unit
	wire [3:0] alu_sel;
	wire zero, alu_src, branch;
	wire [31:0] imm, alu_b, mem_read_data, write_back_data;
	wire reg_write, mem_write, mem_to_reg;
	wire pc_src;
	wire [31:0] pc_plus4, pc_branch;
	
	assign pc_src = (branch & zero); 
	assign pc_plus4 = pc + 32'd4;
	assign pc_branch = pc + imm;
	assign next_pc = (pc_src == 1) ? pc_branch : pc_plus4;
	
	control_unit cu0(.opcode(opcode), .funct3(funct3), .funct7(funct7), .alu_sel(alu_sel), .alu_src(alu_src),
							.reg_write(reg_write), .mem_write(mem_write), .mem_to_reg(mem_to_reg), .branch(branch));
	
	// immediate_generator
	immediate_generator imm0(.instr(instr), .imm(imm));
	
	// ALU
	assign alu_b = (alu_src == 0) ? read_data2 : imm;
	alu_32bit alu0(.a(read_data1), .b(alu_b), .alu_sel(alu_sel), .result(alu_result), .zero(zero));
	
	// data_memory
	assign write_back_data = (mem_to_reg == 1) ? mem_read_data : alu_result; // 
	data_memory dm0(.clk(clk), .mem_write(mem_write), .address(alu_result), .write_data(read_data2), .read_data(mem_read_data));
	
	// register_file
	register_file rf0(.rs1(rs1), .rs2(rs2), .rd(rd), .write_data(write_back_data), .reg_write(reg_write),
							.clk(clk), .read_data1(read_data1), .read_data2(read_data2));
	
endmodule
