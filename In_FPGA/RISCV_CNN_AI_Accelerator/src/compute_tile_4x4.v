`timescale 1ns/1ps

module compute_tile_4x4 #(
    parameter integer INPUT_ADDR_WIDTH  = 12,
    parameter integer WEIGHT_ADDR_WIDTH = 13
)(
    // ============================================================
    // Clock / Reset
    // ============================================================
    input  wire                         clk,
    input  wire                         rst,

    // ============================================================
    // Local Control
    //
    // feeder_clear : abort/clear the current feeder transaction
    // clear_acc    : clear all 16 PE accumulators
    // start_fetch  : fetch one bundle of 4 activations + 4 weights
    // ============================================================
    input  wire                         feeder_clear,
    input  wire                         clear_acc,
    input  wire                         start_fetch,

    // ============================================================
    // Base Addresses for One 4x4 Outer-Product Step
    // ============================================================
    input  wire [INPUT_ADDR_WIDTH-1:0]  input_base_addr,
    input  wire [WEIGHT_ADDR_WIDTH-1:0] weight_base_addr,

    // ============================================================
    // Input Buffer Read Interface
    // ============================================================
    output wire                         input_read_en,
    output wire [INPUT_ADDR_WIDTH-1:0]  input_read_addr,
    input  wire signed [7:0]            input_read_data,

    // ============================================================
    // Weight Buffer Read Interface
    // ============================================================
    output wire                         weight_read_en,
    output wire [WEIGHT_ADDR_WIDTH-1:0] weight_read_addr,
    input  wire signed [7:0]            weight_read_data,

    // ============================================================
    // Status
    // ============================================================
    output wire                         feeder_busy,
    output wire                         bundle_valid,

    // ============================================================
    // Debug / Visibility
    // ============================================================
    output wire [31:0]                  activation_bus,
    output wire [31:0]                  weight_bus,

    // ============================================================
    // PE Array Results
    //
    // 16 x signed INT32 accumulators packed row-major.
    // ============================================================
    output wire [511:0]                 accumulator_bus
);

    // ============================================================
    // Internal Feeder Outputs
    // ============================================================
    wire [31:0] feeder_activation_bus;
    wire [31:0] feeder_weight_bus;
    wire        feeder_data_valid;

    // ============================================================
    // Data Feeder
    //
    // Reads four consecutive activation values and four consecutive
    // weight values from the two synchronous buffers.
    // ============================================================
    data_feeder #(
        .INPUT_ADDR_WIDTH(INPUT_ADDR_WIDTH),
        .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
    ) u_data_feeder (
        .clk(clk),
        .rst(rst),
        .clear(feeder_clear),

        .start(start_fetch),
        .busy(feeder_busy),
        .data_valid(feeder_data_valid),

        .input_base_addr(input_base_addr),
        .weight_base_addr(weight_base_addr),

        .input_read_en(input_read_en),
        .input_read_addr(input_read_addr),
        .input_read_data(input_read_data),

        .weight_read_en(weight_read_en),
        .weight_read_addr(weight_read_addr),
        .weight_read_data(weight_read_data),

        .activation_bus(feeder_activation_bus),
        .weight_bus(feeder_weight_bus)
    );

    // ============================================================
    // PE Array 4x4
    //
    // feeder_data_valid is used as the PE enable pulse.
    //
    // Because the feeder registers activation_bus/weight_bus before
    // the following PE clock edge, all 16 PEs see one stable bundle
    // and perform exactly one accumulation step.
    // ============================================================
    pe_array_4x4 u_pe_array (
        .clk(clk),
        .rst(rst),

        .clear_acc(clear_acc),
        .enable(feeder_data_valid),

        .activation_bus(feeder_activation_bus),
        .weight_bus(feeder_weight_bus),

        .accumulator_bus(accumulator_bus)
    );

    // ============================================================
    // Expose feeder outputs for test/debug
    // ============================================================
    assign activation_bus = feeder_activation_bus;
    assign weight_bus     = feeder_weight_bus;
    assign bundle_valid   = feeder_data_valid;

endmodule
