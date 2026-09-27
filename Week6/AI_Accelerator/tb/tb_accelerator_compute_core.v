`timescale 1ns/1ps

module tb_accelerator_compute_core;

    // ============================================================
    // Small-but-complete configuration for unit/integration test
    // ============================================================
    localparam integer INPUT_MAX_VALUES  = 16;  // 1 x 4 x 4
    localparam integer WEIGHT_MAX_VALUES = 36;  // 4 x 1 x 3 x 3
    localparam integer OUTPUT_MAX_VALUES = 64;  // 4 x 4 x 4

    localparam integer INPUT_ADDR_WIDTH  = 4;
    localparam integer WEIGHT_ADDR_WIDTH = 6;
    localparam integer OUTPUT_ADDR_WIDTH = 6;

    // ============================================================
    // DUT Inputs
    // ============================================================
    reg clk;
    reg rst;
    reg clear;

    reg core_enable;

    reg [15:0] input_h;
    reg [15:0] input_w;
    reg [15:0] cin;
    reg [15:0] cout;

    reg [7:0] kernel_size;
    reg [7:0] stride;
    reg [7:0] padding;
    reg       relu_en;

    reg [31:0] input_data_word;
    reg        input_data_valid;

    reg [31:0] weight_data_word;
    reg        weight_data_valid;

    reg        output_read_pulse;

    // ============================================================
    // DUT Outputs
    // ============================================================
    wire [31:0] core_output_data;
    wire [31:0] core_output_count;

    wire        compute_busy;
    wire        compute_done;
    wire        compute_error;
    wire [31:0] compute_error_code;

    wire [31:0] input_buffer_count;
    wire [31:0] weight_buffer_count;
    wire [31:0] output_read_index;

    wire [15:0] out_h;
    wire [15:0] out_w;

    // ============================================================
    // Test Data
    // ============================================================
    reg signed [31:0] base_sum [0:15];
    reg signed [31:0] expected_output [0:63];

    integer pass_count;
    integer fail_count;
    integer timeout_count;

    integer oc;
    integer pos;
    integer i;

    // ============================================================
    // DUT
    // ============================================================
    accelerator_compute_core #(
        .INPUT_MAX_VALUES(INPUT_MAX_VALUES),
        .WEIGHT_MAX_VALUES(WEIGHT_MAX_VALUES),
        .OUTPUT_MAX_VALUES(OUTPUT_MAX_VALUES),

        .INPUT_ADDR_WIDTH(INPUT_ADDR_WIDTH),
        .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH),
        .OUTPUT_ADDR_WIDTH(OUTPUT_ADDR_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .clear(clear),

        .core_enable(core_enable),

        .input_h(input_h),
        .input_w(input_w),
        .cin(cin),
        .cout(cout),

        .kernel_size(kernel_size),
        .stride(stride),
        .padding(padding),
        .relu_en(relu_en),

        .input_data_word(input_data_word),
        .input_data_valid(input_data_valid),

        .weight_data_word(weight_data_word),
        .weight_data_valid(weight_data_valid),

        .core_output_data(core_output_data),
        .core_output_count(core_output_count),
        .output_read_pulse(output_read_pulse),

        .compute_busy(compute_busy),
        .compute_done(compute_done),
        .compute_error(compute_error),
        .compute_error_code(compute_error_code),

        .input_buffer_count(input_buffer_count),
        .weight_buffer_count(weight_buffer_count),
        .output_read_index(output_read_index),

        .out_h(out_h),
        .out_w(out_w)
    );

    // ============================================================
    // 100 MHz Clock
    // ============================================================
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // ============================================================
    // Waveform Dump
    // ============================================================
    initial begin
        $dumpfile("tb_accelerator_compute_core.vcd");
        $dumpvars(0, tb_accelerator_compute_core);
    end

    // ============================================================
    // Helpers: Packed MMIO-style Input / Weight Writes
    // ============================================================
    task write_input_word;
        input [31:0] data;
        begin
            @(negedge clk);

            input_data_word  = data;
            input_data_valid = 1'b1;

            @(posedge clk);
            #1;

            @(negedge clk);

            input_data_valid = 1'b0;
            input_data_word  = 32'd0;
        end
    endtask

    task write_weight_word;
        input [31:0] data;
        begin
            @(negedge clk);

            weight_data_word  = data;
            weight_data_valid = 1'b1;

            @(posedge clk);
            #1;

            @(negedge clk);

            weight_data_valid = 1'b0;
            weight_data_word  = 32'd0;
        end
    endtask

    // ============================================================
    // Helper: Assert core_enable and KEEP it high
    //
    // This matches the real accelerator controller behavior:
    // core_enable stays high throughout RUN.
    // accelerator_compute_core must generate only one engine_start.
    // ============================================================
    task start_core;
        begin
            @(negedge clk);
            core_enable = 1'b1;

            @(posedge clk);
            #1;
        end
    endtask

    // ============================================================
    // Helper: Wait for Compute DONE
    // ============================================================
    task wait_for_compute_done;
        begin
            timeout_count = 0;

            while ((compute_done !== 1'b1) &&
                   (timeout_count < 3000)) begin

                @(posedge clk);
                #1;

                timeout_count = timeout_count + 1;
            end

            if (compute_done !== 1'b1) begin

                fail_count = fail_count + 1;
                $display("[FAIL] Timeout waiting for compute_done");

            end
        end
    endtask

    // ============================================================
    // Helper: Advance MMIO Output Read Pointer
    // ============================================================
    task advance_output_read;
        begin
            @(negedge clk);
            output_read_pulse = 1'b1;

            @(posedge clk);
            #1;

            @(negedge clk);
            output_read_pulse = 1'b0;
        end
    endtask

    // ============================================================
    // Helper: Global Clear
    // ============================================================
    task clear_core;
        begin
            @(negedge clk);

            core_enable = 1'b0;
            clear       = 1'b1;

            @(posedge clk);
            #1;

            @(negedge clk);
            clear = 1'b0;

            repeat (2) @(posedge clk);
            #1;
        end
    endtask

    // ============================================================
    // Check Helpers
    // ============================================================
    task check1;
        input [8*88-1:0] name;
        input got;
        input expected;
        begin
            if (got === expected) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s | got=%b", name, got);
            end
            else begin
                fail_count = fail_count + 1;
                $display(
                    "[FAIL] %0s | got=%b expected=%b",
                    name, got, expected
                );
            end
        end
    endtask

    task check16;
        input [8*88-1:0] name;
        input [15:0] got;
        input [15:0] expected;
        begin
            if (got === expected) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s | got=%0d", name, got);
            end
            else begin
                fail_count = fail_count + 1;
                $display(
                    "[FAIL] %0s | got=%0d expected=%0d",
                    name, got, expected
                );
            end
        end
    endtask

    task check32;
        input [8*88-1:0] name;
        input [31:0] got;
        input [31:0] expected;
        begin
            if (got === expected) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s | got=%0d", name, got);
            end
            else begin
                fail_count = fail_count + 1;
                $display(
                    "[FAIL] %0s | got=%0d expected=%0d",
                    name, got, expected
                );
            end
        end
    endtask

    task check32s;
        input [8*88-1:0] name;
        input signed [31:0] got;
        input signed [31:0] expected;
        begin
            if (got === expected) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s | got=%0d", name, got);
            end
            else begin
                fail_count = fail_count + 1;
                $display(
                    "[FAIL] %0s | got=%0d expected=%0d",
                    name, got, expected
                );
            end
        end
    endtask

    // ============================================================
    // Build Golden Output
    //
    // Input:
    //   1   2   3   4
    //   5   6   7   8
    //   9  10  11  12
    //  13  14  15  16
    //
    // 3x3, stride=1, padding=1
    //
    // OC0 kernel = all 1
    // OC1 kernel = all 2
    // OC2 kernel = all 3
    // OC3 kernel = all 4
    //
    // Output layout: [COUT][H][W]
    // ============================================================
    task build_expected_output;
        begin

            base_sum[0]  = 32'sd14;
            base_sum[1]  = 32'sd24;
            base_sum[2]  = 32'sd30;
            base_sum[3]  = 32'sd22;

            base_sum[4]  = 32'sd33;
            base_sum[5]  = 32'sd54;
            base_sum[6]  = 32'sd63;
            base_sum[7]  = 32'sd45;

            base_sum[8]  = 32'sd57;
            base_sum[9]  = 32'sd90;
            base_sum[10] = 32'sd99;
            base_sum[11] = 32'sd69;

            base_sum[12] = 32'sd46;
            base_sum[13] = 32'sd72;
            base_sum[14] = 32'sd78;
            base_sum[15] = 32'sd54;

            for (oc = 0; oc < 4; oc = oc + 1) begin
                for (pos = 0; pos < 16; pos = pos + 1) begin
                    expected_output[(oc * 16) + pos]
                        = base_sum[pos] * (oc + 1);
                end
            end

        end
    endtask

    // ============================================================
    // Global Watchdog
    // ============================================================
    initial begin
        #2000000;

        $display("");
        $display("[FAIL] GLOBAL TESTBENCH TIMEOUT");
        $finish;
    end

    // ============================================================
    // Main Test Sequence
    // ============================================================
    initial begin

        pass_count = 0;
        fail_count = 0;

        rst        = 1'b1;
        clear      = 1'b0;

        core_enable = 1'b0;

        input_h     = 16'd4;
        input_w     = 16'd4;
        cin         = 16'd1;
        cout        = 16'd4;

        kernel_size = 8'd3;
        stride      = 8'd1;
        padding     = 8'd1;
        relu_en     = 1'b1;

        input_data_word  = 32'd0;
        input_data_valid = 1'b0;

        weight_data_word  = 32'd0;
        weight_data_valid = 1'b0;

        output_read_pulse = 1'b0;

        build_expected_output();

        repeat (3) @(posedge clk);
        #1;

        $display("");
        $display("==================================================");
        $display(" Accelerator Compute Core Testbench");
        $display("==================================================");
        $display("");

        // ========================================================
        // TEST 1: Reset / Output Shape
        // ========================================================
        $display("---- TEST 1: Reset / Configuration ----");

        check1 ("compute_busy after reset", compute_busy, 1'b0);
        check1 ("compute_done after reset", compute_done, 1'b0);
        check1 ("compute_error after reset", compute_error, 1'b0);

        check32("input count after reset", input_buffer_count, 32'd0);
        check32("weight count after reset", weight_buffer_count, 32'd0);
        check32("output count after reset", core_output_count, 32'd0);
        check32("output read index after reset", output_read_index, 32'd0);

        check16("calculated OUT_H", out_h, 16'd4);
        check16("calculated OUT_W", out_w, 16'd4);

        @(negedge clk);
        rst = 1'b0;

        // ========================================================
        // TEST 2: Load Activation / Weight Buffers
        // ========================================================
        $display("");
        $display("---- TEST 2: Load Input / Weights ----");

        // Input image 1..16
        write_input_word(32'h0403_0201);
        write_input_word(32'h0807_0605);
        write_input_word(32'h0C0B_0A09);
        write_input_word(32'h100F_0E0D);

        // Four 3x3 filters:
        // OC0 = 1, OC1 = 2, OC2 = 3, OC3 = 4
        write_weight_word(32'h0101_0101);
        write_weight_word(32'h0101_0101);
        write_weight_word(32'h0202_0201);
        write_weight_word(32'h0202_0202);
        write_weight_word(32'h0303_0202);
        write_weight_word(32'h0303_0303);
        write_weight_word(32'h0403_0303);
        write_weight_word(32'h0404_0404);
        write_weight_word(32'h0404_0404);

        check32("input buffer count", input_buffer_count, 32'd16);
        check32("weight buffer count", weight_buffer_count, 32'd36);

        check1("no error after normal load", compute_error, 1'b0);
        check32("error code after normal load",
                compute_error_code, 32'h0000_0000);

        // ========================================================
        // TEST 3: core_enable Rising Edge Starts Full Convolution
        //
        // Keep core_enable HIGH for the entire RUN, exactly like
        // accelerator_controller does.
        // ========================================================
        $display("");
        $display("---- TEST 3: Automatic Compute Run ----");

        start_core();

        check1("compute_busy after core_enable", compute_busy, 1'b1);
        check1("compute_done initially low", compute_done, 1'b0);

        wait_for_compute_done();

        check1("compute_done asserted", compute_done, 1'b1);
        check1("compute_error remains low", compute_error, 1'b0);

        // All 4*4*4 output values must have been written.
        check32("full output count", core_output_count, 32'd64);
        check32("output read index before MMIO reads",
                output_read_index, 32'd0);

        // ========================================================
        // TEST 4: Holding core_enable HIGH Must NOT Restart Engine
        // ========================================================
        $display("");
        $display("---- TEST 4: No Restart While core_enable Stays High ----");

        repeat (5) @(posedge clk);
        #1;

        check1("compute_done still high", compute_done, 1'b1);
        check32("output count did not double",
                core_output_count, 32'd64);
        check1("still no compute error", compute_error, 1'b0);

        // Now drop the RUN-level signal.
        @(negedge clk);
        core_enable = 1'b0;

        // ========================================================
        // TEST 5: Sequential MMIO-Style Readback
        //
        // Read all 64 outputs in [COUT][H][W] order and compare
        // every value with the expected convolution result.
        // ========================================================
        $display("");
        $display("---- TEST 5: Read Back All 64 Outputs ----");

        for (i = 0; i < 64; i = i + 1) begin

            if ($signed(core_output_data) === expected_output[i]) begin

                pass_count = pass_count + 1;

                $display(
                    "[PASS] output[%0d] = %0d",
                    i,
                    $signed(core_output_data)
                );

            end
            else begin

                fail_count = fail_count + 1;

                $display(
                    "[FAIL] output[%0d] got=%0d expected=%0d",
                    i,
                    $signed(core_output_data),
                    expected_output[i]
                );

            end

            advance_output_read();

        end

        check32("output read index after 64 reads",
                output_read_index, 32'd64);

        check32s("output data after all reads",
                 $signed(core_output_data), 32'sd0);

        // ========================================================
        // TEST 6: Global CLEAR
        // ========================================================
        $display("");
        $display("---- TEST 6: CLEAR ----");

        clear_core();

        check1 ("compute_busy after clear", compute_busy, 1'b0);
        check1 ("compute_done after clear", compute_done, 1'b0);
        check1 ("compute_error after clear", compute_error, 1'b0);

        check32("input count after clear", input_buffer_count, 32'd0);
        check32("weight count after clear", weight_buffer_count, 32'd0);
        check32("output count after clear", core_output_count, 32'd0);
        check32("output read index after clear", output_read_index, 32'd0);

        // ========================================================
        // TEST 7: Input Buffer Overflow Error Aggregation
        //
        // INPUT_MAX_VALUES = 16.
        // Four words fill it; the fifth must set:
        //   compute_error      = 1
        //   compute_error_code = 0x10
        // ========================================================
        $display("");
        $display("---- TEST 7: Input Buffer Overflow Error ----");

        write_input_word(32'h0403_0201);
        write_input_word(32'h0807_0605);
        write_input_word(32'h0C0B_0A09);
        write_input_word(32'h100F_0E0D);

        check1("no input overflow at exact capacity",
               compute_error, 1'b0);

        write_input_word(32'h1413_1211);

        check1("input overflow -> compute_error",
               compute_error, 1'b1);

        check32("input overflow error code",
                compute_error_code, 32'h0000_0010);

        check32("input count stays at capacity",
                input_buffer_count, 32'd16);

        // ========================================================
        // TEST 8: Weight Buffer Overflow Error Aggregation
        //
        // Clear first so input overflow no longer has priority.
        // WEIGHT_MAX_VALUES = 36 = 9 packed writes.
        // Tenth write must produce code 0x11.
        // ========================================================
        $display("");
        $display("---- TEST 8: Weight Buffer Overflow Error ----");

        clear_core();

        for (i = 0; i < 9; i = i + 1)
            write_weight_word(32'h0101_0101);

        check32("weight count at exact capacity",
                weight_buffer_count, 32'd36);

        check1("no weight overflow at exact capacity",
               compute_error, 1'b0);

        write_weight_word(32'h0202_0202);

        check1("weight overflow -> compute_error",
               compute_error, 1'b1);

        check32("weight overflow error code",
                compute_error_code, 32'h0000_0011);

        check32("weight count stays at capacity",
                weight_buffer_count, 32'd36);

        // ========================================================
        // Final Cleanup
        // ========================================================
        clear_core();

        // ========================================================
        // Final Summary
        // ========================================================
        $display("");
        $display("==================================================");
        $display(" TEST SUMMARY");
        $display("==================================================");
        $display(" PASS = %0d", pass_count);
        $display(" FAIL = %0d", fail_count);

        if (fail_count == 0)
            $display(" RESULT: ALL TESTS PASSED");
        else
            $display(" RESULT: TESTBENCH FAILED");

        $display(" VCD: tb_accelerator_compute_core.vcd");
        $display("==================================================");
        $display("");

        repeat (3) @(posedge clk);
        $finish;
    end

endmodule
