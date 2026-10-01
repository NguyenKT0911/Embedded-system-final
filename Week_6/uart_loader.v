`timescale 1ns / 1ps

module uart_loader(
    clk,
    reset,
    rx_data,
    rx_valid,
    loader_we,
    loader_addr,
    loader_data
);
    input wire clk;
    input wire reset;
    input wire [7:0] rx_data;
    input wire       rx_valid;
    output reg        loader_we;
    output reg [7:0]  loader_addr;
    output reg [31:0] loader_data;
    reg [1:0] byte_count;
    reg [7:0] next_addr;
    reg [31:0] instruction_buffer;
    always @(posedge clk or posedge reset) begin
        if(reset) begin
            byte_count         <= 2'd0;
            next_addr          <= 8'd0;
            instruction_buffer <= 32'd0;
            loader_addr        <= 8'd0;
            loader_data        <= 32'd0;
            loader_we          <= 1'b0;
        end
        else begin
            loader_we <= 1'b0;
            if(rx_valid) begin
                case(byte_count)
                    2'd0: begin
                        instruction_buffer[7:0] <= rx_data;
                        byte_count <= 2'd1;
                    end
                    2'd1: begin
                        instruction_buffer[15:8] <= rx_data;
                        byte_count <= 2'd2;
                    end
                    2'd2: begin
                        instruction_buffer[23:16] <= rx_data;
                        byte_count <= 2'd3;
                    end
                    2'd3: begin
                        // Address of current instruction
                        loader_addr <= next_addr;
                        // Complete current instruction
                        loader_data <= {
                            rx_data,
                            instruction_buffer[23:0]
                        };
                        // Generate write pulse
                        loader_we <= 1'b1;
                        // Address for next instruction
                        next_addr <= next_addr + 1'b1;
                        byte_count <= 2'd0;
                    end
                    default: begin
                        byte_count <= 2'd0;
                    end
                endcase
            end
        end
    end
endmodule
