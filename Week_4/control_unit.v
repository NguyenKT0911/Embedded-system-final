`timescale 1ns / 1ps

module control_unit(opcode, funct3, funct7, alu_sel, alu_src, reg_write, mem_write, mem_to_reg, branch);
	input wire [6:0] opcode;
	input wire [2:0] funct3;
	input wire [6:0] funct7;
	output reg [3:0] alu_sel;
	output reg reg_write, alu_src, mem_write, mem_to_reg, branch;
	always @(*) begin
		alu_sel = 4'b0000;
		reg_write = 1'b0;
		alu_src = 1'b0;
		mem_write = 1'b0;
		mem_to_reg = 1'b0;
		branch = 1'b0;
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
				mem_write = 1'b0; // doc data
				mem_to_reg = 1'b1; // lay tu data memory
				case(funct3)
					3'h2: alu_sel = 4'b0000; // lw : Add : rs1 + offset
					default: alu_sel = 4'b0000;
				endcase
			end
		// Store
			7'b0100011: begin
				reg_write = 1'b0; // khong ghi vao register
				alu_src = 1'b1;
				mem_write = 1'b1; // ghi data
				mem_to_reg = 1'b0; // Khong dung
				case(funct3)
					3'h2: alu_sel = 4'b0000; // sw: Add: rs1 + offset
					default: alu_sel = 4'b0000;
				endcase
			end
		// B-type
			7'b1100011: begin
				reg_write = 1'b0;
				alu_src   = 1'b0;
				mem_write = 1'b0;
				mem_to_reg = 1'b0;
				branch    = 1'b1; // nhay
				case(funct3)
					3'h0: alu_sel = 4'b0001; // Sub: kiem tra rs1 - rs2 == 0 -> Zero = 1 => Jump
					default: alu_sel = 4'b0000;
				endcase
			end
			
			default: begin
				alu_sel = 4'b0000;
				reg_write = 0;
			end
		endcase
		
	end
endmodule