`timescale 1ns / 1ps

// Loads little-endian instruction bytes into instruction memory. A 100 ms
// inter-byte idle gap marks the end of a complete program image.
module uart_loader #(
    parameter integer GAP_CLKS = 2700000 // 100 ms at 27 MHz
)(
    input  wire        clk,
    input  wire        reset,
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,
    output reg         loader_we,
    output reg  [7:0]  loader_addr,
    output reg  [31:0] loader_data,
    output reg         program_loaded
);
    reg [1:0]  byte_count;
    reg [7:0]  next_addr;
    reg [31:0] instruction_buffer;
    reg        program_seen;
    reg [21:0] idle_count;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            byte_count         <= 2'd0;
            next_addr          <= 8'd0;
            instruction_buffer <= 32'd0;
            loader_addr        <= 8'd0;
            loader_data        <= 32'd0;
            loader_we          <= 1'b0;
            program_loaded     <= 1'b0;
            program_seen       <= 1'b0;
            idle_count         <= 22'd0;
        end else begin
            loader_we <= 1'b0;

            if (rx_valid) begin
                idle_count     <= 22'd0;
                program_seen   <= 1'b1;
                program_loaded <= 1'b0;

                // The first byte after power-up or a completed transfer
                // starts a fresh image at instruction address zero.
                if (!program_seen || program_loaded) begin
                    next_addr          <= 8'd0;
                    byte_count         <= 2'd1;
                    instruction_buffer <= {24'd0, rx_data};
                end else begin
                    case (byte_count)
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
                            loader_addr <= next_addr;
                            loader_data <= {rx_data, instruction_buffer[23:0]};
                            loader_we   <= 1'b1;
                            next_addr   <= next_addr + 1'b1;
                            byte_count  <= 2'd0;
                        end
                    endcase
                end
            end else if (program_seen && !program_loaded) begin
                if (idle_count == GAP_CLKS - 1) begin
                    if (byte_count == 2'd0) begin
                        // Delay autostart until after the last synchronous
                        // instruction-memory write has committed.
                        program_loaded <= 1'b1;
                    end else begin
                        // An incomplete transfer can be retried from byte 0.
                        byte_count   <= 2'd0;
                        next_addr    <= 8'd0;
                        program_seen <= 1'b0;
                    end
                end else begin
                    idle_count <= idle_count + 1'b1;
                end
            end
        end
    end
endmodule
