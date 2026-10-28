`timescale 1ns/1ps

module convolution_engine_4x4 #(
    parameter integer INPUT_ADDR_WIDTH  = 12,
    parameter integer WEIGHT_ADDR_WIDTH = 13
)(
    // ============================================================
    // Clock / Reset / Clear
    // ============================================================
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         clear,

    // ============================================================
    // Engine Command
    // ============================================================
    input  wire                         start,

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
    // Completed Tile Handshake
    //
    // tile_ready = PE Array contains one completed 4x4 result tile.
    // tile_accept = downstream output path has captured that tile.
    // ============================================================
    output wire                         tile_ready,
    input  wire                         tile_accept,

    // Coordinates of the completed/current tile
    output wire [15:0]                  tile_oh,
    output wire [15:0]                  tile_ow_base,
    output wire [15:0]                  tile_oc_base,

    // ============================================================
    // PE Array Results
    // 16 x signed INT32 values, row-major
    // ============================================================
    output wire [511:0]                 accumulator_bus,

    // ============================================================
    // Engine Status
    // ============================================================
    output wire                         busy,
    output wire                         done,

    // ============================================================
    // Debug / Visibility
    // ============================================================
    output wire [15:0]                  dbg_ic,
    output wire [7:0]                   dbg_kh,
    output wire [7:0]                   dbg_kw,

    output wire [3:0]                   dbg_input_valid_mask,
    output wire [3:0]                   dbg_weight_valid_mask,

    output wire [31:0]                  dbg_activation_bus,
    output wire [31:0]                  dbg_weight_bus
);

    // ============================================================
    // Sequencer -> Datapath Control / Indices
    // ============================================================
    wire start_step;
    wire clear_acc;

    wire [15:0] seq_oh;
    wire [15:0] seq_ow_base;
    wire [15:0] seq_oc_base;

    wire [15:0] seq_ic;
    wire [7:0]  seq_kh;
    wire [7:0]  seq_kw;

    // ============================================================
    // Datapath -> Sequencer Handshake
    // ============================================================
    wire datapath_busy;
    wire datapath_step_done;

    // ============================================================
    // Convolution Sequencer
    //
    // Automatically iterates:
    //   kw -> kh -> ic -> ow_base -> oh -> oc_base
    // ============================================================
    conv_sequencer_4x4 u_sequencer (
        .clk(clk),
        .rst(rst),
        .clear(clear),

        .start(start),

        .cin(cin),
        .cout(cout),
        .kernel_size(kernel_size),

        .out_h(out_h),
        .out_w(out_w),

        .step_busy(datapath_busy),
        .step_done(datapath_step_done),

        .start_step(start_step),
        .clear_acc(clear_acc),

        .tile_ready(tile_ready),
        .tile_accept(tile_accept),

        .oh(seq_oh),
        .ow_base(seq_ow_base),
        .oc_base(seq_oc_base),

        .ic(seq_ic),
        .kh(seq_kh),
        .kw(seq_kw),

        .busy(busy),
        .done(done)
    );

    // ============================================================
    // Convolution Compute Datapath
    //
    // For each start_step:
    //   Address Generator
    //      -> Conv Data Feeder
    //      -> PE Array 4x4
    //      -> one accumulation step
    // ============================================================
    conv_compute_datapath_4x4 #(
        .INPUT_ADDR_WIDTH(INPUT_ADDR_WIDTH),
        .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
    ) u_datapath (
        .clk(clk),
        .rst(rst),

        // A global clear also aborts any in-flight feeder request.
        .feeder_clear(clear),
        .clear_acc(clear_acc),
        .start_step(start_step),

        .busy(datapath_busy),
        .step_done(datapath_step_done),

        .input_h(input_h),
        .input_w(input_w),
        .cin(cin),
        .cout(cout),

        .kernel_size(kernel_size),
        .stride(stride),
        .padding(padding),

        .out_h(out_h),
        .out_w(out_w),

        .oh(seq_oh),
        .ow_base(seq_ow_base),
        .oc_base(seq_oc_base),

        .ic(seq_ic),
        .kh(seq_kh),
        .kw(seq_kw),

        .input_read_en(input_read_en),
        .input_read_addr(input_read_addr),
        .input_read_data(input_read_data),

        .weight_read_en(weight_read_en),
        .weight_read_addr(weight_read_addr),
        .weight_read_data(weight_read_data),

        .input_valid_mask(dbg_input_valid_mask),
        .weight_valid_mask(dbg_weight_valid_mask),

        .activation_bus(dbg_activation_bus),
        .weight_bus(dbg_weight_bus),

        .accumulator_bus(accumulator_bus)
    );

    // ============================================================
    // Expose Current Tile Coordinates / Inner Indices
    // ============================================================
    assign tile_oh      = seq_oh;
    assign tile_ow_base = seq_ow_base;
    assign tile_oc_base = seq_oc_base;

    assign dbg_ic = seq_ic;
    assign dbg_kh = seq_kh;
    assign dbg_kw = seq_kw;

endmodule
