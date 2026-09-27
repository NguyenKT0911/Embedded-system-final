`timescale 1ns/1ps

module tb_pe_array_4x4;

    // ============================================================
    // DUT Inputs
    // ============================================================
    reg clk;
    reg rst;

    reg clear_acc;
    reg enable;

    reg [31:0] activation_bus;
    reg [31:0] weight_bus;

    // ============================================================
    // DUT Output
    // ============================================================
    wire [511:0] accumulator_bus;

    // ============================================================
    // Test Counters
    // ============================================================
    integer pass_count;
    integer fail_count;

    // ============================================================
    // Convenient PE Output Views
    // ============================================================
    wire signed [31:0] acc_00 = accumulator_bus[31:0];
    wire signed [31:0] acc_01 = accumulator_bus[63:32];
    wire signed [31:0] acc_02 = accumulator_bus[95:64];
    wire signed [31:0] acc_03 = accumulator_bus[127:96];

    wire signed [31:0] acc_10 = accumulator_bus[159:128];
    wire signed [31:0] acc_11 = accumulator_bus[191:160];
    wire signed [31:0] acc_12 = accumulator_bus[223:192];
    wire signed [31:0] acc_13 = accumulator_bus[255:224];

    wire signed [31:0] acc_20 = accumulator_bus[287:256];
    wire signed [31:0] acc_21 = accumulator_bus[319:288];
    wire signed [31:0] acc_22 = accumulator_bus[351:320];
    wire signed [31:0] acc_23 = accumulator_bus[383:352];

    wire signed [31:0] acc_30 = accumulator_bus[415:384];
    wire signed [31:0] acc_31 = accumulator_bus[447:416];
    wire signed [31:0] acc_32 = accumulator_bus[479:448];
    wire signed [31:0] acc_33 = accumulator_bus[511:480];

    // ============================================================
    // DUT
    // ============================================================
    pe_array_4x4 dut (
        .clk(clk),
        .rst(rst),

        .clear_acc(clear_acc),
        .enable(enable),

        .activation_bus(activation_bus),
        .weight_bus(weight_bus),

        .accumulator_bus(accumulator_bus)
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
        $dumpfile("tb_pe_array_4x4.vcd");
        $dumpvars(0, tb_pe_array_4x4);
    end

    // ============================================================
    // Helper: Check one signed INT32 PE output
    // ============================================================
    task check_pe;
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
    // Helper: Apply one compute cycle
    //
    // Input packing:
    //   activation_bus = {act3, act2, act1, act0}
    //   weight_bus     = {w3, w2, w1, w0}
    // ============================================================
    task array_cycle;
        input signed [7:0] act0;
        input signed [7:0] act1;
        input signed [7:0] act2;
        input signed [7:0] act3;

        input signed [7:0] w0;
        input signed [7:0] w1;
        input signed [7:0] w2;
        input signed [7:0] w3;

        begin
            @(negedge clk);

            activation_bus = {
                act3[7:0],
                act2[7:0],
                act1[7:0],
                act0[7:0]
            };

            weight_bus = {
                w3[7:0],
                w2[7:0],
                w1[7:0],
                w0[7:0]
            };

            enable = 1'b1;

            @(posedge clk);
            #1;

            @(negedge clk);
            enable = 1'b0;
        end
    endtask

    // ============================================================
    // Helper: Clear all 16 accumulators
    // ============================================================
    task clear_array;
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

        rst            = 1'b1;
        clear_acc      = 1'b0;
        enable         = 1'b0;
        activation_bus = 32'd0;
        weight_bus     = 32'd0;

        repeat (3) @(posedge clk);
        #1;

        $display("");
        $display("==============================================");
        $display(" PE Array 4x4 Testbench");
        $display("==============================================");
        $display("");

        // ========================================================
        // TEST 1: Reset
        // ========================================================
        $display("---- TEST 1: Reset ----");

        check_pe("PE00 reset", acc_00, 32'sd0);
        check_pe("PE11 reset", acc_11, 32'sd0);
        check_pe("PE22 reset", acc_22, 32'sd0);
        check_pe("PE33 reset", acc_33, 32'sd0);

        @(negedge clk);
        rst = 1'b0;

        // ========================================================
        // TEST 2: First outer-product cycle
        //
        // Activations = [1,2,3,4]
        // Weights     = [5,6,7,8]
        //
        // Expected:
        // row0 = [ 5,  6,  7,  8]
        // row1 = [10, 12, 14, 16]
        // row2 = [15, 18, 21, 24]
        // row3 = [20, 24, 28, 32]
        // ========================================================
        $display("");
        $display("---- TEST 2: First 4x4 Outer Product ----");

        array_cycle(
            8'sd1, 8'sd2, 8'sd3, 8'sd4,
            8'sd5, 8'sd6, 8'sd7, 8'sd8
        );

        check_pe("PE00", acc_00, 32'sd5);
        check_pe("PE01", acc_01, 32'sd6);
        check_pe("PE02", acc_02, 32'sd7);
        check_pe("PE03", acc_03, 32'sd8);

        check_pe("PE10", acc_10, 32'sd10);
        check_pe("PE11", acc_11, 32'sd12);
        check_pe("PE12", acc_12, 32'sd14);
        check_pe("PE13", acc_13, 32'sd16);

        check_pe("PE20", acc_20, 32'sd15);
        check_pe("PE21", acc_21, 32'sd18);
        check_pe("PE22", acc_22, 32'sd21);
        check_pe("PE23", acc_23, 32'sd24);

        check_pe("PE30", acc_30, 32'sd20);
        check_pe("PE31", acc_31, 32'sd24);
        check_pe("PE32", acc_32, 32'sd28);
        check_pe("PE33", acc_33, 32'sd32);

        // ========================================================
        // TEST 3: Second accumulation cycle
        //
        // Activations = [1,1,1,1]
        // Weights     = [1,2,3,4]
        //
        // Add:
        // each row += [1,2,3,4]
        // ========================================================
        $display("");
        $display("---- TEST 3: Accumulation Across Cycles ----");

        array_cycle(
            8'sd1, 8'sd1, 8'sd1, 8'sd1,
            8'sd1, 8'sd2, 8'sd3, 8'sd4
        );

        check_pe("PE00 accumulated", acc_00, 32'sd6);
        check_pe("PE03 accumulated", acc_03, 32'sd12);

        check_pe("PE10 accumulated", acc_10, 32'sd11);
        check_pe("PE13 accumulated", acc_13, 32'sd20);

        check_pe("PE20 accumulated", acc_20, 32'sd16);
        check_pe("PE23 accumulated", acc_23, 32'sd28);

        check_pe("PE30 accumulated", acc_30, 32'sd21);
        check_pe("PE33 accumulated", acc_33, 32'sd36);

        // ========================================================
        // TEST 4: Hold when enable = 0
        // ========================================================
        $display("");
        $display("---- TEST 4: Enable Hold ----");

        @(negedge clk);
        activation_bus = 32'h6464_6464; // 100,100,100,100
        weight_bus     = 32'h6464_6464; // 100,100,100,100
        enable         = 1'b0;

        repeat (2) @(posedge clk);
        #1;

        check_pe("PE00 hold", acc_00, 32'sd6);
        check_pe("PE11 hold", acc_11, 32'sd14);
        check_pe("PE22 hold", acc_22, 32'sd24);
        check_pe("PE33 hold", acc_33, 32'sd36);

        // ========================================================
        // TEST 5: Clear entire array
        // ========================================================
        $display("");
        $display("---- TEST 5: Clear Array ----");

        clear_array();

        check_pe("PE00 clear", acc_00, 32'sd0);
        check_pe("PE03 clear", acc_03, 32'sd0);
        check_pe("PE10 clear", acc_10, 32'sd0);
        check_pe("PE13 clear", acc_13, 32'sd0);
        check_pe("PE20 clear", acc_20, 32'sd0);
        check_pe("PE23 clear", acc_23, 32'sd0);
        check_pe("PE30 clear", acc_30, 32'sd0);
        check_pe("PE33 clear", acc_33, 32'sd0);

        // ========================================================
        // TEST 6: Signed values
        //
        // Activations = [-1, 2, -3, 4]
        // Weights     = [ 5,-6,  7,-8]
        //
        // Expected:
        //
        // row0 = [ -5,   6,  -7,   8]
        // row1 = [ 10, -12,  14, -16]
        // row2 = [-15,  18, -21,  24]
        // row3 = [ 20, -24,  28, -32]
        // ========================================================
        $display("");
        $display("---- TEST 6: Signed INT8 Values ----");

        array_cycle(
            -8'sd1,  8'sd2, -8'sd3,  8'sd4,
             8'sd5, -8'sd6,  8'sd7, -8'sd8
        );

        check_pe("signed PE00", acc_00, -32'sd5);
        check_pe("signed PE01", acc_01,  32'sd6);
        check_pe("signed PE02", acc_02, -32'sd7);
        check_pe("signed PE03", acc_03,  32'sd8);

        check_pe("signed PE10", acc_10,  32'sd10);
        check_pe("signed PE11", acc_11, -32'sd12);
        check_pe("signed PE12", acc_12,  32'sd14);
        check_pe("signed PE13", acc_13, -32'sd16);

        check_pe("signed PE20", acc_20, -32'sd15);
        check_pe("signed PE21", acc_21,  32'sd18);
        check_pe("signed PE22", acc_22, -32'sd21);
        check_pe("signed PE23", acc_23,  32'sd24);

        check_pe("signed PE30", acc_30,  32'sd20);
        check_pe("signed PE31", acc_31, -32'sd24);
        check_pe("signed PE32", acc_32,  32'sd28);
        check_pe("signed PE33", acc_33, -32'sd32);

        // ========================================================
        // TEST 7: Clear priority over enable
        // ========================================================
        $display("");
        $display("---- TEST 7: clear_acc Priority ----");

        @(negedge clk);

        activation_bus = {8'd4, 8'd3, 8'd2, 8'd1};
        weight_bus     = {8'd8, 8'd7, 8'd6, 8'd5};

        clear_acc = 1'b1;
        enable    = 1'b1;

        @(posedge clk);
        #1;

        check_pe("clear priority PE00", acc_00, 32'sd0);
        check_pe("clear priority PE11", acc_11, 32'sd0);
        check_pe("clear priority PE22", acc_22, 32'sd0);
        check_pe("clear priority PE33", acc_33, 32'sd0);

        @(negedge clk);
        clear_acc = 1'b0;
        enable    = 1'b0;

        // ========================================================
        // TEST 8: INT8 boundary values
        //
        // Activations = [127, -128, 127, -128]
        // Weights     = [127, -128, 1, -1]
        // ========================================================
        $display("");
        $display("---- TEST 8: INT8 Boundary Values ----");

        array_cycle(
             8'sd127, -8'sd128,  8'sd127, -8'sd128,
             8'sd127, -8'sd128,  8'sd1,   -8'sd1
        );

        // Row 0: 127 * [127,-128,1,-1]
        check_pe("boundary PE00", acc_00,  32'sd16129);
        check_pe("boundary PE01", acc_01, -32'sd16256);
        check_pe("boundary PE02", acc_02,  32'sd127);
        check_pe("boundary PE03", acc_03, -32'sd127);

        // Row 1: -128 * [127,-128,1,-1]
        check_pe("boundary PE10", acc_10, -32'sd16256);
        check_pe("boundary PE11", acc_11,  32'sd16384);
        check_pe("boundary PE12", acc_12, -32'sd128);
        check_pe("boundary PE13", acc_13,  32'sd128);

        // ========================================================
        // TEST 9: Reset priority
        // ========================================================
        $display("");
        $display("---- TEST 9: Reset Priority ----");

        @(negedge clk);

        rst       = 1'b1;
        clear_acc = 1'b1;
        enable    = 1'b1;

        activation_bus = 32'h0102_0304;
        weight_bus     = 32'h0506_0708;

        @(posedge clk);
        #1;

        check_pe("reset priority PE00", acc_00, 32'sd0);
        check_pe("reset priority PE11", acc_11, 32'sd0);
        check_pe("reset priority PE22", acc_22, 32'sd0);
        check_pe("reset priority PE33", acc_33, 32'sd0);

        @(negedge clk);

        rst       = 1'b0;
        clear_acc = 1'b0;
        enable    = 1'b0;

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

        $display(" VCD: tb_pe_array_4x4.vcd");
        $display("==============================================");
        $display("");

        repeat (3) @(posedge clk);
        $finish;
    end

endmodule
