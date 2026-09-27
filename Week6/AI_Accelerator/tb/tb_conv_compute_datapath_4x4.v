`timescale 1ns/1ps

module tb_conv_compute_datapath_4x4;

    // ============================================================
    // Small buffers are enough for a 4x4 test image and 4 filters.
    // ============================================================
    localparam integer INPUT_MAX_VALUES  = 32;
    localparam integer WEIGHT_MAX_VALUES = 64;

    localparam integer INPUT_ADDR_WIDTH  = 5;
    localparam integer WEIGHT_ADDR_WIDTH = 6;

    // ============================================================
    // Clock / Reset
    // ============================================================
    reg clk;
    reg rst;

    // ============================================================
    // Buffer Write Interfaces
    // ============================================================
    reg        buffer_clear;

    reg [31:0] input_write_data;
    reg        input_write_valid;

    reg [31:0] weight_write_data;
    reg        weight_write_valid;

    // ============================================================
    // Datapath Control
    // ============================================================
    reg feeder_clear;
    reg clear_acc;
    reg start_step;

    // ============================================================
    // Convolution Configuration
    // ============================================================
    reg [15:0] input_h;
    reg [15:0] input_w;
    reg [15:0] cin;
    reg [15:0] cout;

    reg [7:0] kernel_size;
    reg [7:0] stride;
    reg [7:0] padding;

    reg [15:0] out_h;
    reg [15:0] out_w;

    // ============================================================
    // Current Convolution Indices
    // ============================================================
    reg [15:0] oh;
    reg [15:0] ow_base;
    reg [15:0] oc_base;

    reg [15:0] ic;
    reg [7:0]  kh;
    reg [7:0]  kw;

    // ============================================================
    // Buffer <-> Datapath Read Interfaces
    // ============================================================
    wire                         input_read_en;
    wire [INPUT_ADDR_WIDTH-1:0]  input_read_addr;
    wire signed [7:0]            input_read_data;

    wire                         weight_read_en;
    wire [WEIGHT_ADDR_WIDTH-1:0] weight_read_addr;
    wire signed [7:0]            weight_read_data;

    // ============================================================
    // Buffer Status
    // ============================================================
    wire [31:0] input_stored_count;
    wire        input_full;
    wire        input_overflow_error;

    wire [31:0] weight_stored_count;
    wire        weight_full;
    wire        weight_overflow_error;

    // ============================================================
    // Datapath Outputs
    // ============================================================
    wire        busy;
    wire        step_done;

    wire [3:0]  input_valid_mask;
    wire [3:0]  weight_valid_mask;

    wire [31:0] activation_bus;
    wire [31:0] weight_bus;

    wire [511:0] accumulator_bus;

    // ============================================================
    // Convenient PE Views
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
    // Test Counters
    // ============================================================
    integer pass_count;
    integer fail_count;
    integer timeout_count;

    integer r;
    integer c;

    // ============================================================
    // Input Buffer
    // ============================================================
    input_buffer #(
        .MAX_VALUES(INPUT_MAX_VALUES),
        .ADDR_WIDTH(INPUT_ADDR_WIDTH)
    ) u_input_buffer (
        .clk(clk),
        .rst(rst),
        .clear(buffer_clear),

        .write_data(input_write_data),
        .write_valid(input_write_valid),

        .read_en(input_read_en),
        .read_addr(input_read_addr),
        .read_data(input_read_data),

        .stored_count(input_stored_count),
        .full(input_full),
        .overflow_error(input_overflow_error)
    );

    // ============================================================
    // Weight Buffer
    // ============================================================
    weight_buffer #(
        .MAX_VALUES(WEIGHT_MAX_VALUES),
        .ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
    ) u_weight_buffer (
        .clk(clk),
        .rst(rst),
        .clear(buffer_clear),

        .write_data(weight_write_data),
        .write_valid(weight_write_valid),

        .read_en(weight_read_en),
        .read_addr(weight_read_addr),
        .read_data(weight_read_data),

        .stored_count(weight_stored_count),
        .full(weight_full),
        .overflow_error(weight_overflow_error)
    );

    // ============================================================
    // Convolution Compute Datapath
    // ============================================================
    conv_compute_datapath_4x4 #(
        .INPUT_ADDR_WIDTH(INPUT_ADDR_WIDTH),
        .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),

        .feeder_clear(feeder_clear),
        .clear_acc(clear_acc),
        .start_step(start_step),

        .busy(busy),
        .step_done(step_done),

        .input_h(input_h),
        .input_w(input_w),
        .cin(cin),
        .cout(cout),

        .kernel_size(kernel_size),
        .stride(stride),
        .padding(padding),

        .out_h(out_h),
        .out_w(out_w),

        .oh(oh),
        .ow_base(ow_base),
        .oc_base(oc_base),

        .ic(ic),
        .kh(kh),
        .kw(kw),

        .input_read_en(input_read_en),
        .input_read_addr(input_read_addr),
        .input_read_data(input_read_data),

        .weight_read_en(weight_read_en),
        .weight_read_addr(weight_read_addr),
        .weight_read_data(weight_read_data),

        .input_valid_mask(input_valid_mask),
        .weight_valid_mask(weight_valid_mask),

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
        $dumpfile("tb_conv_compute_datapath_4x4.vcd");
        $dumpvars(0, tb_conv_compute_datapath_4x4);
    end

    // ============================================================
    // Write Helpers
    // ============================================================
    task write_input_word;
        input [31:0] data;
        begin
            @(negedge clk);
            input_write_data  = data;
            input_write_valid = 1'b1;

            @(posedge clk);
            #1;

            @(negedge clk);
            input_write_valid = 1'b0;
            input_write_data  = 32'd0;
        end
    endtask

    task write_weight_word;
        input [31:0] data;
        begin
            @(negedge clk);
            weight_write_data  = data;
            weight_write_valid = 1'b1;

            @(posedge clk);
            #1;

            @(negedge clk);
            weight_write_valid = 1'b0;
            weight_write_data  = 32'd0;
        end
    endtask

    // ============================================================
    // Control Helpers
    // ============================================================
    task pulse_start_step;
        begin
            @(negedge clk);
            start_step = 1'b1;

            @(posedge clk);
            #1;

            @(negedge clk);
            start_step = 1'b0;
        end
    endtask

    task wait_for_step_done;
        begin
            timeout_count = 0;

            while ((step_done !== 1'b1) && (timeout_count < 20)) begin
                @(posedge clk);
                #1;
                timeout_count = timeout_count + 1;
            end

            if (step_done !== 1'b1) begin
                fail_count = fail_count + 1;
                $display("[FAIL] Timeout waiting for step_done");
            end
        end
    endtask

    // step_done becomes high when the feeder bundle is complete.
    // PE Array consumes that enable pulse on the following posedge.
    task wait_for_pe_accumulate;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task run_conv_step;
        input [7:0] kh_value;
        input [7:0] kw_value;
        begin
            kh = kh_value;
            kw = kw_value;

            #1; // let combinational address generation settle

            pulse_start_step();
            wait_for_step_done();
            wait_for_pe_accumulate();
        end
    endtask

    task clear_accumulators;
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
    // Check Helpers
    // ============================================================
    task check1;
        input [8*80-1:0] name;
        input got;
        input expected;
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

    task check4;
        input [8*80-1:0] name;
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

    task check32;
        input [8*80-1:0] name;
        input [31:0] got;
        input [31:0] expected;
        begin
            if (got === expected) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s | got=0x%08h", name, got);
            end
            else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s | got=0x%08h expected=0x%08h",
                         name, got, expected);
            end
        end
    endtask

    task check32s;
        input [8*80-1:0] name;
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
    // Main Test Sequence
    // ============================================================
    initial begin

        pass_count = 0;
        fail_count = 0;

        rst          = 1'b1;
        buffer_clear = 1'b0;
        feeder_clear = 1'b0;
        clear_acc    = 1'b0;
        start_step   = 1'b0;

        input_write_data  = 32'd0;
        input_write_valid = 1'b0;

        weight_write_data  = 32'd0;
        weight_write_valid = 1'b0;

        // 4x4 input, 1 input channel, 4 output channels
        input_h     = 16'd4;
        input_w     = 16'd4;
        cin         = 16'd1;
        cout        = 16'd4;

        kernel_size = 8'd3;
        stride      = 8'd1;
        padding     = 8'd1;

        out_h       = 16'd4;
        out_w       = 16'd4;

        oh          = 16'd1;
        ow_base     = 16'd0;
        oc_base     = 16'd0;
        ic          = 16'd0;
        kh          = 8'd0;
        kw          = 8'd0;

        repeat (3) @(posedge clk);
        #1;

        $display("");
        $display("==================================================");
        $display(" Conv Compute Datapath 4x4 Integration Testbench");
        $display("==================================================");
        $display("");

        // ========================================================
        // TEST 1: Reset
        // ========================================================
        $display("---- TEST 1: Reset ----");

        check1("busy after reset", busy, 1'b0);
        check1("step_done after reset", step_done, 1'b0);

        check32s("PE00 reset", acc_00, 32'sd0);
        check32s("PE11 reset", acc_11, 32'sd0);
        check32s("PE22 reset", acc_22, 32'sd0);
        check32s("PE33 reset", acc_33, 32'sd0);

        @(negedge clk);
        rst = 1'b0;

        // ========================================================
        // TEST 2: Load 4x4 Input
        //
        // Input image:
        //
        //   1   2   3   4
        //   5   6   7   8
        //   9  10  11  12
        //  13  14  15  16
        //
        // Flattened [C][H][W].
        // ========================================================
        $display("");
        $display("---- TEST 2: Load Input / Weights ----");

        write_input_word(32'h0403_0201);
        write_input_word(32'h0807_0605);
        write_input_word(32'h0C0B_0A09);
        write_input_word(32'h100F_0E0D);

        // --------------------------------------------------------
        // Four 3x3 filters.
        //
        // OC0: every weight = 1
        // OC1: every weight = 2
        // OC2: every weight = 3
        // OC3: every weight = 4
        //
        // Layout: [COUT][CIN][KH][KW]
        // Total = 4 * 1 * 3 * 3 = 36 weights.
        // --------------------------------------------------------
        write_weight_word(32'h0101_0101); // indices  0..3
        write_weight_word(32'h0101_0101); // indices  4..7
        write_weight_word(32'h0202_0201); // indices  8..11
        write_weight_word(32'h0202_0202); // indices 12..15
        write_weight_word(32'h0303_0202); // indices 16..19
        write_weight_word(32'h0303_0303); // indices 20..23
        write_weight_word(32'h0403_0303); // indices 24..27
        write_weight_word(32'h0404_0404); // indices 28..31
        write_weight_word(32'h0404_0404); // indices 32..35

        check32("input_stored_count",
                input_stored_count, 32'd16);

        check32("weight_stored_count",
                weight_stored_count, 32'd36);

        // ========================================================
        // TEST 3: First Convolution Step with Left Padding
        //
        // Tile:
        //   oh=1
        //   ow=0,1,2,3
        //   oc=0,1,2,3
        //
        // First kernel position: kh=0, kw=0
        //
        // input coordinates:
        //   row = 0
        //   col = -1,0,1,2
        //
        // activation lanes = [0,1,2,3]
        // weights          = [1,2,3,4]
        //
        // Expected first accumulation:
        //
        // row0 = [0,0,0,0]
        // row1 = [1,2,3,4]
        // row2 = [2,4,6,8]
        // row3 = [3,6,9,12]
        // ========================================================
        $display("");
        $display("---- TEST 3: First Step / Padding ----");

        kh = 8'd0;
        kw = 8'd0;

        #1;

        check4("input mask for padded step",
               input_valid_mask, 4'b1110);

        check4("weight mask for first step",
               weight_valid_mask, 4'b1111);

        pulse_start_step();

        check1("busy after first START",
               busy, 1'b1);

        wait_for_step_done();

        check32("activation bus with zero padding",
                activation_bus, 32'h0302_0100);

        check32("weight bus first step",
                weight_bus, 32'h0403_0201);

        wait_for_pe_accumulate();

        check32s("first step PE00", acc_00, 32'sd0);
        check32s("first step PE03", acc_03, 32'sd0);

        check32s("first step PE10", acc_10, 32'sd1);
        check32s("first step PE13", acc_13, 32'sd4);

        check32s("first step PE20", acc_20, 32'sd2);
        check32s("first step PE23", acc_23, 32'sd8);

        check32s("first step PE30", acc_30, 32'sd3);
        check32s("first step PE33", acc_33, 32'sd12);

        // ========================================================
        // TEST 4: Complete Full 3x3 Convolution Tile
        //
        // We already completed kh=0,kw=0.
        // Run the remaining 8 kernel positions.
        //
        // Neighborhood sums at oh=1:
        //
        // ow0 = 33
        // ow1 = 54
        // ow2 = 63
        // ow3 = 45
        //
        // Since filters contain constants [1,2,3,4], final tile:
        //
        // row0 = [ 33,  66,  99, 132]
        // row1 = [ 54, 108, 162, 216]
        // row2 = [ 63, 126, 189, 252]
        // row3 = [ 45,  90, 135, 180]
        // ========================================================
        $display("");
        $display("---- TEST 4: Full 3x3 Convolution Tile ----");

        for (r = 0; r < 3; r = r + 1) begin
            for (c = 0; c < 3; c = c + 1) begin

                if (!((r == 0) && (c == 0))) begin
                    run_conv_step(r[7:0], c[7:0]);
                end

            end
        end

        check32s("final PE00", acc_00, 32'sd33);
        check32s("final PE01", acc_01, 32'sd66);
        check32s("final PE02", acc_02, 32'sd99);
        check32s("final PE03", acc_03, 32'sd132);

        check32s("final PE10", acc_10, 32'sd54);
        check32s("final PE11", acc_11, 32'sd108);
        check32s("final PE12", acc_12, 32'sd162);
        check32s("final PE13", acc_13, 32'sd216);

        check32s("final PE20", acc_20, 32'sd63);
        check32s("final PE21", acc_21, 32'sd126);
        check32s("final PE22", acc_22, 32'sd189);
        check32s("final PE23", acc_23, 32'sd252);

        check32s("final PE30", acc_30, 32'sd45);
        check32s("final PE31", acc_31, 32'sd90);
        check32s("final PE32", acc_32, 32'sd135);
        check32s("final PE33", acc_33, 32'sd180);

        // ========================================================
        // TEST 5: Clear Accumulators
        // ========================================================
        $display("");
        $display("---- TEST 5: Clear Accumulators ----");

        clear_accumulators();

        check32s("PE00 after clear", acc_00, 32'sd0);
        check32s("PE11 after clear", acc_11, 32'sd0);
        check32s("PE22 after clear", acc_22, 32'sd0);
        check32s("PE33 after clear", acc_33, 32'sd0);

        // ========================================================
        // TEST 6: Output-Channel Tail Mask
        //
        // Temporarily set cout=3.
        // Lane 3 (OC3) must become invalid and therefore weight=0.
        //
        // Use center kernel position kh=1, kw=1:
        // activation lanes = [5,6,7,8]
        // valid weights    = [1,2,3,0]
        // ========================================================
        $display("");
        $display("---- TEST 6: Output Channel Tail Mask ----");

        cout = 16'd3;

        kh = 8'd1;
        kw = 8'd1;

        #1;

        check4("weight tail mask",
               weight_valid_mask, 4'b0111);

        pulse_start_step();
        wait_for_step_done();

        check32("activation bus center",
                activation_bus, 32'h0807_0605);

        check32("weight bus with OC tail zero",
                weight_bus, 32'h0003_0201);

        wait_for_pe_accumulate();

        check32s("tail PE00", acc_00, 32'sd5);
        check32s("tail PE01", acc_01, 32'sd10);
        check32s("tail PE02", acc_02, 32'sd15);
        check32s("tail PE03 invalid lane", acc_03, 32'sd0);

        check32s("tail PE30", acc_30, 32'sd8);
        check32s("tail PE31", acc_31, 32'sd16);
        check32s("tail PE32", acc_32, 32'sd24);
        check32s("tail PE33 invalid lane", acc_33, 32'sd0);

        // Restore normal COUT.
        cout = 16'd4;

        // ========================================================
        // TEST 7: Feeder Clear Independence
        // feeder_clear must not clear PE accumulators.
        // ========================================================
        $display("");
        $display("---- TEST 7: Feeder Clear Independence ----");

        @(negedge clk);
        feeder_clear = 1'b1;

        @(posedge clk);
        #1;

        @(negedge clk);
        feeder_clear = 1'b0;

        check32s("PE00 preserved after feeder clear",
                 acc_00, 32'sd5);

        check32s("PE33 preserved after feeder clear",
                 acc_33, 32'sd0);

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

        $display(" VCD: tb_conv_compute_datapath_4x4.vcd");
        $display("==================================================");
        $display("");

        repeat (3) @(posedge clk);
        $finish;
    end

endmodule
