`timescale 1ns/1ps

module uart_tx #(
    parameter integer CLK_FREQ  = 5_400_000,
    parameter integer BAUD_RATE = 115200
)(
    input  wire       clk,
    input  wire       rst,

    input  wire [7:0] tx_data,
    input  wire       tx_valid,

    output wire       tx_ready,
    output reg        tx
);

    // =========================================================
    // Baud-rate divider
    // =========================================================
    localparam integer CLKS_PER_BIT =
        (CLK_FREQ + BAUD_RATE/2) / BAUD_RATE;

    // =========================================================
    // UART TX states
    // =========================================================
    localparam [1:0]
        IDLE  = 2'd0,
        START = 2'd1,
        DATA  = 2'd2,
        STOP  = 2'd3;

    // =========================================================
    // Internal registers
    // =========================================================
    reg [1:0]  state;
    reg [15:0] clk_count;
    reg [2:0]  bit_index;
    reg [7:0]  data_reg;

    // UART can accept new data only when idle
    assign tx_ready = (state == IDLE);

    // =========================================================
    // UART TX sequential logic
    // =========================================================
    always @(posedge clk) begin
        if (rst) begin
            state     <= IDLE;
            clk_count <= 16'd0;
            bit_index <= 3'd0;
            data_reg  <= 8'd0;
            tx         <= 1'b1;
        end
        else begin
            case (state)

                // -------------------------------------------------
                // IDLE
                // UART line stays HIGH
                // Wait for tx_valid
                // -------------------------------------------------
                IDLE: begin
                    tx        <= 1'b1;
                    clk_count <= 16'd0;
                    bit_index <= 3'd0;

                    if (tx_valid) begin
                        data_reg <= tx_data;

                        // Start bit begins immediately
                        tx    <= 1'b0;
                        state <= START;
                    end
                end


                // -------------------------------------------------
                // START BIT
                // Hold TX LOW for one UART bit period
                // -------------------------------------------------
                START: begin
                    tx <= 1'b0;

                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 16'd0;

                        // Send first data bit: LSB first
                        tx    <= data_reg[0];
                        state <= DATA;
                    end
                    else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end


                // -------------------------------------------------
                // DATA BITS
                // Send D0 -> D7
                // -------------------------------------------------
                DATA: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 16'd0;

                        if (bit_index == 3'd7) begin
                            bit_index <= 3'd0;

                            // Move to stop bit
                            tx    <= 1'b1;
                            state <= STOP;
                        end
                        else begin
                            bit_index <= bit_index + 1'b1;

                            // Send next data bit
                            tx <= data_reg[bit_index + 1'b1];
                        end
                    end
                    else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end


                // -------------------------------------------------
                // STOP BIT
                // Hold TX HIGH for one UART bit period
                // -------------------------------------------------
                STOP: begin
                    tx <= 1'b1;

                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 16'd0;

                        // Transmission finished
                        state <= IDLE;
                    end
                    else begin
                        clk_count <= clk_count + 1'b1;
                    end
                end


                // -------------------------------------------------
                // Safety default
                // -------------------------------------------------
                default: begin
                    state     <= IDLE;
                    clk_count <= 16'd0;
                    bit_index <= 3'd0;
                    data_reg  <= 8'd0;
                    tx         <= 1'b1;
                end

            endcase
        end
    end

endmodule