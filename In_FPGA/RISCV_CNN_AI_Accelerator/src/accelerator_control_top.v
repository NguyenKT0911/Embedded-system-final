`timescale 1ns/1ps

module accelerator_control_top #(
    parameter [31:0] BASE_ADDR = 32'h4000_0000
)(
    // ============================================================
    // Clock and Reset
    // ============================================================
    input  wire         clk,
    input  wire         rst,

    // ============================================================
    // RISC-V MMIO Interface
    // ============================================================
    input  wire [31:0]  mmio_addr,
    input  wire [31:0]  mmio_wdata,
    input  wire         mmio_we,
    input  wire         mmio_re,

    output wire [31:0]  mmio_rdata,
    output wire         mmio_hit,

    // ============================================================
    // Configuration Outputs to Future Compute Core
    // ============================================================
    output wire [15:0]  cfg_input_h,
    output wire [15:0]  cfg_input_w,
    output wire [15:0]  cfg_cin,
    output wire [15:0]  cfg_cout,

    output wire [7:0]   cfg_kernel_size,
    output wire [7:0]   cfg_stride,
    output wire [7:0]   cfg_padding,
    output wire         cfg_relu_en,

    // ============================================================
    // Input Activation Stream from MMIO
    // ============================================================
    output wire [31:0]  input_data_word,
    output wire         input_data_valid,

    // ============================================================
    // Weight Stream from MMIO
    // ============================================================
    output wire [31:0]  weight_data_word,
    output wire         weight_data_valid,

    // ============================================================
    // Output Interface from Future Compute Core
    // ============================================================
    input  wire [31:0]  compute_output_data,
    input  wire [31:0]  compute_output_count,
    output wire         output_read_pulse,

    // ============================================================
    // Future Compute Core Status
    // ============================================================
    input  wire         compute_done,
    input  wire         compute_error,
    input  wire [31:0]  compute_error_code,

    // ============================================================
    // Control Outputs to Compute Core
    // ============================================================
    output wire         core_enable,
    output wire         core_clear
);

    // ============================================================
    // Internal MMIO Control Signals
    // ============================================================
    wire start_pulse;
    wire clear_pulse;

    // Forward the MMIO CLEAR pulse to the compute datapath so all
    // input/weight/output buffers and engine state are cleared too.
    assign core_clear = clear_pulse;

    // ============================================================
    // Internal Configuration Signals
    // ============================================================
    wire [15:0] input_h;
    wire [15:0] input_w;
    wire [15:0] cin;
    wire [15:0] cout;

    wire [7:0] kernel_size;
    wire [7:0] stride;
    wire [7:0] padding;
    wire       relu_en;

    // ============================================================
    // MMIO Data Counters
    // ============================================================
    wire [31:0] input_count_value;
    wire [31:0] weight_count_value;

    // ============================================================
    // Validation Result
    // ============================================================
    wire validation_ok;

    // ============================================================
    // Controller Status
    // ============================================================
    wire controller_busy;
    wire controller_done;
    wire controller_error;

    // ============================================================
    // Validation Error Event
    //
    // In CHECK:
    //   busy        = 1
    //   core_enable = 0
    //
    // Therefore, if validation_ok = 0 while the controller is in
    // CHECK, this signal becomes a one-state validation error event.
    // ============================================================
    wire validation_error_event;

    assign validation_error_event =
        controller_busy &&
        !core_enable &&
        !validation_ok;

    // ============================================================
    // Error Signal / Error Code Sent to MMIO
    //
    // For version 0.1:
    //   0x01 = generic validation/configuration error
    //
    // Detailed validation error codes can be added later without
    // changing the basic MMIO -> Validation -> Controller flow.
    // ============================================================
    wire        mmio_core_done;
    wire        mmio_core_error;
    wire [31:0] mmio_core_error_code;

    // CLEAR is generated inside the MMIO block and is observed by
    // the controller / compute core on the following clock edge.
    // During that one-cycle handoff, compute_done/compute_error may
    // still be high from the previous transaction.  Mask them while
    // clear_pulse is active so MMIO cannot re-latch DONE/ERROR just
    // after software cleared the status bits.
    assign mmio_core_done = compute_done & ~clear_pulse;

    assign mmio_core_error =
        (validation_error_event | compute_error) & ~clear_pulse;

    assign mmio_core_error_code =
        validation_error_event
        ? 32'h0000_0001
        : compute_error_code;

    // ============================================================
    // Expose Configuration to Future Compute Core
    // ============================================================
    assign cfg_input_h     = input_h;
    assign cfg_input_w     = input_w;
    assign cfg_cin         = cin;
    assign cfg_cout        = cout;

    assign cfg_kernel_size = kernel_size;
    assign cfg_stride      = stride;
    assign cfg_padding     = padding;
    assign cfg_relu_en     = relu_en;

    // ============================================================
    // MMIO Block
    // ============================================================
    accelerator_mmio #(
        .BASE_ADDR(BASE_ADDR)
    ) u_mmio (
        .clk(clk),
        .rst(rst),

        .mmio_addr(mmio_addr),
        .mmio_wdata(mmio_wdata),
        .mmio_we(mmio_we),
        .mmio_re(mmio_re),

        .mmio_rdata(mmio_rdata),
        .mmio_hit(mmio_hit),

        .start_pulse(start_pulse),
        .clear_pulse(clear_pulse),

        .input_h(input_h),
        .input_w(input_w),
        .cin(cin),
        .cout(cout),

        .kernel_size(kernel_size),
        .stride(stride),
        .padding(padding),
        .relu_en(relu_en),

        .input_count_value(input_count_value),
        .weight_count_value(weight_count_value),

        .input_data_word(input_data_word),
        .input_data_valid(input_data_valid),

        .weight_data_word(weight_data_word),
        .weight_data_valid(weight_data_valid),

        .core_output_data(compute_output_data),
        .core_output_count(compute_output_count),
        .output_read_pulse(output_read_pulse),

        .core_busy(controller_busy),

        // IMPORTANT:
        // MMIO expects DONE/ERROR events to latch its STATUS bits.
        // Use the compute event directly instead of controller_done,
        // because controller_done stays high in the DONE state.
        .core_done(mmio_core_done),

        .core_error(mmio_core_error),
        .core_error_code(mmio_core_error_code)
    );

    // ============================================================
    // Validation Block
    // ============================================================
    accelerator_validation u_validation (
        .input_h(input_h),
        .input_w(input_w),

        .cin(cin),
        .cout(cout),

        .kernel_size(kernel_size),
        .stride(stride),
        .padding(padding),

        .input_count_value(input_count_value),
        .weight_count_value(weight_count_value),

        .validation_ok(validation_ok)
    );

    // ============================================================
    // Controller FSM
    // ============================================================
    accelerator_controller u_controller (
        .clk(clk),
        .rst(rst),

        .start_pulse(start_pulse),
        .clear_pulse(clear_pulse),

        .validation_ok(validation_ok),

        .compute_done(compute_done),
        .compute_error(compute_error),

        .busy(controller_busy),
        .done(controller_done),
        .error(controller_error),

        .core_enable(core_enable)
    );

endmodule
