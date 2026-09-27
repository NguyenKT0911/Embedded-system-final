`timescale 1ns/1ps

module tb_conv_address_generator_4x4;

    // ============================================================
    // Address Widths
    // ============================================================
    localparam integer INPUT_ADDR_WIDTH  = 12;
    localparam integer WEIGHT_ADDR_WIDTH = 13;

    // ============================================================
    // DUT Inputs
    // ============================================================
    reg [15:0] input_h;
    reg [15:0] input_w;
    reg [15:0] cin;
    reg [15:0] cout;

    reg [7:0] kernel_size;
    reg [7:0] stride;
    reg [7:0] padding;

    reg [15:0] oh;
    reg [15:0] ow_base;
    reg [15:0] oc_base;

    reg [15:0] ic;
    reg [7:0]  kh;
    reg [7:0]  kw;

    reg [15:0] out_h;
    reg [15:0] out_w;

    // ============================================================
    // DUT Outputs
    // ============================================================
    wire [INPUT_ADDR_WIDTH-1:0] input_addr_0;
    wire [INPUT_ADDR_WIDTH-1:0] input_addr_1;
    wire [INPUT_ADDR_WIDTH-1:0] input_addr_2;
    wire [INPUT_ADDR_WIDTH-1:0] input_addr_3;

    wire [3:0] input_valid_mask;

    wire [WEIGHT_ADDR_WIDTH-1:0] weight_addr_0;
    wire [WEIGHT_ADDR_WIDTH-1:0] weight_addr_1;
    wire [WEIGHT_ADDR_WIDTH-1:0] weight_addr_2;
    wire [WEIGHT_ADDR_WIDTH-1:0] weight_addr_3;

    wire [3:0] weight_valid_mask;

    // ============================================================
    // Test Counters
    // ============================================================
    integer pass_count;
    integer fail_count;

    // ============================================================
    // DUT
    // ============================================================
    conv_address_generator_4x4 #(
        .INPUT_ADDR_WIDTH(INPUT_ADDR_WIDTH),
        .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
    ) dut (
        .input_h(input_h),
        .input_w(input_w),
        .cin(cin),
        .cout(cout),

        .kernel_size(kernel_size),
        .stride(stride),
        .padding(padding),

        .oh(oh),
        .ow_base(ow_base),
        .oc_base(oc_base),

        .ic(ic),
        .kh(kh),
        .kw(kw),

        .out_h(out_h),
        .out_w(out_w),

        .input_addr_0(input_addr_0),
        .input_addr_1(input_addr_1),
        .input_addr_2(input_addr_2),
        .input_addr_3(input_addr_3),

        .input_valid_mask(input_valid_mask),

        .weight_addr_0(weight_addr_0),
        .weight_addr_1(weight_addr_1),
        .weight_addr_2(weight_addr_2),
        .weight_addr_3(weight_addr_3),

        .weight_valid_mask(weight_valid_mask)
    );

    // ============================================================
    // Waveform Dump
    // ============================================================
    initial begin
        $dumpfile("tb_conv_address_generator_4x4.vcd");
        $dumpvars(0, tb_conv_address_generator_4x4);
    end

    // ============================================================
    // Helpers
    // ============================================================
    task check_input_addr;
        input [8*64-1:0] name;
        input [INPUT_ADDR_WIDTH-1:0] got;
        input [INPUT_ADDR_WIDTH-1:0] expected;
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

    task check_weight_addr;
        input [8*64-1:0] name;
        input [WEIGHT_ADDR_WIDTH-1:0] got;
        input [WEIGHT_ADDR_WIDTH-1:0] expected;
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

    task check_mask;
        input [8*64-1:0] name;
        input [3:0] got;
        input [3:0] expected;
        begin
            if (got === expected) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s | got=%b", name, got);
            end
            else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s | got=%b expected=%b",
                         name, got, expected);
            end
        end
    endtask

    // ============================================================
    // Conv1 Config Helper
    //
    // Input  : 1x28x28
    // Output : 16x28x28
    // K=3, S=1, P=1
    // ============================================================
    task set_conv1;
        begin
            input_h     = 16'd28;
            input_w     = 16'd28;
            cin         = 16'd1;
            cout        = 16'd16;

            kernel_size = 8'd3;
            stride      = 8'd1;
            padding     = 8'd1;

            out_h       = 16'd28;
            out_w       = 16'd28;
        end
    endtask

    // ============================================================
    // Conv2 Config Helper
    //
    // Input  : 16x14x14
    // Output : 32x14x14
    // K=3, S=1, P=1
    // ============================================================
    task set_conv2;
        begin
            input_h     = 16'd14;
            input_w     = 16'd14;
            cin         = 16'd16;
            cout        = 16'd32;

            kernel_size = 8'd3;
            stride      = 8'd1;
            padding     = 8'd1;

            out_h       = 16'd14;
            out_w       = 16'd14;
        end
    endtask

    // ============================================================
    // Main Test Sequence
    // ============================================================
    initial begin

        pass_count = 0;
        fail_count = 0;

        input_h     = 0;
        input_w     = 0;
        cin         = 0;
        cout        = 0;

        kernel_size = 0;
        stride      = 0;
        padding     = 0;

        oh          = 0;
        ow_base     = 0;
        oc_base     = 0;

        ic          = 0;
        kh          = 0;
        kw          = 0;

        out_h       = 0;
        out_w       = 0;

        #1;

        $display("");
        $display("==================================================");
        $display(" Conv Address Generator 4x4 Testbench");
        $display("==================================================");
        $display("");

        // ========================================================
        // TEST 1: Conv1 center position, first kernel element
        //
        // oh=5, ow_base=6, ic=0, kh=1, kw=1
        // in_row = 5
        // in_col lanes = 6,7,8,9
        //
        // CHW flatten for Cin=1:
        // addr = row*28 + col
        //      = 146,147,148,149
        //
        // oc_base=0 and kernel_index=4
        // weight stride per OC = 1*3*3 = 9
        // weight addresses = 4,13,22,31
        // ========================================================
        $display("---- TEST 1: Conv1 Center ----");

        set_conv1();

        oh      = 16'd5;
        ow_base = 16'd6;
        oc_base = 16'd0;

        ic = 16'd0;
        kh = 8'd1;
        kw = 8'd1;

        #1;

        check_mask("Conv1 center input mask", input_valid_mask, 4'b1111);
        check_mask("Conv1 center weight mask", weight_valid_mask, 4'b1111);

        check_input_addr("Conv1 input addr 0", input_addr_0, 12'd146);
        check_input_addr("Conv1 input addr 1", input_addr_1, 12'd147);
        check_input_addr("Conv1 input addr 2", input_addr_2, 12'd148);
        check_input_addr("Conv1 input addr 3", input_addr_3, 12'd149);

        check_weight_addr("Conv1 weight addr 0", weight_addr_0, 13'd4);
        check_weight_addr("Conv1 weight addr 1", weight_addr_1, 13'd13);
        check_weight_addr("Conv1 weight addr 2", weight_addr_2, 13'd22);
        check_weight_addr("Conv1 weight addr 3", weight_addr_3, 13'd31);

        // ========================================================
        // TEST 2: Conv1 top-left padding
        //
        // oh=0, ow_base=0, kh=0, kw=0
        // in_row = -1 for all four lanes -> all input lanes invalid.
        //
        // Weight addresses are still valid.
        // kernel_index = 0
        // addresses = 0,9,18,27
        // ========================================================
        $display("");
        $display("---- TEST 2: Top-Left Padding ----");

        set_conv1();

        oh      = 16'd0;
        ow_base = 16'd0;
        oc_base = 16'd0;

        ic = 16'd0;
        kh = 8'd0;
        kw = 8'd0;

        #1;

        check_mask("Top-left padding input mask",
                   input_valid_mask, 4'b0000);

        check_mask("Top-left padding weight mask",
                   weight_valid_mask, 4'b1111);

        check_weight_addr("Padding weight addr 0", weight_addr_0, 13'd0);
        check_weight_addr("Padding weight addr 1", weight_addr_1, 13'd9);
        check_weight_addr("Padding weight addr 2", weight_addr_2, 13'd18);
        check_weight_addr("Padding weight addr 3", weight_addr_3, 13'd27);

        // ========================================================
        // TEST 3: Conv1 left edge with partial padding
        //
        // oh=1, ow_base=0, kh=1, kw=0
        //
        // in_row = 1
        // in_col = -1,0,1,2
        //
        // lane 0 invalid
        // lanes 1..3 valid
        //
        // addresses:
        // lane1 = 1*28+0 = 28
        // lane2 = 29
        // lane3 = 30
        // ========================================================
        $display("");
        $display("---- TEST 3: Left Edge Partial Padding ----");

        set_conv1();

        oh      = 16'd1;
        ow_base = 16'd0;
        oc_base = 16'd4;

        ic = 16'd0;
        kh = 8'd1;
        kw = 8'd0;

        #1;

        check_mask("Left edge input mask",
                   input_valid_mask, 4'b1110);

        check_input_addr("Left edge lane1", input_addr_1, 12'd28);
        check_input_addr("Left edge lane2", input_addr_2, 12'd29);
        check_input_addr("Left edge lane3", input_addr_3, 12'd30);

        // kernel_index = 3
        // oc 4..7 => 4*9+3, 5*9+3, ...
        check_weight_addr("Left edge weight 0", weight_addr_0, 13'd39);
        check_weight_addr("Left edge weight 1", weight_addr_1, 13'd48);
        check_weight_addr("Left edge weight 2", weight_addr_2, 13'd57);
        check_weight_addr("Left edge weight 3", weight_addr_3, 13'd66);

        // ========================================================
        // TEST 4: Conv1 right-edge output lanes
        //
        // out_w=28, ow_base=26 -> lanes 0,1 valid output positions;
        // lanes 2,3 exceed output width.
        //
        // Choose kh=1, kw=1 so input coordinate equals output coord.
        // ========================================================
        $display("");
        $display("---- TEST 4: Right Edge Output Mask ----");

        set_conv1();

        oh      = 16'd10;
        ow_base = 16'd26;
        oc_base = 16'd12;

        ic = 16'd0;
        kh = 8'd1;
        kw = 8'd1;

        #1;

        check_mask("Right edge input mask",
                   input_valid_mask, 4'b0011);

        check_input_addr("Right edge lane0",
                         input_addr_0,
                         12'd306); // 10*28+26

        check_input_addr("Right edge lane1",
                         input_addr_1,
                         12'd307); // 10*28+27

        // All 4 output channels 12..15 still valid.
        check_mask("Right edge weight mask",
                   weight_valid_mask, 4'b1111);

        // ========================================================
        // TEST 5: Output-channel tail mask
        //
        // Conv1 cout=16, oc_base=14
        // valid channels = 14,15
        // invalid = 16,17
        // ========================================================
        $display("");
        $display("---- TEST 5: Output Channel Tail ----");

        set_conv1();

        oh      = 16'd8;
        ow_base = 16'd8;
        oc_base = 16'd14;

        ic = 16'd0;
        kh = 8'd2;
        kw = 8'd2;

        #1;

        check_mask("Output-channel tail weight mask",
                   weight_valid_mask, 4'b0011);

        // kernel_index = 8
        // oc14 -> 14*9+8 = 134
        // oc15 -> 15*9+8 = 143
        check_weight_addr("OC tail weight lane0",
                          weight_addr_0, 13'd134);

        check_weight_addr("OC tail weight lane1",
                          weight_addr_1, 13'd143);

        // ========================================================
        // TEST 6: Conv2 address generation
        //
        // Input layout [C][H][W], H=W=14.
        //
        // ic=3, oh=4, ow_base=5, kh=2, kw=1:
        // in_row = 4+2-1 = 5
        // in_col = 5,6,7,8
        //
        // channel base = 3*14*14 = 588
        // row base = 5*14 = 70
        // addresses = 663,664,665,666
        //
        // kernel_index = 3*9 + 2*3 + 1 = 34
        //
        // oc_base=8
        // per-OC weight block = 16*9 = 144
        //
        // addresses:
        // 8*144 + 34  = 1186
        // 9*144 + 34  = 1330
        // 10*144 + 34 = 1474
        // 11*144 + 34 = 1618
        // ========================================================
        $display("");
        $display("---- TEST 6: Conv2 Address Generation ----");

        set_conv2();

        oh      = 16'd4;
        ow_base = 16'd5;
        oc_base = 16'd8;

        ic = 16'd3;
        kh = 8'd2;
        kw = 8'd1;

        #1;

        check_mask("Conv2 input mask",
                   input_valid_mask, 4'b1111);

        check_mask("Conv2 weight mask",
                   weight_valid_mask, 4'b1111);

        check_input_addr("Conv2 input addr 0",
                         input_addr_0, 12'd663);

        check_input_addr("Conv2 input addr 1",
                         input_addr_1, 12'd664);

        check_input_addr("Conv2 input addr 2",
                         input_addr_2, 12'd665);

        check_input_addr("Conv2 input addr 3",
                         input_addr_3, 12'd666);

        check_weight_addr("Conv2 weight addr 0",
                          weight_addr_0, 13'd1186);

        check_weight_addr("Conv2 weight addr 1",
                          weight_addr_1, 13'd1330);

        check_weight_addr("Conv2 weight addr 2",
                          weight_addr_2, 13'd1474);

        check_weight_addr("Conv2 weight addr 3",
                          weight_addr_3, 13'd1618);

        // ========================================================
        // TEST 7: Invalid input channel
        // ic == cin must invalidate both input and weight lanes.
        // ========================================================
        $display("");
        $display("---- TEST 7: Invalid Input Channel ----");

        set_conv2();

        oh      = 16'd2;
        ow_base = 16'd2;
        oc_base = 16'd0;

        ic = 16'd16; // invalid because cin = 16
        kh = 8'd1;
        kw = 8'd1;

        #1;

        check_mask("Invalid ic input mask",
                   input_valid_mask, 4'b0000);

        check_mask("Invalid ic weight mask",
                   weight_valid_mask, 4'b0000);

        // ========================================================
        // TEST 8: Invalid kernel coordinate
        // kh == K must invalidate all lanes.
        // ========================================================
        $display("");
        $display("---- TEST 8: Invalid Kernel Coordinate ----");

        set_conv1();

        oh      = 16'd3;
        ow_base = 16'd3;
        oc_base = 16'd0;

        ic = 16'd0;
        kh = 8'd3; // invalid for K=3
        kw = 8'd1;

        #1;

        check_mask("Invalid kh input mask",
                   input_valid_mask, 4'b0000);

        check_mask("Invalid kh weight mask",
                   weight_valid_mask, 4'b0000);

        // ========================================================
        // TEST 9: Bottom padding
        //
        // Conv1 oh=27, kh=2, P=1
        // in_row = 28 -> outside image
        // ========================================================
        $display("");
        $display("---- TEST 9: Bottom Padding ----");

        set_conv1();

        oh      = 16'd27;
        ow_base = 16'd5;
        oc_base = 16'd0;

        ic = 16'd0;
        kh = 8'd2;
        kw = 8'd1;

        #1;

        check_mask("Bottom padding input mask",
                   input_valid_mask, 4'b0000);

        check_mask("Bottom padding weight mask",
                   weight_valid_mask, 4'b1111);

        // ========================================================
        // TEST 10: Conv2 maximum valid weight address
        //
        // oc=31, ic=15, kh=2, kw=2
        //
        // flatten:
        // ((31*16 + 15)*3 + 2)*3 + 2
        // = 4607
        //
        // Use oc_base=28 -> lanes 28..31.
        // lane3 must equal 4607.
        // ========================================================
        $display("");
        $display("---- TEST 10: Conv2 Max Weight Address ----");

        set_conv2();

        oh      = 16'd6;
        ow_base = 16'd6;
        oc_base = 16'd28;

        ic = 16'd15;
        kh = 8'd2;
        kw = 8'd2;

        #1;

        check_mask("Conv2 max weight mask",
                   weight_valid_mask, 4'b1111);

        check_weight_addr("Conv2 final weight address",
                          weight_addr_3, 13'd4607);

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

        $display(" VCD: tb_conv_address_generator_4x4.vcd");
        $display("==================================================");
        $display("");

        #10;
        $finish;
    end

endmodule
