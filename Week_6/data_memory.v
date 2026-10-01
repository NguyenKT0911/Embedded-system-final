`timescale 1ns / 1ps

module data_memory(clk, mem_write, address, write_data, read_data, funct3);
	input wire clk, mem_write; // cho phep ghi hay ko
	input wire [2:0] funct3;
	input wire [31:0] address, write_data;
	output reg [31:0] read_data;
	
	reg [31:0] memory[0:255];
	reg [7:0] selected_byte;
	reg [15:0] selected_halfword;
	wire [31:0] word_data;
	reg [31:0] write_word;
	assign word_data = memory[address[9:2]];
	// Byte selection
	always @(*) begin
		case(address[1:0])
			2'b00: selected_byte = word_data[7:0];
			2'b01: selected_byte = word_data[15:8];
			2'b10: selected_byte = word_data[23:16];
			2'b11: selected_byte = word_data[31:24];
			default: selected_byte = 8'b0;
		endcase
	end
	always @(*) begin
		case(address[1])
			1'b0: selected_halfword = word_data[15:0];
			1'b1: selected_halfword = word_data[31:16];
			default: selected_halfword = 16'b0;
		endcase
	end
	// Load/Read
	always @(*) begin
		case(funct3)
			3'h0: // lb sign-extension
				read_data = {{24{selected_byte[7]}} ,selected_byte};
			3'h1: // lh sign-extension
				read_data = {{16{selected_halfword[15]}} ,selected_halfword};
			3'h2: // lw
				read_data = word_data;
			3'h4: // lbu zero-extension
				read_data = {24'b0, selected_byte};
			3'h5: // lhu zero-extension
				read_data = {16'b0, selected_halfword};
			default: read_data = 32'b0;
		endcase
	end
	// Store/Write
	always @(*) begin
		write_word = word_data;
		case(funct3)
			3'h0: begin// sb
				case(address[1:0])
					2'b00:
						write_word = {word_data[31:8], write_data[7:0]};
					2'b01:
						write_word = {word_data[31:16], write_data[7:0], word_data[7:0]};
					2'b10:
						write_word = {word_data[31:24], write_data[7:0], word_data[15:0]};
					2'b11:
						write_word = {write_data[7:0], word_data[23:0]};
				endcase
			end
			3'h1: begin// sh
				case(address[1])
					1'b0:
						write_word = {word_data[31:16], write_data[15:0]};
					1'b1:
						write_word = {write_data[15:0], word_data[15:0]};
				endcase
			end
			3'h2: // sw
				write_word = write_data;
			default:
				write_word = word_data;
		endcase
	end
	always @(posedge clk) 
		if(mem_write) 
			memory[address[9:2]] <= write_word;
	

			
endmodule
