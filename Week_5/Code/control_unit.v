`timescale 1ns / 1ps

module control_unit(opcode, funct3, funct7, alu_sel, alu_src, reg_write, mem_write, mem_to_reg, branch_type, jump, jalr, lui, auipc);
	input wire [6:0] opcode;
	input wire [2:0] funct3;
	input wire [6:0] funct7;
	output reg [3:0] alu_sel;
	output reg reg_write, alu_src, mem_write, mem_to_reg, jump, jalr, lui, auipc;
	output reg [2:0] branch_type;
	localparam br_none = 3'b000, br_beq = 3'b001, br_bne = 3'b010, br_blt = 3'b011, br_bge = 3'b100, br_bltu = 3'b101, br_bgeu = 3'b110;
	always @(*) begin
		alu_sel = 4'b0000;
		reg_write = 1'b0;
		alu_src = 1'b0;
		mem_write = 1'b0;
		mem_to_reg = 1'b0;
		branch_type = br_none;
		jump = 1'b0;
		jalr = 1'b0;
		lui = 1'b0;
		auipc = 1'b0;
		case(opcode)
		// R-type
			7'b0110011: begin 
				reg_write = 1'b1;
				alu_src = 1'b0;
				mem_write = 1'b0;
				mem_to_reg = 1'b0; // lay tu ALU result
				case(funct3)
					3'h0: begin
						if(funct7 == 7'h00) alu_sel = 4'b0000; // ADD
						else if(funct7 == 7'h20) alu_sel = 4'b0001; // SUB
						else alu_sel = 4'b0000;
					end
					3'h4: alu_sel = 4'b0010; // XOR
					3'h6:	alu_sel = 4'b0011; // OR
					3'h7:	alu_sel = 4'b0100; // AND
					3'h1:	alu_sel = 4'b0101; // SLL
					3'h5: begin
						if(funct7 == 7'h00) alu_sel = 4'b0110; // SRL
						else if(funct7 == 7'h20) alu_sel = 4'b0111; // SRA
						else alu_sel = 4'b0000;
					end
					3'h2: alu_sel = 4'b1000; // SLT
					3'h3:	alu_sel = 4'b1001; // SLTU
					default: alu_sel = 4'b0000;
				endcase
			end
		// I-type
			7'b0010011: begin
				reg_write = 1'b1;
				alu_src = 1'b1;
				mem_write = 1'b0;
				mem_to_reg = 1'b0; // lay tu ALU_result
				case(funct3)
					3'h0: alu_sel = 4'b0000; // addi
					3'h4: alu_sel = 4'b0010; // xori
					3'h6:	alu_sel = 4'b0011; // ori
					3'h7:	alu_sel = 4'b0100; // andi
					3'h1:	alu_sel = 4'b0101; // slli
					3'h5: begin
						if(funct7 == 7'h00) alu_sel = 4'b0110; // SRL
						else if(funct7 == 7'h20) alu_sel = 4'b0111; // SRA
						else alu_sel = 4'b0000;
					end
					3'h2: alu_sel = 4'b1000; // slti
					3'h3:	alu_sel = 4'b1001; // sltiu
					default: alu_sel = 4'b0000;
				endcase
			end
		// Load I-type
			7'b0000011: begin
				reg_write = 1'b1; // ghi vao register
				alu_src = 1'b1;
				mem_to_reg = 1'b1; // lay tu data memory
				alu_sel = 4'b0000; // vi tat ca lenh load deu lay add
			end
		// Store
			7'b0100011: begin
				alu_src = 1'b1;
				mem_write = 1'b1; // ghi data
				alu_sel = 4'b0000; // vi tat ca lenh store deu lay add
			end
		// B-type
			7'b1100011: begin
				reg_write = 1'b0;
				alu_src   = 1'b0;
				mem_write = 1'b0;
				mem_to_reg = 1'b0;
				case(funct3)
					3'h0: branch_type = br_beq; // beq (rs1 == rs2)
					3'h1: branch_type = br_bne; // bne (rs1 != rs2)
					3'h4: branch_type = br_blt; // blt (signed(rs1) < signed(rs2))
					3'h5: branch_type = br_bge; // bge (signed(rs1) >= signed(rs2))
					3'h6: branch_type = br_bltu; // bltu (unsigned(rs1) < unsigned(rs2))
					3'h7: branch_type = br_bgeu; // bgeu (unsigned(rs1) >= unsigned(rs2))
					default: branch_type = br_none; // no branch
				endcase
			end
		// jal - J-type
			7'b1101111: begin
				reg_write = 1'b1;
				jump = 1'b1;
			end
		// jalr - I-type
			7'b1100111: begin
				reg_write = 1'b1;
				jump = 1'b0;
				jalr = 1'b1;
				alu_src = 1'b1;
				alu_sel = 4'b0000; // ADD
			end
		// lui - U-type
			7'b0110111: begin
				lui = 1'b1;
				reg_write = 1'b1;
			end
		// auipc - U-type
			7'b0010111: begin
				auipc = 1'b1;
				reg_write = 1'b1;
			end
			default: begin
				alu_sel = 4'b0000;
				reg_write = 0;
			end
		endcase
		
	end
endmodule