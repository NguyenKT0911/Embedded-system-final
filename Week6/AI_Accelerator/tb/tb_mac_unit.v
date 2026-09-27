`timescale 1ns/1ps

module tb_mac_unit;

    // ============================================================
    // DUT Inputs
    // ============================================================
    reg signed [7:0]  activation;
    reg signed [7:0]  weight;
    reg signed [31:0] acc_in;

    // ============================================================
    // DUT Output
    // ============================================================
    wire signed [31:0] acc_out;

    // ============================================================
    // Test Counters
    // ============================================================
    integer pass_count;
    integer fail_count;

    // ============================================================
    // DUT
    // ============================================================
    mac_unit dut (
        .activation(activation),
        .weight(weight),
        .acc_in(acc_in),
        .acc_out(acc_out)
    );

    // ============================================================
    // Waveform Dump
    // ============================================================
    initial begin
        $dumpfile("tb_mac_unit.vcd");
        $dumpvars(0, tb_mac_unit);
    end

    // ============================================================
    // Test Task
    // ============================================================
    task run_case;
        input [8*64-1:0] name;
        input signed [7:0]  act;
        input signed [7:0]  wgt;
        input signed [31:0] acc;
        input signed [31:0] expected;

        begin
            activation = act;
            weight     = wgt;
            acc_in     = acc;

            // Combinational settling time
            #1;

            if (acc_out === expected) begin
                pass_count = pass_count + 1;

                $display(
                    "[PASS] %0s | act=%0d weight=%0d acc_in=%0d acc_out=%0d",
                    name,
                    activation,
                    weight,
                    acc_in,
                    acc_out
                );
            end
            else begin
                fail_count = fail_count + 1;

                $display(
                    "[FAIL] %0s | act=%0d weight=%0d acc_in=%0d got=%0d expected=%0d",
                    name,
                    activation,
                    weight,
                    acc_in,
                    acc_out,
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

        activation = 8'sd0;
        weight     = 8'sd0;
        acc_in     = 32'sd0;

        #1;

        $display("");
        $display("==============================================");
        $display(" MAC Unit Testbench");
        $display("==============================================");
        $display("");

        // ========================================================
        // TEST 1: Zero
        // 0 * 0 + 0 = 0
        // ========================================================
        run_case(
            "Zero",
            8'sd0,
            8'sd0,
            32'sd0,
            32'sd0
        );

        // ========================================================
        // TEST 2: Positive x Positive
        // 5 * 3 + 10 = 25
        // ========================================================
        run_case(
            "Positive x Positive",
            8'sd5,
            8'sd3,
            32'sd10,
            32'sd25
        );

        // ========================================================
        // TEST 3: Negative x Positive
        // -5 * 3 + 20 = 5
        // ========================================================
        run_case(
            "Negative x Positive",
            -8'sd5,
            8'sd3,
            32'sd20,
            32'sd5
        );

        // ========================================================
        // TEST 4: Positive x Negative
        // 7 * -4 + 50 = 22
        // ========================================================
        run_case(
            "Positive x Negative",
            8'sd7,
            -8'sd4,
            32'sd50,
            32'sd22
        );

        // ========================================================
        // TEST 5: Negative x Negative
        // -6 * -7 + 8 = 50
        // ========================================================
        run_case(
            "Negative x Negative",
            -8'sd6,
            -8'sd7,
            32'sd8,
            32'sd50
        );

        // ========================================================
        // TEST 6: Negative Accumulator
        // 4 * 5 + (-100) = -80
        // ========================================================
        run_case(
            "Negative accumulator",
            8'sd4,
            8'sd5,
            -32'sd100,
            -32'sd80
        );

        // ========================================================
        // TEST 7: Max Positive INT8
        // 127 * 127 = 16129
        // ========================================================
        run_case(
            "INT8 max positive",
            8'sd127,
            8'sd127,
            32'sd0,
            32'sd16129
        );

        // ========================================================
        // TEST 8: Min Negative INT8
        // -128 * -128 = 16384
        // ========================================================
        run_case(
            "INT8 min negative squared",
            -8'sd128,
            -8'sd128,
            32'sd0,
            32'sd16384
        );

        // ========================================================
        // TEST 9: Max Positive x Min Negative
        // 127 * -128 = -16256
        // ========================================================
        run_case(
            "INT8 max x min",
            8'sd127,
            -8'sd128,
            32'sd0,
            -32'sd16256
        );

        // ========================================================
        // TEST 10: Add Positive Accumulator
        // 10 * 10 + 1000 = 1100
        // ========================================================
        run_case(
            "Positive accumulation",
            8'sd10,
            8'sd10,
            32'sd1000,
            32'sd1100
        );

        // ========================================================
        // TEST 11: Add Negative Product to Large Accumulator
        // -100 * 50 + 10000 = 5000
        // ========================================================
        run_case(
            "Large accumulator with negative product",
            -8'sd100,
            8'sd50,
            32'sd10000,
            32'sd5000
        );

        // ========================================================
        // TEST 12: Product Only
        // -12 * 11 + 0 = -132
        // ========================================================
        run_case(
            "Product only",
            -8'sd12,
            8'sd11,
            32'sd0,
            -32'sd132
        );

        // ========================================================
        // TEST 13: Accumulator Pass-Through
        // activation = 0, so output must equal acc_in
        // ========================================================
        run_case(
            "Accumulator pass-through",
            8'sd0,
            -8'sd100,
            32'sd123456,
            32'sd123456
        );

        // ========================================================
        // TEST 14: Sign Extension Check
        // -128 * 1 + 0 = -128
        // This specifically checks INT16 -> INT32 sign extension.
        // ========================================================
        run_case(
            "Sign extension check",
            -8'sd128,
            8'sd1,
            32'sd0,
            -32'sd128
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

        $display(" VCD: tb_mac_unit.vcd");
        $display("==============================================");
        $display("");

        #10;
        $finish;
    end

endmodule
