`timescale 1ns / 1ps


module ricsv_cpu_tb;

	// Inputs
	reg clk;
	reg reset;

	// Outputs
	wire [31:0] pc;
	wire [31:0] instr;
	wire [31:0] alu_result;
	wire [31:0] read_data1;
	wire [31:0] read_data2;

	// Instantiate the Unit Under Test (UUT)
	ricsv_cpu uut (
		.clk(clk), 
		.reset(reset), 
		.pc(pc), 
		.instr(instr), 
		.alu_result(alu_result), 
		.read_data1(read_data1), 
		.read_data2(read_data2)
	);
	always #10 clk = !clk;
	
	initial begin
		// Initialize Inputs
		clk = 0;
		reset = 1;

		// Wait 100 ns for global reset to finish
		#100;
		reset = 0;
		#800;
		//-----------------------//
		$display("");
		$display("============================================");
		$display("          FINAL REGISTER VALUES");
		$display("============================================");

		$display("x1  = %0d  (expected 10)",
			  $signed(uut.dp1.rf0.registers[1]));
		$display("x2  = %0d  (expected 3)",
			  $signed(uut.dp1.rf0.registers[2]));

		$display("x3  = %0d  (ADD expected 13)",
			  $signed(uut.dp1.rf0.registers[3]));

		$display("x4  = %0d  (SUB expected 7)",
			  $signed(uut.dp1.rf0.registers[4]));

		$display("x5  = %0d  (XOR expected 9)",
			  $signed(uut.dp1.rf0.registers[5]));
		$display("x6  = %0d  (OR expected 11)",
			  $signed(uut.dp1.rf0.registers[6]));

		$display("x7  = %0d  (AND expected 2)",
			  $signed(uut.dp1.rf0.registers[7]));

		$display("x8  = %0d  (SLL expected 80)",
			  $signed(uut.dp1.rf0.registers[8]));

		$display("x9  = %0d  (SRL expected 1)",
			  $signed(uut.dp1.rf0.registers[9]));

		$display("x10 = %0d  (expected -16)",
			  $signed(uut.dp1.rf0.registers[10]));
		$display("x11 = %0d  (SRA expected -2)",
			  $signed(uut.dp1.rf0.registers[11]));

		$display("x12 = %0d  (SLT expected 1)",
			  $signed(uut.dp1.rf0.registers[12]));

		$display("x13 = %0d  (SLTU expected 0)",
			  $signed(uut.dp1.rf0.registers[13]));

		$display("x14 = %0d  (ADDI expected 5)",
			  $signed(uut.dp1.rf0.registers[14]));

		$display("x15 = %0d  (XORI expected 9)",
			  $signed(uut.dp1.rf0.registers[15]));
		$display("x16 = %0d  (ORI expected 15)",
			  $signed(uut.dp1.rf0.registers[16]));

		$display("x17 = %0d  (ANDI expected 2)",
			  $signed(uut.dp1.rf0.registers[17]));

		$display("x18 = %0d  (SLTI expected 1)",
			  $signed(uut.dp1.rf0.registers[18]));

		$display("x19 = %0d  (SLTIU expected 1)",
			  $signed(uut.dp1.rf0.registers[19]));
		$display("x20 = %0d  (SLLI expected 12)",
			  $signed(uut.dp1.rf0.registers[20]));

		$display("x21 = %0d  (SRLI expected 5)",
			  $signed(uut.dp1.rf0.registers[21]));

		$display("x22 = %0d  (SRAI expected -4)",
			  $signed(uut.dp1.rf0.registers[22]));
			  
		$display("x23 = %0d  (SRAI expected 100)",
			  $signed(uut.dp1.rf0.registers[23]));
			  
		$display("x24 = %0d  (SRAI expected 50)",
			  $signed(uut.dp1.rf0.registers[24]));
			  
		$display("mem[26] = %0d  (SRAI expected 50)",
			  $signed(uut.dp1.dm0.memory[26]));
			  
		$display("x25 = %0d  (SRAI expected 50)",
			  $signed(uut.dp1.rf0.registers[25]));
		//==================================================
		// BEQ
		//==================================================
		$display("x26 = %0d  (SRAI expected 5)",
			  $signed(uut.dp1.rf0.registers[26]));
			  
		$display("x27 = %0d  (SRAI expected 5)",
			  $signed(uut.dp1.rf0.registers[27]));
			  
		$display("x28 = %0d  (SRAI expected X)", // bi skip
			  $signed(uut.dp1.rf0.registers[28]));
			  
		$display("x29 = %0d  (SRAI expected 50)",
			  $signed(uut.dp1.rf0.registers[29]));
			  
		//==================================================
		// BEQ KHONG NHAY
		//==================================================
		$display("x30 = %0d  (SRAI expected 7)",
			  $signed(uut.dp1.rf0.registers[30]));
		$display("x31 = %0d  (SRAI expected 77)", // khong nhay => thuc thi
			  $signed(uut.dp1.rf0.registers[31]));
		$display("============================================");
		$finish;
	end
	initial begin
        // Monitor
        $monitor(
        "T=%0t | PC=%3d | instr=%h | rs1=%4d | rs2=%4d | ALU=%4d",
        $time, pc, instr, $signed(read_data1), $signed(read_data2), $signed(alu_result));
	end
      
endmodule

