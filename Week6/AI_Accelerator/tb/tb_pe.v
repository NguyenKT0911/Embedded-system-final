`timescale 1ns/1ps

module tb_pe;

    // ============================================================
    // DUT Inputs
    // ============================================================
    reg clk;
    reg rst;

    reg clear_acc;
    reg enable;

    reg signed [7:0] activation;
    reg signed [7:0] weight;

    // ============================================================
    // DUT Output
    // ============================================================
    wire signed [31:0] accumulator;

    // ============================================================
    // Test Counters
    // ============================================================
    integer pass_count;
    integer fail_count;

    // ============================================================
    // DUT
    // ============================================================
    pe dut (
        .clk(clk),
        .rst(rst),

        .clear_acc(clear_acc),
        .enable(enable),

        .activation(activation),
        .weight(weight),

        .accumulator(accumulator)
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
        $dumpfile("tb_pe.vcd");
        $dumpvars(0, tb_pe);
    end

    // ============================================================
    // Check signed INT32
    // ============================================================
    task check32s;
        input [8*64-1:0] name;
        input signed [31:0] got;
        input signed [31:0] expected;
        begin
            if (got === expected) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s | got=%0d", name, got);
            end
            else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s | got=%0d expected=%0d",
                         name, got, expected);
            end
        end
    endtask

    // ============================================================
    // Apply one MAC cycle
    // ============================================================
    task mac_cycle;
        input signed [7:0] act;
        input signed [7:0] wgt;
        begin
            @(negedge clk);
            activation = act;
            weight     = wgt;
            enable     = 1'b1;

            @(posedge clk);
            #1;

            @(negedge clk);
            enable     = 1'b0;
        end
    endtask

    // ============================================================
    // Clear accumulator for one clock
    // ============================================================
    task clear_accumulator;
        begin
            @(negedge clk);
            clear_acc = 1'b1;

            @(posedge clk);
            #1;

            @(negedge clk);
            clear_acc = 1'b0;
        end
    endtask

    // ============================================================
    // Main Test Sequence
    // ============================================================
    initial begin

        pass_count = 0;
        fail_count = 0;

        rst        = 1'b1;
        clear_acc  = 1'b0;
        enable     = 1'b0;

        activation = 8'sd0;
        weight     = 8'sd0;

        repeat (3) @(posedge clk);
        #1;

        $display("");
        $display("==============================================");
        $display(" PE Testbench");
        $display("==============================================");
        $display("");

        // ========================================================
        // TEST 1: Reset
        // ========================================================
        check32s("Accumulator after reset",
                 accumulator,
                 32'sd0);

        @(negedge clk);
        rst = 1'b0;

        // ========================================================
        // TEST 2: First MAC
        // 0 + (2 * 3) = 6
        // ========================================================
        $display("");
        $display("---- TEST 2: First MAC ----");

        mac_cycle(8'sd2, 8'sd3);

        check32s("2 * 3",
                 accumulator,
                 32'sd6);

        // ========================================================
        // TEST 3: Accumulate second MAC
        // 6 + (4 * 5) = 26
        // ========================================================
        $display("");
        $display("---- TEST 3: Accumulate ----");

        mac_cycle(8'sd4, 8'sd5);

        check32s("6 + 4*5",
                 accumulator,
                 32'sd26);

        // ========================================================
        // TEST 4: Add negative product
        // 26 + (-2 * 3) = 20
        // ========================================================
        $display("");
        $display("---- TEST 4: Negative Product ----");

        mac_cycle(-8'sd2, 8'sd3);

        check32s("26 + (-2*3)",
                 accumulator,
                 32'sd20);

        // ========================================================
        // TEST 5: Hold when enable=0
        // Inputs change, accumulator must remain 20.
        // ========================================================
        $display("");
        $display("---- TEST 5: Enable Hold ----");

        @(negedge clk);
        activation = 8'sd100;
        weight     = 8'sd100;
        enable     = 1'b0;

        repeat (2) @(posedge clk);
        #1;

        check32s("Accumulator holds when enable=0",
                 accumulator,
                 32'sd20);

        // ========================================================
        // TEST 6: Clear accumulator
        // ========================================================
        $display("");
        $display("---- TEST 6: Clear ----");

        clear_accumulator();

        check32s("Accumulator after clear",
                 accumulator,
                 32'sd0);

        // ========================================================
        // TEST 7: Negative x Negative after clear
        // 0 + (-6 * -7) = 42
        // ========================================================
        $display("");
        $display("---- TEST 7: Negative x Negative ----");

        mac_cycle(-8'sd6, -8'sd7);

        check32s("-6 * -7",
                 accumulator,
                 32'sd42);

        // ========================================================
        // TEST 8: Priority clear_acc over enable
        //
        // Both high at same rising edge:
        // expected accumulator = 0, NOT 42 + 100.
        // ========================================================
        $display("");
        $display("---- TEST 8: clear_acc Priority ----");

        @(negedge clk);
        activation = 8'sd10;
        weight     = 8'sd10;
        enable     = 1'b1;
        clear_acc  = 1'b1;

        @(posedge clk);
        #1;

        check32s("clear_acc priority over enable",
                 accumulator,
                 32'sd0);

        @(negedge clk);
        enable    = 1'b0;
        clear_acc = 1'b0;

        // ========================================================
        // TEST 9: INT8 maximum values
        // 127 * 127 = 16129
        // ========================================================
        $display("");
        $display("---- TEST 9: INT8 Max ----");

        mac_cycle(8'sd127, 8'sd127);

        check32s("127 * 127",
                 accumulator,
                 32'sd16129);

        // ========================================================
        // TEST 10: INT8 minimum values accumulate
        // 16129 + (-128 * -128)
        // = 16129 + 16384
        // = 32513
        // ========================================================
        $display("");
        $display("---- TEST 10: INT8 Min ----");

        mac_cycle(-8'sd128, -8'sd128);

        check32s("16129 + (-128 * -128)",
                 accumulator,
                 32'sd32513);

        // ========================================================
        // TEST 11: Sign extension through MAC inside PE
        //
        // 32513 + (-128 * 1) = 32385
        // ========================================================
        $display("");
        $display("---- TEST 11: Sign Extension ----");

        mac_cycle(-8'sd128, 8'sd1);

        check32s("32513 + (-128)",
                 accumulator,
                 32'sd32385);

        // ========================================================
        // TEST 12: Reset has highest priority
        //
        // Assert rst, clear_acc, enable together.
        // accumulator must become 0.
        // ========================================================
        $display("");
        $display("---- TEST 12: Reset Priority ----");

        @(negedge clk);
        rst        = 1'b1;
        clear_acc  = 1'b1;
        enable     = 1'b1;
        activation = 8'sd20;
        weight     = 8'sd20;

        @(posedge clk);
        #1;

        check32s("Reset priority",
                 accumulator,
                 32'sd0);

        @(negedge clk);
        rst        = 1'b0;
        clear_acc  = 1'b0;
        enable     = 1'b0;

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

        $display(" VCD: tb_pe.vcd");
        $display("==============================================");
        $display("");

        repeat (3) @(posedge clk);
        $finish;
    end

endmodule
