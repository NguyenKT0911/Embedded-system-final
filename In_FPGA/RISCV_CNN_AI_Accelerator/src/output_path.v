`timescale 1ns/1ps

module output_path #(
    parameter integer MAX_VALUES = 12544,
    parameter integer ADDR_WIDTH = 14
)(
    // ============================================================
    // Clock / Reset / Clear
    // ============================================================
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         clear,

    // ============================================================
    // Completed Tile from Convolution Engine
    // ============================================================
    input  wire                         tile_ready,
    output wire                         tile_accept,

    input  wire [15:0]                  tile_oh,
    input  wire [15:0]                  tile_ow_base,
    input  wire [15:0]                  tile_oc_base,

    input  wire [15:0]                  out_h,
    input  wire [15:0]                  out_w,
    input  wire [15:0]                  cout,

    input  wire                         relu_en,

    input  wire [511:0]                 accumulator_bus,

    // ============================================================
    // MMIO-Style Sequential Output Read
    // ============================================================
    output wire signed [31:0]           output_data,
    input  wire                         output_read_next,

    // ============================================================
    // Output Status
    // ============================================================
    output wire [31:0]                  output_count,
    output wire [31:0]                  output_read_index,

    output wire                         output_empty,
    output wire                         output_full,
    output wire                         output_overflow_error,

    output wire                         writer_busy
);

    // ============================================================
    // Tile Writer -> Output Buffer Signals
    // ============================================================
    wire [ADDR_WIDTH-1:0]  buffer_write_addr;
    wire signed [31:0]     buffer_write_data;
    wire                   buffer_write_valid;

    // ============================================================
    // Output Tile Writer
    //
    // Responsibilities:
    //   1. Latch one completed PE tile
    //   2. Scan all 16 PE results
    //   3. Apply ReLU when enabled
    //   4. Calculate flattened [COUT][H][W] output address
    //   5. Skip invalid W / COUT tail lanes
    //   6. Acknowledge tile after all lanes are processed
    // ============================================================
    output_tile_writer #(
        .OUTPUT_ADDR_WIDTH(ADDR_WIDTH)
    ) u_output_tile_writer (
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

        .write_addr(buffer_write_addr),
        .write_data(buffer_write_data),
        .write_valid(buffer_write_valid),

        .busy(writer_busy)
    );

    // ============================================================
    // Indexed Output Buffer
    //
    // Writes arrive at their final flattened tensor address.
    //
    // MMIO later reads values sequentially:
    //   output[0], output[1], ..., output[N-1]
    // ============================================================
    output_buffer #(
        .MAX_VALUES(MAX_VALUES),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_output_buffer (
        .clk(clk),
        .rst(rst),
        .clear(clear),

        .write_addr(buffer_write_addr),
        .write_data(buffer_write_data),
        .write_valid(buffer_write_valid),

        .read_data(output_data),
        .read_next(output_read_next),

        .stored_count(output_count),
        .read_index(output_read_index),

        .empty(output_empty),
        .full(output_full),

        .overflow_error(output_overflow_error)
    );

endmodule
