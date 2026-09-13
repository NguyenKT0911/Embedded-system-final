`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer:
//
// Create Date:   03:43:47 09/04/2026
// Design Name:   alu_32bit
// Module Name:   /home/ise/Documents/alu_32bit/alu_32bit_tb.v
// Project Name:  alu_32bit
// Target Device:  
// Tool versions:  
// Description: 
//
// Verilog Test Fixture created by ISE for module: alu_32bit
//
// Dependencies:
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
////////////////////////////////////////////////////////////////////////////////

module alu_32bit_tb;

	// Inputs
	reg [31:0] a;
	reg [31:0] b;
	reg [3:0] alu_sel;

	// Outputs
	wire [31:0] result;
	wire zero;

	// Instantiate the Unit Under Test (UUT)
	alu_32bit uut (
		.a(a), 
		.b(b), 
		.alu_sel(alu_sel), 
		.result(result), 
		.zero(zero)
	);

	initial begin
		// Initialize Inputs
		a = 0;
		b = 0;
		alu_sel = 0;

		// Wait 100 ns for global reset to finish
		#100;
      // Test 1: add, sub, xor, or , and
		a = 32'd36; b= 32'd69; 
		alu_sel = 4'd0; // add
		#100;
		alu_sel = 4'd1; // sub
		#100;
		alu_sel = 4'd2; // xor
		#100;
		alu_sel = 4'd3; // or
		#100;
		alu_sel = 4'd4; // and
		#100;
		// Test 2: sll, srl, sra, slt, sltu
		a = 32'd36; b = 32'd6;
		// a = 0010 0100
		alu_sel = 4'd5; // sll
		#100;
		alu_sel = 4'd6; // srl
		#100;
		a = -32'd36;
		alu_sel = 4'd7; // sra
		#100;
		a = -32'd36; b = -32'd69;
		alu_sel = 4'd8; // slt
		#100;
		a = 32'd36; b = 32'd69;
		alu_sel = 4'd9; // sltu
		#100;
		
		$stop;
		// Add stimulus here

	end
      
endmodule

