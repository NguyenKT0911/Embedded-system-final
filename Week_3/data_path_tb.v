`timescale 1ns / 1ps

module data_path_tb;

	// Inputs
	reg clk;
	reg [31:0] instr;
	reg ext_reg_write;
	reg [4:0] ext_rd;
	reg [31:0] ext_write_data;

	// Outputs
	wire [31:0] alu_result;
	wire [31:0] read_data1;
	wire [31:0] read_data2;

	// Instantiate the Unit Under Test (UUT)
	data_path uut (
		.clk(clk), 
		.instr(instr), 
		.alu_result(alu_result), 
		.read_data1(read_data1), 
		.read_data2(read_data2), 
		.ext_reg_write(ext_reg_write), 
		.ext_rd(ext_rd), 
		.ext_write_data(ext_write_data)
	);
	always #10 clk = !clk;
	
	initial begin
		// Initialize Inputs
		clk = 0;
		instr = 0;
		ext_reg_write = 0;
		ext_rd = 0;
		ext_write_data = 0;

		// Wait 100 ns for global reset to finish
		#10;
      // nap x1 = 10
		ext_reg_write = 1'b1;
		#10;
		ext_rd = 5'd1;
		ext_write_data = 32'd36;
		#50;
		// nap x2 = 20
		ext_rd = 5'd2;
		ext_write_data = 32'd13;
		#50;
		ext_reg_write = 0;
		//-----------------------//
		// add x5 = x1 + x2
		instr = {7'h0, 5'd2, 5'd1, 3'h0, 5'd5, 7'b0110011}; 
		#50;
		// sub x6 = x2 - x1
		instr = {7'h20, 5'd2, 5'd1, 3'h0, 5'd6, 7'b0110011};
		#50;
		// and x9 = x5 & x6
		instr = {7'h0, 5'd6, 5'd5, 3'h7, 5'd9, 7'b0110011};
		#50;
		$stop;
	end
	initial begin
        // Monitor
        $monitor("Time=%0t | instr=%h | rs1_data=%d | rs2_data=%d | alu=%d | x5=%d | x6=%d | x9 = %d",
						$time, instr, read_data1, read_data2, alu_result, uut.rf0.registers[5], uut.rf0.registers[6], uut.rf0.registers[9]);
	end
endmodule

