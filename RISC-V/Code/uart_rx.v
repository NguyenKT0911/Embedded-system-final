`timescale 1ns / 1ps

module uart_rx(
    clk,
    reset,
    rx,
    data,
    data_valid
);

    input wire clk;
    input wire reset;
    input wire rx;
    output reg [7:0] data;
    output reg data_valid;
    parameter CLKS_PER_BIT = 234;
    // =========================
    // State definition
    // =========================
    localparam IDLE       = 3'd0;
    localparam START_BIT  = 3'd1;
    localparam DATA_BITS  = 3'd2;
    localparam STOP_BIT   = 3'd3;
    localparam CLEANUP    = 3'd4;
    reg [2:0] state;
    reg [8:0] clk_count;
    reg [2:0] bit_index;
    reg [7:0] rx_data;
    // =========================
    // UART Receiver FSM
    // =========================
    always @(posedge clk or posedge reset) begin
        if(reset) begin
            state      <= IDLE;
            clk_count  <= 0;
            bit_index  <= 0;
            rx_data    <= 0;
            data       <= 0;
            data_valid <= 0;
        end
        else begin
            case(state)
                // =====================
                // Wait for start bit
                // =====================
                IDLE: begin
                    data_valid <= 0;
                    clk_count  <= 0;
                    bit_index  <= 0;
                    if(rx == 1'b0)
                        state <= START_BIT;
                end
                // =====================
                // Check middle of start
                // =====================
                START_BIT: begin
                    if(clk_count == (CLKS_PER_BIT - 1) / 2) begin
                        if(rx == 1'b0) begin
                            clk_count <= 0;
                            state <= DATA_BITS;
                        end
                        else begin
                            state <= IDLE;
                        end
                    end
                    else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end
                // =====================
                // Receive 8 data bits
                // =====================
                DATA_BITS: begin
                    if(clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 0;
                        rx_data[bit_index] <= rx;
                        if(bit_index == 3'd7) begin
                            bit_index <= 0;
                            state <= STOP_BIT;
                        end
                        else begin
                            bit_index <= bit_index + 1'b1;
                        end
                    end
                    else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end
                // =====================
                // Stop bit
                // =====================
                STOP_BIT: begin
                    if(clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 0;
                        if(rx == 1'b1) begin
                            data <= rx_data;
                            data_valid <= 1'b1;
                        end
                        state <= CLEANUP;
                    end
                    else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end
                // =====================
                // data_valid = 1 clock
                // =====================
                CLEANUP: begin
                    data_valid <= 0;
                    state <= IDLE;
                end
                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule
