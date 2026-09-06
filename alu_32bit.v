`timescale 1ns / 1ps
module alu_32bit(a, b, alu_sel, result, zero);
	input wire [31:0] a, b;
	input wire [3:0] alu_sel;
	output reg [31:0] result;
	output zero;
	localparam add = 4'b0000, sub = 4'b0001, op_xor = 4'b0010;
	localparam op_or = 4'b0011, op_and = 4'b0100, sll = 4'b0101;
	localparam srl = 4'b0110, sra = 4'b0111, slt = 4'b1000;
	localparam sltu = 4'b1001;
	always @(*) begin
		case(alu_sel)
			add: result = a + b;
			sub: result = a - b;
			op_xor: result = a ^ b;
			op_or: result = a | b;
			op_and: result = a & b;
			sll: result = a << b[4:0]; // dich trai 32 bit => can 5 bit
			srl: result = a >> b[4:0];
			sra: result = $signed(a) >>> b[4:0]; // giu lai bit dau
			slt: result = ($signed(a) < $signed(b)); // so sanh co dau
			sltu: result = (a < b); // so sanh khong dau
			default: result = 32'b0;
		endcase
	end
	assign zero = (result == 32'b0);

endmodule
