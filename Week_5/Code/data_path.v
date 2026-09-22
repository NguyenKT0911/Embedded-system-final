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
	// Branch
	localparam br_none = 3'b000, br_beq = 3'b001, br_bne = 3'b010, br_blt = 3'b011, br_bge = 3'b100, br_bltu = 3'b101, br_bgeu = 3'b110;
	
	// Parameter
	wire [3:0] alu_sel;
	wire [31:0] imm, alu_b, mem_read_data, write_back_data;
	wire reg_write, mem_write, mem_to_reg;
	wire [31:0] pc_plus4, pc_branch, pc_jalr, pc_auipc;
	wire zero, alu_src, jump, jalr, lui, auipc;
	wire [2:0] branch_type;
	reg branch_taken;
	assign pc_plus4 = pc + 32'd4;
	assign pc_branch = pc + imm;
	assign pc_jalr = {alu_result[31:1], 1'b0};
	assign pc_auipc = pc + imm;
	assign next_pc = (jalr == 1) ? pc_jalr : ((branch_taken | jump) ? pc_branch : pc_plus4);
	
	// Branch
	always @(*) begin 
		case(branch_type)
			br_beq: branch_taken = (read_data1 == read_data2);
			br_bne: branch_taken = (read_data1 != read_data2);
			br_blt: branch_taken = ($signed(read_data1) < $signed(read_data2));
			br_bge: branch_taken = ($signed(read_data1) >= $signed(read_data2));
			br_bltu: branch_taken = (read_data1 < read_data2);
			br_bgeu: branch_taken = (read_data1 >= read_data2);
			default: branch_taken = 1'b0;
		endcase
	end
	// control_unit	
	control_unit cu0(.opcode(opcode), .funct3(funct3), .funct7(funct7), .alu_sel(alu_sel), .alu_src(alu_src),
							.reg_write(reg_write), .mem_write(mem_write), .mem_to_reg(mem_to_reg), 
							.branch_type(branch_type), .jump(jump), .jalr(jalr), .lui(lui), .auipc(auipc));
	
	// immediate_generator
	immediate_generator imm0(.instr(instr), .imm(imm));
	
	// ALU
	assign alu_b = (alu_src == 0) ? read_data2 : imm;
	alu_32bit alu0(.a(read_data1), .b(alu_b), .alu_sel(alu_sel), .result(alu_result), .zero(zero));
	
	// data_memory
	//assign write_back_data = (auipc == 1) ? (pc_auipc :(jump == 1) ? pc_plus4 : ((mem_to_reg == 1) ? mem_read_data : alu_result)); // 
	assign write_back_data =
    (jump | jalr) ? pc_plus4 :
    lui           ? imm :
    auipc         ? pc_auipc :
    mem_to_reg    ? mem_read_data :
                    alu_result;
	data_memory dm0(.clk(clk), .mem_write(mem_write), .address(alu_result), .write_data(read_data2), .read_data(mem_read_data), .funct3(funct3));
	
	// register_file
	register_file rf0(.rs1(rs1), .rs2(rs2), .rd(rd), .write_data(write_back_data), .reg_write(reg_write),
							.clk(clk), .read_data1(read_data1), .read_data2(read_data2));
	
endmodule
