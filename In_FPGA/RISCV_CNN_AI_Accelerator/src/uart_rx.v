`timescale 1ns/1ps

module uart_rx #(
    parameter integer CLK_FREQ  = 5_400_000,
    parameter integer BAUD_RATE = 115200
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    output reg  [7:0] data_out,
    output reg        data_valid,
    output reg        framing_error
);
    localparam integer CLKS_PER_BIT = (CLK_FREQ + BAUD_RATE/2) / BAUD_RATE;
    localparam integer HALF_CLKS    = CLKS_PER_BIT / 2;

    localparam [2:0] IDLE      = 3'd0;
    localparam [2:0] START_BIT = 3'd1;
    localparam [2:0] DATA_BITS = 3'd2;
    localparam [2:0] STOP_BIT  = 3'd3;
    localparam [2:0] CLEANUP   = 3'd4;

    reg rx_meta;
    reg rx_sync;
    reg [2:0] state;
    reg [15:0] clk_count;
    reg [2:0] bit_index;
    reg [7:0] rx_data;

    always @(posedge clk) begin
        if (rst) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            state         <= IDLE;
            clk_count     <= 16'd0;
            bit_index     <= 3'd0;
            rx_data       <= 8'd0;
            data_out      <= 8'd0;
            data_valid    <= 1'b0;
            framing_error <= 1'b0;
        end else begin
            data_valid <= 1'b0;
            case (state)
                IDLE: begin
                    clk_count     <= 16'd0;
                    bit_index     <= 3'd0;
                    framing_error <= 1'b0;
                    if (!rx_sync)
                        state <= START_BIT;
                end

                START_BIT: begin
                    if (clk_count == HALF_CLKS - 1) begin
                        clk_count <= 16'd0;
                        state <= rx_sync ? IDLE : DATA_BITS;
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                DATA_BITS: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 16'd0;
                        rx_data[bit_index] <= rx_sync;
                        if (bit_index == 3'd7) begin
                            bit_index <= 3'd0;
                            state <= STOP_BIT;
                        end else begin
                            bit_index <= bit_index + 1'b1;
                        end
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                STOP_BIT: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 16'd0;
                        if (rx_sync) begin
                            data_out   <= rx_data;
                            data_valid <= 1'b1;
                        end else begin
                            framing_error <= 1'b1;
                        end
                        state <= CLEANUP;
                    end else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end

                CLEANUP: state <= IDLE;

                default: begin
                    state         <= IDLE;
                    data_valid    <= 1'b0;
                    framing_error <= 1'b0;
                end
            endcase
        end
    end
endmodule
