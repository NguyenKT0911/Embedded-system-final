`timescale 1ns/1ps

module pe (
    // Clock / Reset
    input  wire                    clk,
    input  wire                    rst,

    // PE Control
    input  wire                    clear_acc,
    input  wire                    enable,

    // Signed INT8 Data Inputs
    input  wire signed [7:0]       activation,
    input  wire signed [7:0]       weight,

    // Signed INT32 Accumulator Output
    output reg  signed [31:0]      accumulator
);

    // MAC Combinational Result
    // next_acc = accumulator + activation * weight
    wire signed [31:0] mac_result;

    mac_unit u_mac (
        .activation(activation),
        .weight(weight),
        .acc_in(accumulator),
        .acc_out(mac_result)
    );

    // ============================================================
    // Accumulator Register
    //
    // Priority:
    //   1. rst
    //   2. clear_acc
    //   3. enable
    // ============================================================
    always @(posedge clk) begin

        if (rst) begin

            accumulator <= 32'sd0;

        end
        else if (clear_acc) begin

            accumulator <= 32'sd0;

        end
        else if (enable) begin

            accumulator <= mac_result;

        end

    end

endmodule
