`timescale 1ns / 1ps

module uart_tx #(
    parameter CLKS_PER_BIT = 234
)(
    input wire clk,
    input wire reset,
    input wire [7:0] tx_data,
    input wire tx_start,

    output reg tx,
    output reg tx_busy,
    output reg tx_done
);

    localparam IDLE  = 2'd0;
    localparam START = 2'd1;
    localparam DATA  = 2'd2;
    localparam STOP  = 2'd3;

    reg [1:0] state;
    reg [8:0] clk_count;
    reg [2:0] bit_index;
    reg [7:0] data_buffer;

    always @(posedge clk or posedge reset) begin

        if (reset) begin
            state       <= IDLE;
            clk_count   <= 0;
            bit_index   <= 0;
            data_buffer <= 0;
            tx          <= 1'b1;
            tx_busy     <= 1'b0;
            tx_done     <= 1'b0;
        end

        else begin

            tx_done <= 1'b0;

            case (state)

                IDLE: begin
                    tx       <= 1'b1;
                    tx_busy  <= 1'b0;
                    clk_count <= 0;
                    bit_index <= 0;

                    if (tx_start) begin
                        data_buffer <= tx_data;
                        tx_busy <= 1'b1;
                        state <= START;
                    end
                end

                START: begin
                    tx <= 1'b0;

                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 0;
                        state <= DATA;
                    end
                    else
                        clk_count <= clk_count + 1'b1;
                end

                DATA: begin
                    tx <= data_buffer[bit_index];

                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 0;

                        if (bit_index == 3'd7) begin
                            bit_index <= 0;
                            state <= STOP;
                        end
                        else
                            bit_index <= bit_index + 1'b1;
                    end
                    else
                        clk_count <= clk_count + 1'b1;
                end

                STOP: begin
                    tx <= 1'b1;

                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 0;
                        tx_done <= 1'b1;
                        tx_busy <= 1'b0;
                        state <= IDLE;
                    end
                    else
                        clk_count <= clk_count + 1'b1;
                end

                default:
                    state <= IDLE;

            endcase
        end
    end

endmodule