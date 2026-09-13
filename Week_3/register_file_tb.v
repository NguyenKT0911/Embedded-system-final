`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer:
//
// Create Date:   10:25:28 09/06/2026
// Design Name:   register_file
// Module Name:   /home/ise/Documents/RICS-V/register_file/register_file_tb.v
// Project Name:  register_file
// Target Device:  
// Tool versions:  
// Description: 
//
// Verilog Test Fixture created by ISE for module: register_file
//
// Dependencies:
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
////////////////////////////////////////////////////////////////////////////////

module register_file_tb;

	// Inputs
	reg [4:0] rs1;
	reg [4:0] rs2;
	reg [4:0] rd;
	reg [31:0] write_data;
	reg reg_write;
	reg clk;

	// Outputs
	wire [31:0] read_data1;
	wire [31:0] read_data2;

	// Instantiate the Unit Under Test (UUT)
	register_file uut (
		.rs1(rs1), 
		.rs2(rs2), 
		.rd(rd), 
		.write_data(write_data), 
		.reg_write(reg_write), 
		.clk(clk), 
		.read_data1(read_data1), 
		.read_data2(read_data2)
	);
	always #10 clk = !clk;
	initial begin
		// Initialize Inputs
		rs1 = 0;
		rs2 = 0;
		rd = 0;
		write_data = 0;
		reg_write = 0;
		clk = 0;

		// Wait 100 ns for global reset to finish
		#20;
      rs1 = 5'd1;
		#20 // x1 = 10
		rs1 = 5'd0;
		reg_write = 1;
		rd = 5'd1;
		write_data = 32'd10;
		#50;
		reg_write = 0;
		#5;
		rs1 = 5'd1;
		#20; // x2 = 20
		reg_write = 1;
		rd = 5'd2;
		write_data = 32'd20;
		#50;
		reg_write = 0;
		rs2 = 5'd2;
		rs1 = 0;
		#50; // x0 = 36;
		reg_write = 1;
		rd = 0;
		write_data = 32'd36;
		#50;
		rs2 = 0;
		#30;
		$stop;
		// Add stimulus here

	end
   initial begin
		$monitor("time = %0t;    rs1 = %d;   rs2 = %d;   x1 = %d;   x2 = %d", $time, rs1, rs2, read_data1, read_data2);
	end
endmodule

