module instruction_memory(clk, address, instr, loader_we, loader_addr, loader_data);
	input wire clk;
    // cpu
    input wire [31:0] address;
	output wire [31:0] instr;
	// loader
    input wire loader_we;
    input wire [7:0] loader_addr;
    input wire [31:0] loader_data;

    reg [31:0] memory [0:255];
 
	integer i;
	initial begin
		// nop = addi x0, x0, 0 (no operation)
		for(i = 0; i < 256; i = i + 1)
			memory[i] = 32'h00000013;
//		$readmemh("program.hex", memory);
		
	end
    // Loader
    always @(posedge clk)
        if(loader_we)
            memory[loader_addr] <= loader_data;
    
    assign instr = memory[address[9:2]];
endmodule
