`timescale 1ns / 1ps

module control_unit(opcode, funct3, funct7, alu_sel, reg_write);
	input wire [6:0] opcode;
	input wire [2:0] funct3;
	input wire [6:0] funct7;
	output reg [3:0] alu_sel;
	output reg reg_write;
	always @(*) begin
		alu_sel = 4'b0000;
		reg_write = 0;
		case(opcode)
			7'b0110011: begin // R-type
				reg_write = 1;
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
			default: begin
				alu_sel = 4'b0000;
				reg_write = 0;
			end
		endcase
		
	end
endmodule
