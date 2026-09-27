`timescale 1ns/1ps

module accelerator_top #(
    parameter [31:0] BASE_ADDR = 32'h4000_0000,

    parameter integer INPUT_MAX_VALUES   = 3136,
    parameter integer WEIGHT_MAX_VALUES  = 4608,
    parameter integer OUTPUT_MAX_VALUES  = 12544,

    parameter integer INPUT_ADDR_WIDTH   = 12,
    parameter integer WEIGHT_ADDR_WIDTH  = 13,
    parameter integer OUTPUT_ADDR_WIDTH  = 14
)(
    // ============================================================
    // Clock / Reset
    // ============================================================
    input  wire         clk,
    input  wire         rst,

    // ============================================================
    // 32-bit RISC-V MMIO Interface
    // ============================================================
    input  wire [31:0]  mmio_addr,
    input  wire [31:0]  mmio_wdata,
    input  wire         mmio_we,
    input  wire         mmio_re,

    output wire [31:0]  mmio_rdata,
    output wire         mmio_hit,

    // ============================================================
    // Optional Top-Level Debug / Status
    // ============================================================
    output wire         dbg_core_enable,
    output wire         dbg_core_clear,

    output wire         dbg_compute_busy,
    output wire         dbg_compute_done,
    output wire         dbg_compute_error,
    output wire [31:0]  dbg_compute_error_code,

    output wire [31:0]  dbg_input_buffer_count,
    output wire [31:0]  dbg_weight_buffer_count,
    output wire [31:0]  dbg_output_count,
    output wire [31:0]  dbg_output_read_index
);

    // ============================================================
    // Control / MMIO -> Compute-Core Configuration
    // ============================================================
    wire [15:0] cfg_input_h;
    wire [15:0] cfg_input_w;
    wire [15:0] cfg_cin;
    wire [15:0] cfg_cout;

    wire [7:0]  cfg_kernel_size;
    wire [7:0]  cfg_stride;
    wire [7:0]  cfg_padding;
    wire        cfg_relu_en;

    // ============================================================
    // MMIO -> Compute-Core Data Streams
    // ============================================================
    wire [31:0] input_data_word;
    wire        input_data_valid;

    wire [31:0] weight_data_word;
    wire        weight_data_valid;

    // ============================================================
    // Compute-Core -> MMIO Output Path
    // ============================================================
    wire [31:0] compute_output_data;
    wire [31:0] compute_output_count;
    wire        output_read_pulse;

    // ============================================================
    // Control Handshake
    // ============================================================
    wire core_enable;
    wire core_clear;

    // ============================================================
    // Compute Status
    // ============================================================
    wire        compute_busy;
    wire        compute_done;
    wire        compute_error;
    wire [31:0] compute_error_code;

    // ============================================================
    // Compute-Core Debug / Counts
    // ============================================================
    wire [31:0] input_buffer_count;
    wire [31:0] weight_buffer_count;
    wire [31:0] output_read_index;

    wire [15:0] compute_out_h;
    wire [15:0] compute_out_w;

    // ============================================================
    // 1) Control / Interface Subsystem
    //
    // RISC-V MMIO
    //    -> configuration
    //    -> validation
    //    -> controller FSM
    //    -> packed input / weight streams
    // ============================================================
    accelerator_control_top #(
        .BASE_ADDR(BASE_ADDR)
    ) u_control (
        .clk(clk),
        .rst(rst),

        .mmio_addr(mmio_addr),
        .mmio_wdata(mmio_wdata),
        .mmio_we(mmio_we),
        .mmio_re(mmio_re),

        .mmio_rdata(mmio_rdata),
        .mmio_hit(mmio_hit),

        .cfg_input_h(cfg_input_h),
        .cfg_input_w(cfg_input_w),
        .cfg_cin(cfg_cin),
        .cfg_cout(cfg_cout),

        .cfg_kernel_size(cfg_kernel_size),
        .cfg_stride(cfg_stride),
        .cfg_padding(cfg_padding),
        .cfg_relu_en(cfg_relu_en),

        .input_data_word(input_data_word),
        .input_data_valid(input_data_valid),

        .weight_data_word(weight_data_word),
        .weight_data_valid(weight_data_valid),

        .compute_output_data(compute_output_data),
        .compute_output_count(compute_output_count),
        .output_read_pulse(output_read_pulse),

        .compute_done(compute_done),
        .compute_error(compute_error),
        .compute_error_code(compute_error_code),

        .core_enable(core_enable),
        .core_clear(core_clear)
    );

    // ============================================================
    // 2) Complete Compute Core
    //
    // Input Buffer
    // Weight Buffer
    // Convolution Sequencer / Address Generator / Feeder
    // PE Array 4x4
    // ReLU
    // Output Tile Writer
    // Indexed Output Buffer
    // ============================================================
    accelerator_compute_core #(
        .INPUT_MAX_VALUES(INPUT_MAX_VALUES),
        .WEIGHT_MAX_VALUES(WEIGHT_MAX_VALUES),
        .OUTPUT_MAX_VALUES(OUTPUT_MAX_VALUES),

        .INPUT_ADDR_WIDTH(INPUT_ADDR_WIDTH),
        .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH),
        .OUTPUT_ADDR_WIDTH(OUTPUT_ADDR_WIDTH)
    ) u_compute_core (
        .clk(clk),
        .rst(rst),
        .clear(core_clear),

        .core_enable(core_enable),

        .input_h(cfg_input_h),
        .input_w(cfg_input_w),
        .cin(cfg_cin),
        .cout(cfg_cout),

        .kernel_size(cfg_kernel_size),
        .stride(cfg_stride),
        .padding(cfg_padding),
        .relu_en(cfg_relu_en),

        .input_data_word(input_data_word),
        .input_data_valid(input_data_valid),

        .weight_data_word(weight_data_word),
        .weight_data_valid(weight_data_valid),

        .core_output_data(compute_output_data),
        .core_output_count(compute_output_count),
        .output_read_pulse(output_read_pulse),

        .compute_busy(compute_busy),
        .compute_done(compute_done),
        .compute_error(compute_error),
        .compute_error_code(compute_error_code),

        .input_buffer_count(input_buffer_count),
        .weight_buffer_count(weight_buffer_count),
        .output_read_index(output_read_index),

        .out_h(compute_out_h),
        .out_w(compute_out_w)
    );

    // ============================================================
    // Debug Exports
    // ============================================================
    assign dbg_core_enable        = core_enable;
    assign dbg_core_clear         = core_clear;

    assign dbg_compute_busy       = compute_busy;
    assign dbg_compute_done       = compute_done;
    assign dbg_compute_error      = compute_error;
    assign dbg_compute_error_code = compute_error_code;

    assign dbg_input_buffer_count = input_buffer_count;
    assign dbg_weight_buffer_count = weight_buffer_count;
    assign dbg_output_count       = compute_output_count;
    assign dbg_output_read_index  = output_read_index;

endmodule
