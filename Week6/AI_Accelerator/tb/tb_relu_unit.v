`timescale 1ns/1ps

module tb_relu_unit;

    // ============================================================
    // DUT Inputs
    // ============================================================
    reg                      relu_en;
    reg signed [31:0]        data_in;

    // ============================================================
    // DUT Output
    // ============================================================
    wire signed [31:0]       data_out;

    // ============================================================
    // Test Counters
    // ============================================================
    integer pass_count;
    integer fail_count;

    // ============================================================
    // DUT
    // ============================================================
    relu_unit dut (
        .relu_en(relu_en),
        .data_in(data_in),
        .data_out(data_out)
    );

    // ============================================================
    // Waveform Dump
    // ============================================================
    initial begin
        $dumpfile("tb_relu_unit.vcd");
        $dumpvars(0, tb_relu_unit);
    end

    // ============================================================
    // Test Helper
    // ============================================================
    task run_case;
        input [8*64-1:0] name;
        input            en;
        input signed [31:0] in_value;
        input signed [31:0] expected;

        begin
            relu_en = en;
            data_in = in_value;

            #1;

            if (data_out === expected) begin
                pass_count = pass_count + 1;

                $display(
                    "[PASS] %0s | relu_en=%b data_in=%0d data_out=%0d",
                    name,
                    relu_en,
                    data_in,
                    data_out
                );
            end
            else begin
                fail_count = fail_count + 1;

                $display(
                    "[FAIL] %0s | relu_en=%b data_in=%0d got=%0d expected=%0d",
                    name,
                    relu_en,
                    data_in,
                    data_out,
                    expected
                );
            end
        end
    endtask

    // ============================================================
    // Main Test Sequence
    // ============================================================
    initial begin

        pass_count = 0;
        fail_count = 0;

        relu_en = 1'b0;
        data_in = 32'sd0;

        #1;

        $display("");
        $display("==============================================");
        $display(" ReLU Unit Testbench");
        $display("==============================================");
        $display("");

        // ========================================================
        // TEST 1: ReLU OFF / Positive
        // ========================================================
        run_case(
            "ReLU OFF positive pass-through",
            1'b0,
            32'sd25,
            32'sd25
        );

        // ========================================================
        // TEST 2: ReLU OFF / Negative
        // ========================================================
        run_case(
            "ReLU OFF negative pass-through",
            1'b0,
            -32'sd25,
            -32'sd25
        );

        // ========================================================
        // TEST 3: ReLU OFF / Zero
        // ========================================================
        run_case(
            "ReLU OFF zero",
            1'b0,
            32'sd0,
            32'sd0
        );

        // ========================================================
        // TEST 4: ReLU ON / Positive
        // ========================================================
        run_case(
            "ReLU ON positive",
            1'b1,
            32'sd100,
            32'sd100
        );

        // ========================================================
        // TEST 5: ReLU ON / Negative
        // ========================================================
        run_case(
            "ReLU ON negative becomes zero",
            1'b1,
            -32'sd100,
            32'sd0
        );

        // ========================================================
        // TEST 6: ReLU ON / Zero
        // ========================================================
        run_case(
            "ReLU ON zero",
            1'b1,
            32'sd0,
            32'sd0
        );

        // ========================================================
        // TEST 7: Maximum Positive INT32
        // ========================================================
        run_case(
            "ReLU ON INT32 max",
            1'b1,
            32'sh7FFF_FFFF,
            32'sh7FFF_FFFF
        );

        // ========================================================
        // TEST 8: Minimum Negative INT32
        // ========================================================
        run_case(
            "ReLU ON INT32 min",
            1'b1,
            32'sh8000_0000,
            32'sd0
        );

        // ========================================================
        // TEST 9: Minimum Negative INT32 with ReLU OFF
        // ========================================================
        run_case(
            "ReLU OFF INT32 min pass-through",
            1'b0,
            32'sh8000_0000,
            32'sh8000_0000
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

        $display(" VCD: tb_relu_unit.vcd");
        $display("==============================================");
        $display("");

        #10;
        $finish;
    end

endmodule
