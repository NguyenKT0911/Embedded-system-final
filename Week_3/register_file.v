`timescale 1ns / 1ps
module register_file(rs1, rs2, rd, write_data, reg_write, clk, read_data1, read_data2);
	input wire [4:0] rs1, rs2, rd; // x0 -> x31
	input wire [31:0] write_data;
	input wire reg_write, clk;
	output wire [31:0] read_data1, read_data2;
	// Tao 32 thanh ghi 32 bit: x0, x1, x2, ..., x31
	reg [31:0] registers [31:0];
	// Read data
	// Note: x0 = 0 (always)
	assign read_data1 = (rs1 == 0) ? 0 : registers[rs1];
	assign read_data2 = (rs2 == 0) ? 0 : registers[rs2];
	// Write data
	always @(posedge clk)
		if(reg_write && (rd!=0))
			registers[rd] <= write_data;
			
endmodule
