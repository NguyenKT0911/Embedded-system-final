`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer:
//
// Create Date:   09:34:33 09/06/2026
// Design Name:   control_unit
// Module Name:   /home/ise/Documents/control_unit/control_unit_tb.v
// Project Name:  control_unit
// Target Device:  
// Tool versions:  
// Description: 
//
// Verilog Test Fixture created by ISE for module: control_unit
//
// Dependencies:
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
////////////////////////////////////////////////////////////////////////////////

module control_unit_tb;

	// Inputs
	reg [6:0] opcode;
	reg [2:0] funct3;
	reg [6:0] funct7;

	// Outputs
	wire [3:0] alu_sel;

	// Instantiate the Unit Under Test (UUT)
	control_unit uut (
		.opcode(opcode), 
		.funct3(funct3), 
		.funct7(funct7), 
		.alu_sel(alu_sel)
	);

	initial begin
		// Initialize Inputs
		opcode = 0;
		funct3 = 0;
		funct7 = 0;

		// Wait 100 ns for global reset to finish
		#100;
      opcode = 7'b0110011;
		funct3 = 3'h0;
		funct7 = 7'h0;
		#100;
		funct7 = 7'h20;
		#100;
		funct3 = 3'h4;
		#100;
		funct3 = 3'h6;
		#100;
		funct3 = 3'h7;
		#100;
		funct3 = 3'h1;
		#100;
		funct3 = 3'h5;
		funct7 = 7'h0;
		#100;
		funct7 = 7'h20;
		#100;
		funct3 = 3'h2;
		#100;
		funct3 = 3'h3;
		#100;
		funct3 = 3'h9;
		funct7 = 7'h36;
		$stop;
		// Add stimulus here

	end
   initial begin
		$monitor("Time=%0t | opcode=%b | funct3=%h | funct7=%h | alu_sel=%b",
                  $time, opcode, funct3, funct7, alu_sel);
	end
endmodule

