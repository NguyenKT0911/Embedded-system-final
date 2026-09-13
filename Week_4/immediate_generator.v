`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    12:10:16 09/10/2026 
// Design Name: 
// Module Name:    immediate_generator 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module immediate_generator(instr, imm);
	input wire [31:0] instr;
	output reg [31:0] imm;
	always @(*) begin
		case(instr[6:0]) // xet opcode
			7'b0010011: // I-type
				imm = {{20{instr[31]}} ,instr[31:20]}; // lay 12 bit cho imm, con lai la bit dau
			7'b0000011: // Load I-type
				imm = {{20{instr[31]}} ,instr[31:20]}; // lay 12 bit cho imm, con lai la bit dau
			7'b0100011: // S-type
				imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
			7'b1100011: // B-type
				imm = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
			default:
				imm = 32'b0;
		endcase
	end
	
endmodule
