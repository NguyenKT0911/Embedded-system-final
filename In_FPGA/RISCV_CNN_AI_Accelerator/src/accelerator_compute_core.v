`timescale 1ns/1ps

module accelerator_compute_core #(
    parameter integer INPUT_MAX_VALUES   = 3136,
    parameter integer WEIGHT_MAX_VALUES  = 4608,
    parameter integer OUTPUT_MAX_VALUES  = 12544,

    parameter integer INPUT_ADDR_WIDTH   = 12,
    parameter integer WEIGHT_ADDR_WIDTH  = 13,
    parameter integer OUTPUT_ADDR_WIDTH  = 14
)(
    // ============================================================
    // Clock / Reset / Clear
    // ============================================================
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         clear,

    // ============================================================
    // Control from Accelerator Controller
    //
    // core_enable stays high during RUN.
    // This module converts its rising edge into one engine START.
    // ============================================================
    input  wire                         core_enable,

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
    input  wire                         relu_en,

    // ============================================================
    // Packed Input Activation Stream from MMIO
    // 4 x INT8 per 32-bit write
    // ============================================================
    input  wire [31:0]                  input_data_word,
    input  wire                         input_data_valid,

    // ============================================================
    // Packed Weight Stream from MMIO
    // 4 x INT8 per 32-bit write
    // ============================================================
    input  wire [31:0]                  weight_data_word,
    input  wire                         weight_data_valid,

    // ============================================================
    // MMIO Output Read Interface
    // ============================================================
    output wire [31:0]                  core_output_data,
    output wire [31:0]                  core_output_count,
    input  wire                         output_read_pulse,

    // ============================================================
    // Compute Status
    // ============================================================
    output wire                         compute_busy,
    output wire                         compute_done,
    output wire                         compute_error,
    output wire [31:0]                  compute_error_code,

    // ============================================================
    // Optional Visibility / Debug
    // ============================================================
    output wire [31:0]                  input_buffer_count,
    output wire [31:0]                  weight_buffer_count,
    output wire [31:0]                  output_read_index,

    output wire [15:0]                  out_h,
    output wire [15:0]                  out_w
);

    // ============================================================
    // Output Dimension Calculation
    //
    // out = floor((in + 2P - K) / S) + 1
    //
    // The validation block guarantees legal configuration before
    // the controller enters RUN.
    // ============================================================
    wire [31:0] out_h_calc;
    wire [31:0] out_w_calc;

    assign out_h_calc =
        (stride != 0)
        ? ((({16'd0, input_h} + ({24'd0, padding} << 1)
              - {24'd0, kernel_size}) / stride) + 1)
        : 32'd0;

    assign out_w_calc =
        (stride != 0)
        ? ((({16'd0, input_w} + ({24'd0, padding} << 1)
              - {24'd0, kernel_size}) / stride) + 1)
        : 32'd0;

    assign out_h = out_h_calc[15:0];
    assign out_w = out_w_calc[15:0];

    // ============================================================
    // Convert level-style core_enable into one-cycle START pulse
    // ============================================================
    reg core_enable_d;

    always @(posedge clk) begin

        if (rst || clear)
            core_enable_d <= 1'b0;
        else
            core_enable_d <= core_enable;

    end

    wire engine_start;

    assign engine_start = core_enable & ~core_enable_d;

    // ============================================================
    // Input Buffer
    // ============================================================
    wire                         input_read_en;
    wire [INPUT_ADDR_WIDTH-1:0]  input_read_addr;
    wire signed [7:0]            input_read_data;

    wire                         input_buffer_full;
    wire                         input_buffer_overflow;

    input_buffer #(
        .MAX_VALUES(INPUT_MAX_VALUES),
        .ADDR_WIDTH(INPUT_ADDR_WIDTH)
    ) u_input_buffer (
        .clk(clk),
        .rst(rst),
        .clear(clear),

        .write_data(input_data_word),
        .write_valid(input_data_valid),

        .read_en(input_read_en),
        .read_addr(input_read_addr),
        .read_data(input_read_data),

        .stored_count(input_buffer_count),
        .full(input_buffer_full),
        .overflow_error(input_buffer_overflow)
    );

    // ============================================================
    // Weight Buffer
    // ============================================================
    wire                          weight_read_en;
    wire [WEIGHT_ADDR_WIDTH-1:0]  weight_read_addr;
    wire signed [7:0]             weight_read_data;

    wire                          weight_buffer_full;
    wire                          weight_buffer_overflow;

    weight_buffer #(
        .MAX_VALUES(WEIGHT_MAX_VALUES),
        .ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
    ) u_weight_buffer (
        .clk(clk),
        .rst(rst),
        .clear(clear),

        .write_data(weight_data_word),
        .write_valid(weight_data_valid),

        .read_en(weight_read_en),
        .read_addr(weight_read_addr),
        .read_data(weight_read_data),

        .stored_count(weight_buffer_count),
        .full(weight_buffer_full),
        .overflow_error(weight_buffer_overflow)
    );

    // ============================================================
    // Convolution Engine <-> Output Path Tile Handshake
    // ============================================================
    wire         tile_ready;
    wire         tile_accept;

    wire [15:0]  tile_oh;
    wire [15:0]  tile_ow_base;
    wire [15:0]  tile_oc_base;

    wire [511:0] accumulator_bus;

    // ============================================================
    // Convolution Engine
    // ============================================================
    wire engine_busy;
    wire engine_done;

    convolution_engine_4x4 #(
        .INPUT_ADDR_WIDTH(INPUT_ADDR_WIDTH),
        .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
    ) u_convolution_engine (
        .clk(clk),
        .rst(rst),
        .clear(clear),

        .start(engine_start),

        .input_h(input_h),
        .input_w(input_w),
        .cin(cin),
        .cout(cout),

        .kernel_size(kernel_size),
        .stride(stride),
        .padding(padding),

        .out_h(out_h),
        .out_w(out_w),

        .input_read_en(input_read_en),
        .input_read_addr(input_read_addr),
        .input_read_data(input_read_data),

        .weight_read_en(weight_read_en),
        .weight_read_addr(weight_read_addr),
        .weight_read_data(weight_read_data),

        .tile_ready(tile_ready),
        .tile_accept(tile_accept),

        .tile_oh(tile_oh),
        .tile_ow_base(tile_ow_base),
        .tile_oc_base(tile_oc_base),

        .accumulator_bus(accumulator_bus),

        .busy(engine_busy),
        .done(engine_done),

        .dbg_ic(),
        .dbg_kh(),
        .dbg_kw(),

        .dbg_input_valid_mask(),
        .dbg_weight_valid_mask(),

        .dbg_activation_bus(),
        .dbg_weight_bus()
    );

    // ============================================================
    // Output Path
    // ============================================================
    wire signed [31:0] output_data_signed;

    wire output_empty;
    wire output_full;
    wire output_overflow;

    wire output_writer_busy;

    output_path #(
        .MAX_VALUES(OUTPUT_MAX_VALUES),
        .ADDR_WIDTH(OUTPUT_ADDR_WIDTH)
    ) u_output_path (
        .clk(clk),
        .rst(rst),
        .clear(clear),

        .tile_ready(tile_ready),
        .tile_accept(tile_accept),

        .tile_oh(tile_oh),
        .tile_ow_base(tile_ow_base),
        .tile_oc_base(tile_oc_base),

        .out_h(out_h),
        .out_w(out_w),
        .cout(cout),

        .relu_en(relu_en),

        .accumulator_bus(accumulator_bus),

        .output_data(output_data_signed),
        .output_read_next(output_read_pulse),

        .output_count(core_output_count),
        .output_read_index(output_read_index),

        .output_empty(output_empty),
        .output_full(output_full),
        .output_overflow_error(output_overflow),

        .writer_busy(output_writer_busy)
    );

    assign core_output_data = output_data_signed;

    // ============================================================
    // Compute Status
    //
    // Engine cannot enter DONE until the final tile has already
    // been accepted by the output path, so all final writes are
    // committed before compute_done is asserted.
    // ============================================================
    assign compute_busy = engine_busy | output_writer_busy;
    assign compute_done = engine_done;

    // ============================================================
    // Error Aggregation
    //
    // These codes extend the MMIO v0.1 error namespace:
    //   0x10 = input buffer overflow
    //   0x11 = weight buffer overflow
    //   0x12 = output buffer overflow
    // ============================================================
    assign compute_error =
        input_buffer_overflow |
        weight_buffer_overflow |
        output_overflow;

    assign compute_error_code =
        input_buffer_overflow  ? 32'h0000_0010 :
        weight_buffer_overflow ? 32'h0000_0011 :
        output_overflow        ? 32'h0000_0012 :
                                 32'h0000_0000;

endmodule
