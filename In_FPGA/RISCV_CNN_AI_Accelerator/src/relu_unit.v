`timescale 1ns/1ps

module relu_unit (
    // ============================================================
    // ReLU Control
    // ============================================================
    input  wire                    relu_en,

    // ============================================================
    // Signed INT32 Input / Output
    // ============================================================
    input  wire signed [31:0]      data_in,
    output wire signed [31:0]      data_out
);

    // ============================================================
    // ReLU
    //
    // relu_en = 1:
    //   data_out = max(0, data_in)
    //
    // relu_en = 0:
    //   data_out = data_in
    // ============================================================
    assign data_out =
        relu_en
        ? (data_in[31] ? 32'sd0 : data_in)
        : data_in;

endmodule
