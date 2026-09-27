`timescale 1ns/1ps

module conv_compute_datapath_4x4 #(
    parameter integer INPUT_ADDR_WIDTH  = 12,
    parameter integer WEIGHT_ADDR_WIDTH = 13
)(
    // ============================================================
    // Clock / Reset
    // ============================================================
    input  wire                         clk,
    input  wire                         rst,

    // ============================================================
    // Datapath Control
    // ============================================================
    input  wire                         feeder_clear,
    input  wire                         clear_acc,
    input  wire                         start_step,

    output wire                         busy,
    output wire                         step_done,

    // ============================================================
    // Convolution Configuration
    // ============================================================
    input  wire [15:0]                  input_h,
    input  wire [15:0]                  input_w,
    input  wire [15:0]                  cin,
    input  wire [15:0]                  cout,

    input  wire [7:0]                   kernel_size,
    input  wire [7:0]                   stride,
    input  wire [7:0]                   padding,

    input  wire [15:0]                  out_h,
    input  wire [15:0]                  out_w,

    // ============================================================
    // Current Convolution Indices
    //
    // One step corresponds to one (ic, kh, kw) contribution
    // for a tile of:
    //   4 output positions x 4 output channels
    // ============================================================
    input  wire [15:0]                  oh,
    input  wire [15:0]                  ow_base,
    input  wire [15:0]                  oc_base,

    input  wire [15:0]                  ic,
    input  wire [7:0]                   kh,
    input  wire [7:0]                   kw,

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
    // Debug / Visibility
    // ============================================================
    output wire [3:0]                   input_valid_mask,
    output wire [3:0]                   weight_valid_mask,

    output wire [31:0]                  activation_bus,
    output wire [31:0]                  weight_bus,

    // ============================================================
    // PE Array Results
    // 16 x signed INT32 accumulators packed row-major
    // ============================================================
    output wire [511:0]                 accumulator_bus
);

    // ============================================================
    // Address Generator Outputs
    // ============================================================
    wire [INPUT_ADDR_WIDTH-1:0] input_addr_0;
    wire [INPUT_ADDR_WIDTH-1:0] input_addr_1;
    wire [INPUT_ADDR_WIDTH-1:0] input_addr_2;
    wire [INPUT_ADDR_WIDTH-1:0] input_addr_3;

    wire [WEIGHT_ADDR_WIDTH-1:0] weight_addr_0;
    wire [WEIGHT_ADDR_WIDTH-1:0] weight_addr_1;
    wire [WEIGHT_ADDR_WIDTH-1:0] weight_addr_2;
    wire [WEIGHT_ADDR_WIDTH-1:0] weight_addr_3;

    // ============================================================
    // Feeder Internal Signals
    // ============================================================
    wire feeder_busy;
    wire feeder_data_valid;

    wire [31:0] feeder_activation_bus;
    wire [31:0] feeder_weight_bus;

    // ============================================================
    // Status Mapping
    // ============================================================
    assign busy      = feeder_busy;
    assign step_done = feeder_data_valid;

    assign activation_bus = feeder_activation_bus;
    assign weight_bus     = feeder_weight_bus;

    // ============================================================
    // 1) Convolution Address Generator
    //
    // Generates 4 independent activation addresses and
    // 4 independent weight addresses for the current
    // (oh, ow_base, oc_base, ic, kh, kw) step.
    // ============================================================
    conv_address_generator_4x4 #(
        .INPUT_ADDR_WIDTH(INPUT_ADDR_WIDTH),
        .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
    ) u_address_generator (
        .input_h(input_h),
        .input_w(input_w),
        .cin(cin),
        .cout(cout),

        .kernel_size(kernel_size),
        .stride(stride),
        .padding(padding),

        .oh(oh),
        .ow_base(ow_base),
        .oc_base(oc_base),

        .ic(ic),
        .kh(kh),
        .kw(kw),

        .out_h(out_h),
        .out_w(out_w),

        .input_addr_0(input_addr_0),
        .input_addr_1(input_addr_1),
        .input_addr_2(input_addr_2),
        .input_addr_3(input_addr_3),

        .input_valid_mask(input_valid_mask),

        .weight_addr_0(weight_addr_0),
        .weight_addr_1(weight_addr_1),
        .weight_addr_2(weight_addr_2),
        .weight_addr_3(weight_addr_3),

        .weight_valid_mask(weight_valid_mask)
    );

    // ============================================================
    // 2) Convolution Data Feeder
    //
    // Reads the generated addresses from the single-port buffers,
    // applies the valid masks, and packs:
    //
    //   4 x INT8 activations
    //   4 x INT8 weights
    //
    // into two 32-bit buses.
    // ============================================================
    conv_data_feeder_4x4 #(
        .INPUT_ADDR_WIDTH(INPUT_ADDR_WIDTH),
        .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
    ) u_conv_data_feeder (
        .clk(clk),
        .rst(rst),
        .clear(feeder_clear),

        .start(start_step),
        .busy(feeder_busy),
        .data_valid(feeder_data_valid),

        .input_addr_0(input_addr_0),
        .input_addr_1(input_addr_1),
        .input_addr_2(input_addr_2),
        .input_addr_3(input_addr_3),
        .input_valid_mask(input_valid_mask),

        .weight_addr_0(weight_addr_0),
        .weight_addr_1(weight_addr_1),
        .weight_addr_2(weight_addr_2),
        .weight_addr_3(weight_addr_3),
        .weight_valid_mask(weight_valid_mask),

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
    // 3) PE Array 4x4
    //
    // One feeder_data_valid pulse causes exactly one
    // outer-product accumulation step.
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

endmodule
