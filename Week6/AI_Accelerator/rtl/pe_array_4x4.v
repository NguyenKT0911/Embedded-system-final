`timescale 1ns/1ps

module pe_array_4x4 (
    // ============================================================
    // Clock / Reset
    // ============================================================
    input  wire                     clk,
    input  wire                     rst,

    // ============================================================
    // Array Control
    // ============================================================
    input  wire                     clear_acc,
    input  wire                     enable,

    // ============================================================
    // Row Activations
    //
    // activation_bus[7:0]   = activation row 0
    // activation_bus[15:8]  = activation row 1
    // activation_bus[23:16] = activation row 2
    // activation_bus[31:24] = activation row 3
    // ============================================================
    input  wire [31:0]              activation_bus,

    // ============================================================
    // Column Weights
    //
    // weight_bus[7:0]   = weight column 0
    // weight_bus[15:8]  = weight column 1
    // weight_bus[23:16] = weight column 2
    // weight_bus[31:24] = weight column 3
    // ============================================================
    input  wire [31:0]              weight_bus,

    // ============================================================
    // 16 x INT32 Accumulator Outputs
    //
    // Layout is row-major:
    //
    // accumulator_bus[31:0]    = PE(0,0)
    // accumulator_bus[63:32]   = PE(0,1)
    // accumulator_bus[95:64]   = PE(0,2)
    // accumulator_bus[127:96]  = PE(0,3)
    //
    // accumulator_bus[159:128] = PE(1,0)
    // ...
    //
    // accumulator_bus[511:480] = PE(3,3)
    // ============================================================
    output wire [511:0]             accumulator_bus
);

    // ============================================================
    // Unpack Row Activations
    // ============================================================
    wire signed [7:0] activation_0;
    wire signed [7:0] activation_1;
    wire signed [7:0] activation_2;
    wire signed [7:0] activation_3;

    assign activation_0 = activation_bus[7:0];
    assign activation_1 = activation_bus[15:8];
    assign activation_2 = activation_bus[23:16];
    assign activation_3 = activation_bus[31:24];

    // ============================================================
    // Unpack Column Weights
    // ============================================================
    wire signed [7:0] weight_0;
    wire signed [7:0] weight_1;
    wire signed [7:0] weight_2;
    wire signed [7:0] weight_3;

    assign weight_0 = weight_bus[7:0];
    assign weight_1 = weight_bus[15:8];
    assign weight_2 = weight_bus[23:16];
    assign weight_3 = weight_bus[31:24];

    // ============================================================
    // PE Output Wires
    // ============================================================
    wire signed [31:0] acc_00;
    wire signed [31:0] acc_01;
    wire signed [31:0] acc_02;
    wire signed [31:0] acc_03;

    wire signed [31:0] acc_10;
    wire signed [31:0] acc_11;
    wire signed [31:0] acc_12;
    wire signed [31:0] acc_13;

    wire signed [31:0] acc_20;
    wire signed [31:0] acc_21;
    wire signed [31:0] acc_22;
    wire signed [31:0] acc_23;

    wire signed [31:0] acc_30;
    wire signed [31:0] acc_31;
    wire signed [31:0] acc_32;
    wire signed [31:0] acc_33;

    // ============================================================
    // Row 0
    // ============================================================
    pe pe_00 (
        .clk(clk), .rst(rst),
        .clear_acc(clear_acc), .enable(enable),
        .activation(activation_0), .weight(weight_0),
        .accumulator(acc_00)
    );

    pe pe_01 (
        .clk(clk), .rst(rst),
        .clear_acc(clear_acc), .enable(enable),
        .activation(activation_0), .weight(weight_1),
        .accumulator(acc_01)
    );

    pe pe_02 (
        .clk(clk), .rst(rst),
        .clear_acc(clear_acc), .enable(enable),
        .activation(activation_0), .weight(weight_2),
        .accumulator(acc_02)
    );

    pe pe_03 (
        .clk(clk), .rst(rst),
        .clear_acc(clear_acc), .enable(enable),
        .activation(activation_0), .weight(weight_3),
        .accumulator(acc_03)
    );

    // ============================================================
    // Row 1
    // ============================================================
    pe pe_10 (
        .clk(clk), .rst(rst),
        .clear_acc(clear_acc), .enable(enable),
        .activation(activation_1), .weight(weight_0),
        .accumulator(acc_10)
    );

    pe pe_11 (
        .clk(clk), .rst(rst),
        .clear_acc(clear_acc), .enable(enable),
        .activation(activation_1), .weight(weight_1),
        .accumulator(acc_11)
    );

    pe pe_12 (
        .clk(clk), .rst(rst),
        .clear_acc(clear_acc), .enable(enable),
        .activation(activation_1), .weight(weight_2),
        .accumulator(acc_12)
    );

    pe pe_13 (
        .clk(clk), .rst(rst),
        .clear_acc(clear_acc), .enable(enable),
        .activation(activation_1), .weight(weight_3),
        .accumulator(acc_13)
    );

    // ============================================================
    // Row 2
    // ============================================================
    pe pe_20 (
        .clk(clk), .rst(rst),
        .clear_acc(clear_acc), .enable(enable),
        .activation(activation_2), .weight(weight_0),
        .accumulator(acc_20)
    );

    pe pe_21 (
        .clk(clk), .rst(rst),
        .clear_acc(clear_acc), .enable(enable),
        .activation(activation_2), .weight(weight_1),
        .accumulator(acc_21)
    );

    pe pe_22 (
        .clk(clk), .rst(rst),
        .clear_acc(clear_acc), .enable(enable),
        .activation(activation_2), .weight(weight_2),
        .accumulator(acc_22)
    );

    pe pe_23 (
        .clk(clk), .rst(rst),
        .clear_acc(clear_acc), .enable(enable),
        .activation(activation_2), .weight(weight_3),
        .accumulator(acc_23)
    );

    // ============================================================
    // Row 3
    // ============================================================
    pe pe_30 (
        .clk(clk), .rst(rst),
        .clear_acc(clear_acc), .enable(enable),
        .activation(activation_3), .weight(weight_0),
        .accumulator(acc_30)
    );

    pe pe_31 (
        .clk(clk), .rst(rst),
        .clear_acc(clear_acc), .enable(enable),
        .activation(activation_3), .weight(weight_1),
        .accumulator(acc_31)
    );

    pe pe_32 (
        .clk(clk), .rst(rst),
        .clear_acc(clear_acc), .enable(enable),
        .activation(activation_3), .weight(weight_2),
        .accumulator(acc_32)
    );

    pe pe_33 (
        .clk(clk), .rst(rst),
        .clear_acc(clear_acc), .enable(enable),
        .activation(activation_3), .weight(weight_3),
        .accumulator(acc_33)
    );

    // ============================================================
    // Pack 16 Accumulators into one output bus
    // Row-major order
    // ============================================================
    assign accumulator_bus[31:0]    = acc_00;
    assign accumulator_bus[63:32]   = acc_01;
    assign accumulator_bus[95:64]   = acc_02;
    assign accumulator_bus[127:96]  = acc_03;

    assign accumulator_bus[159:128] = acc_10;
    assign accumulator_bus[191:160] = acc_11;
    assign accumulator_bus[223:192] = acc_12;
    assign accumulator_bus[255:224] = acc_13;

    assign accumulator_bus[287:256] = acc_20;
    assign accumulator_bus[319:288] = acc_21;
    assign accumulator_bus[351:320] = acc_22;
    assign accumulator_bus[383:352] = acc_23;

    assign accumulator_bus[415:384] = acc_30;
    assign accumulator_bus[447:416] = acc_31;
    assign accumulator_bus[479:448] = acc_32;
    assign accumulator_bus[511:480] = acc_33;

endmodule
