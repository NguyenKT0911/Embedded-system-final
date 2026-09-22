module instruction_memory(address, instr);
	input wire [31:0] address;
	output wire [31:0] instr;
	reg [31:0] memory [0:255];

	integer i;
	initial begin
		// nop = addi x0, x0, 0 (no operation)
		for(i = 0; i < 256; i = i + 1)
			memory[i] = 32'h00000013;
		$readmemh("program.hex", memory);
		
	end
	
   assign instr = memory[address[9:2]];
endmodule
