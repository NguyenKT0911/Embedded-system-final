`timescale 1ns/1ps

module mac_unit (
    // Signed INT8 Inputs
    input  wire signed [7:0]  activation,
    input  wire signed [7:0]  weight,

    // Signed INT32 Accumulator Input
    input  wire signed [31:0] acc_in,

    // Signed INT32 MAC Result
    // acc_out = acc_in + (activation * weight)
    output wire signed [31:0] acc_out
);

    // INT8 x INT8 = INT16
    wire signed [15:0] product;

    // Sign-extended product for INT32 accumulation
    wire signed [31:0] product_ext;

    assign product = activation * weight;

    assign product_ext = {
        {16{product[15]}},
        product
    };

    // Multiply-Accumulate
    assign acc_out = acc_in + product_ext;

endmodule
