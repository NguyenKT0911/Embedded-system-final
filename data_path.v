`timescale 1ns / 1ps
module data_path(clk, instr, alu_result, read_data1, read_data2, ext_reg_write, ext_rd, ext_write_data);
	input wire clk;
	input wire [31:0] instr;
	output wire [31:0] alu_result, read_data1, read_data2;

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
	
	// nap gia tri tu ben ngoai, sau nay thay bang I-type
	input wire ext_reg_write;
   input wire [4:0] ext_rd;
   input wire [31:0] ext_write_data;
	
	wire reg_write;
	wire [4:0] rf_rd;
   wire [31:0] rf_write_data;
   wire rf_write_enable;
	
	assign rf_rd = ext_reg_write ? ext_rd : rd;
	assign rf_write_data = ext_reg_write ? ext_write_data : alu_result;
	assign rf_write_enable = ext_reg_write ? 1'b1 : reg_write;
	
	// control_unit
	wire [3:0] alu_sel;
	wire zero;
	control_unit cu0(opcode, funct3, funct7, alu_sel, reg_write);
	// ALU
	alu_32bit alu0(read_data1, read_data2, alu_sel, alu_result, zero);
	// register_file
	register_file rf0(rs1, rs2, rf_rd, rf_write_data, rf_write_enable, clk, read_data1, read_data2);

endmodule
