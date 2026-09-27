`timescale 1ns/1ps

module tb_accelerator_validation;

    // DUT Inputs
    reg  [15:0] input_h;
    reg  [15:0] input_w;
    reg  [15:0] cin;
    reg  [15:0] cout;

    reg  [7:0]  kernel_size;
    reg  [7:0]  stride;
    reg  [7:0]  padding;

    reg  [31:0] input_count_value;
    reg  [31:0] weight_count_value;

    // DUT Output
    wire validation_ok;

    // Testbench Counters
    integer pass_count;
    integer fail_count;

    // DUT
    accelerator_validation dut (
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

    // Waveform Dump
    initial begin
        $dumpfile("tb_accelerator_validation.vcd");
        $dumpvars(0, tb_accelerator_validation);
    end

    // Helper Task: Set Configuration
    task set_config;
        input [15:0] h;
        input [15:0] w;
        input [15:0] in_ch;
        input [15:0] out_ch;
        input [7:0]  k;
        input [7:0]  s;
        input [7:0]  p;
        input [31:0] in_count;
        input [31:0] wt_count;

        begin
            input_h            = h;
            input_w            = w;
            cin                = in_ch;
            cout               = out_ch;

            kernel_size        = k;
            stride             = s;
            padding            = p;

            input_count_value  = in_count;
            weight_count_value = wt_count;

            // Combinational logic settling time
            #1;
        end
    endtask

    // Helper Task: Check validation_ok
    task check_validation;
        input [8*64-1:0] name;
        input expected;

        begin
            if (validation_ok === expected) begin
                pass_count = pass_count + 1;
                $display(
                    "[PASS] %0s | validation_ok=%b",
                    name,
                    validation_ok
                );
            end
            else begin
                fail_count = fail_count + 1;
                $display(
                    "[FAIL] %0s | got=%b expected=%b",
                    name,
                    validation_ok,
                    expected
                );
            end
        end
    endtask

    // Test Sequence
    initial begin

        pass_count = 0;
        fail_count = 0;

        // Safe initial values
        input_h            = 16'd0;
        input_w            = 16'd0;
        cin                = 16'd0;
        cout               = 16'd0;

        kernel_size        = 8'd0;
        stride             = 8'd0;
        padding            = 8'd0;

        input_count_value  = 32'd0;
        weight_count_value = 32'd0;

        #1;

        $display("");
        $display("==============================================");
        $display(" AI Accelerator Validation Testbench");
        $display("==============================================");
        $display("");

        // ========================================================
        // TEST 1: Valid Conv1
        // H=28, W=28, Cin=1, Cout=16, K=3, S=1, P=1
        // Input  = 1*28*28       = 784
        // Weight = 16*1*3*3      = 144
        // Output = 16*28*28      = 12544
        // ========================================================
        set_config(
            16'd28, 16'd28,
            16'd1,  16'd16,
            8'd3, 8'd1, 8'd1,
            32'd784,
            32'd144
        );

        check_validation(
            "Valid Conv1",
            1'b1
        );

        // ========================================================
        // TEST 2: Valid Conv2
        // H=14, W=14, Cin=16, Cout=32
        // Input  = 16*14*14      = 3136
        // Weight = 32*16*3*3     = 4608
        // Output = 32*14*14      = 6272
        // ========================================================
        set_config(
            16'd14, 16'd14,
            16'd16, 16'd32,
            8'd3, 8'd1, 8'd1,
            32'd3136,
            32'd4608
        );

        check_validation(
            "Valid Conv2",
            1'b1
        );

        // ========================================================
        // TEST 3: Missing Input Data
        // ========================================================
        set_config(
            16'd28, 16'd28,
            16'd1,  16'd16,
            8'd3, 8'd1, 8'd1,
            32'd780,   // should be 784
            32'd144
        );

        check_validation(
            "Missing input data",
            1'b0
        );

        // ========================================================
        // TEST 4: Missing Weight Data
        // ========================================================
        set_config(
            16'd28, 16'd28,
            16'd1,  16'd16,
            8'd3, 8'd1, 8'd1,
            32'd784,
            32'd140    // should be 144
        );

        check_validation(
            "Missing weight data",
            1'b0
        );

        // ========================================================
        // TEST 5: Unsupported Kernel Size
        // ========================================================
        set_config(
            16'd28, 16'd28,
            16'd1,  16'd16,
            8'd5, 8'd1, 8'd1,
            32'd784,
            32'd400
        );

        check_validation(
            "Unsupported kernel size",
            1'b0
        );

        // ========================================================
        // TEST 6: Unsupported Stride
        // ========================================================
        set_config(
            16'd28, 16'd28,
            16'd1,  16'd16,
            8'd3, 8'd2, 8'd1,
            32'd784,
            32'd144
        );

        check_validation(
            "Unsupported stride",
            1'b0
        );

        // ========================================================
        // TEST 7: Unsupported Padding
        // ========================================================
        set_config(
            16'd28, 16'd28,
            16'd1,  16'd16,
            8'd3, 8'd1, 8'd0,
            32'd784,
            32'd144
        );

        check_validation(
            "Unsupported padding",
            1'b0
        );

        // ========================================================
        // TEST 8: Zero Dimension
        // ========================================================
        set_config(
            16'd0, 16'd28,
            16'd1, 16'd16,
            8'd3, 8'd1, 8'd1,
            32'd0,
            32'd144
        );

        check_validation(
            "Zero input dimension",
            1'b0
        );

        // ========================================================
        // TEST 9: Input Buffer Overflow
        // Input = 4*29*28 = 3248 > 3136
        // Weight = 4*4*3*3 = 144
        // Output = 4*29*28 = 3248
        // ========================================================
        set_config(
            16'd29, 16'd28,
            16'd4,  16'd4,
            8'd3, 8'd1, 8'd1,
            32'd3248,
            32'd144
        );

        check_validation(
            "Input buffer overflow",
            1'b0
        );

        // ========================================================
        // TEST 10: Weight Buffer Overflow
        // Input = 32*4*4 = 512
        // Weight = 17*32*3*3 = 4896 > 4608
        // Output = 17*4*4 = 272
        // ========================================================
        set_config(
            16'd4,  16'd4,
            16'd32, 16'd17,
            8'd3, 8'd1, 8'd1,
            32'd512,
            32'd4896
        );

        check_validation(
            "Weight buffer overflow",
            1'b0
        );

        // ========================================================
        // TEST 11: Output Buffer Overflow
        // Input = 1*28*28 = 784
        // Weight = 20*1*3*3 = 180
        // Output = 20*28*28 = 15680 > 12544
        // ========================================================
        set_config(
            16'd28, 16'd28,
            16'd1,  16'd20,
            8'd3, 8'd1, 8'd1,
            32'd784,
            32'd180
        );

        check_validation(
            "Output buffer overflow",
            1'b0
        );

        // ========================================================
        // TEST 12: INT8 Packing Alignment Failure
        // Input count = 1 is not divisible by 4.
        // ========================================================
        set_config(
            16'd1, 16'd1,
            16'd1, 16'd4,
            8'd3, 8'd1, 8'd1,
            32'd1,
            32'd36
        );

        check_validation(
            "Input packing alignment failure",
            1'b0
        );

        // ========================================================
        // TEST 13: Wrong Input Count Even Though Configuration Valid
        // ========================================================
        set_config(
            16'd14, 16'd14,
            16'd16, 16'd32,
            8'd3, 8'd1, 8'd1,
            32'd3132,   // should be 3136
            32'd4608
        );

        check_validation(
            "Conv2 incorrect input count",
            1'b0
        );

        // ========================================================
        // TEST 14: Wrong Weight Count Even Though Configuration Valid
        // ========================================================
        set_config(
            16'd14, 16'd14,
            16'd16, 16'd32,
            8'd3, 8'd1, 8'd1,
            32'd3136,
            32'd4604    // should be 4608
        );

        check_validation(
            "Conv2 incorrect weight count",
            1'b0
        );

        // ========================================================
        // Final Summary
        // ========================================================
        $display("");
        $display("==============================================");
        $display(" TEST SUMMARY");
        $display("==============================================");
        $display(" PASS = %0d", pass_count);
        $display(" FAIL = %0d", fail_count);

        if (fail_count == 0)
            $display(" RESULT: ALL TESTS PASSED");
        else
            $display(" RESULT: TESTBENCH FAILED");

        $display(" VCD: tb_accelerator_validation.vcd");
        $display("==============================================");
        $display("");

        #10;
        $finish;
    end

endmodule
