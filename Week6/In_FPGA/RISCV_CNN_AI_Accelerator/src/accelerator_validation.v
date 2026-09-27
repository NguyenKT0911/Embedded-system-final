`timescale 1ns/1ps

module accelerator_validation (

    // Convolution Configuration
    input  wire [15:0] input_h,
    input  wire [15:0] input_w,

    input  wire [15:0] cin,
    input  wire [15:0] cout,

    input  wire [7:0]  kernel_size,
    input  wire [7:0]  stride,
    input  wire [7:0]  padding,

    // Data Counters from MMIO
    input  wire [31:0] input_count_value,
    input  wire [31:0] weight_count_value,

    // Validation Result
    output reg          validation_ok
);

    // Version 0.1 Limits
    localparam [31:0] MAX_INPUT_VALUES  = 32'd3136;
    localparam [31:0] MAX_WEIGHT_VALUES = 32'd4608;
    localparam [31:0] MAX_OUTPUT_VALUES = 32'd12544;

    // Expected Data Counts
    reg [63:0] expected_input_count;
    reg [63:0] expected_weight_count;
    reg [63:0] expected_output_count;

    reg [31:0] out_h;
    reg [31:0] out_w;

    // Validation Logic
    always @(*) begin
        // Default values
        validation_ok        = 1'b0;

        expected_input_count  = 64'd0;
        expected_weight_count = 64'd0;
        expected_output_count = 64'd0;

        out_h = 32'd0;
        out_w = 32'd0;

        // Calculate expected tensor sizes
        // Version 0.1 supports K=3, S=1, P=1
        if ((input_h > 0) &&
            (input_w > 0) &&
            (cin > 0) &&
            (cout > 0) &&
            (kernel_size == 8'd3) &&
            (stride == 8'd1) &&
            (padding == 8'd1)) begin

            out_h = input_h + (padding << 1)
                    - kernel_size + 1;

            out_w = input_w + (padding << 1)
                    - kernel_size + 1;

            expected_input_count =
                cin * input_h * input_w;

            expected_weight_count =
                cout * cin * kernel_size * kernel_size;

            expected_output_count =
                cout * out_h * out_w;

            // Final Validation
            if (
                // Correct number of input activations
                (input_count_value == expected_input_count) &&

                // Correct number of weights
                (weight_count_value == expected_weight_count) &&

                // Input buffer capacity
                (expected_input_count <= MAX_INPUT_VALUES) &&

                // Weight buffer capacity
                (expected_weight_count <= MAX_WEIGHT_VALUES) &&

                // Output buffer capacity
                (expected_output_count <= MAX_OUTPUT_VALUES) &&

                // Version 0.1 uses four INT8 values per MMIO word
                ((expected_input_count % 4) == 0) &&

                ((expected_weight_count % 4) == 0)
            ) begin

                validation_ok = 1'b1;

            end

        end

    end

endmodule