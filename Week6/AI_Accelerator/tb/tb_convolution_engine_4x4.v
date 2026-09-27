`timescale 1ns/1ps

module tb_convolution_engine_4x4;

    // ============================================================
    // Small memories for a complete 4x4 convolution test
    // ============================================================
    localparam integer INPUT_MAX_VALUES  = 32;
    localparam integer WEIGHT_MAX_VALUES = 64;

    localparam integer INPUT_ADDR_WIDTH  = 5;
    localparam integer WEIGHT_ADDR_WIDTH = 6;

    // ============================================================
    // Clock / Reset / Clear
    // ============================================================
    reg clk;
    reg rst;
    reg clear;

    // ============================================================
    // Buffer Write Interfaces
    // ============================================================
    reg        buffer_clear;

    reg [31:0] input_write_data;
    reg        input_write_valid;

    reg [31:0] weight_write_data;
    reg        weight_write_valid;

    // ============================================================
    // Engine Control
    // ============================================================
    reg start;
    reg tile_accept;

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
    // Buffer <-> Engine Read Interfaces
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
    // Engine Outputs
    // ============================================================
    wire        tile_ready;

    wire [15:0] tile_oh;
    wire [15:0] tile_ow_base;
    wire [15:0] tile_oc_base;

    wire [511:0] accumulator_bus;

    wire busy;
    wire done;

    // Debug
    wire [15:0] dbg_ic;
    wire [7:0]  dbg_kh;
    wire [7:0]  dbg_kw;

    wire [3:0]  dbg_input_valid_mask;
    wire [3:0]  dbg_weight_valid_mask;

    wire [31:0] dbg_activation_bus;
    wire [31:0] dbg_weight_bus;

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
    // Convolution Engine
    // ============================================================
    convolution_engine_4x4 #(
        .INPUT_ADDR_WIDTH(INPUT_ADDR_WIDTH),
        .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .clear(clear),

        .start(start),

        .input_h(input_h),
        .input_w(input_w),
        .cin(cin),
        .cout(cout),

        .kernel_size(kernel_size),
        .stride(stride),
        .padding(padding),

        .out_h(out_h),
        .out_w(out_w),

        .input_read_en(input_read_en),
        .input_read_addr(input_read_addr),
        .input_read_data(input_read_data),

        .weight_read_en(weight_read_en),
        .weight_read_addr(weight_read_addr),
        .weight_read_data(weight_read_data),

        .tile_ready(tile_ready),
        .tile_accept(tile_accept),

        .tile_oh(tile_oh),
        .tile_ow_base(tile_ow_base),
        .tile_oc_base(tile_oc_base),

        .accumulator_bus(accumulator_bus),

        .busy(busy),
        .done(done),

        .dbg_ic(dbg_ic),
        .dbg_kh(dbg_kh),
        .dbg_kw(dbg_kw),

        .dbg_input_valid_mask(dbg_input_valid_mask),
        .dbg_weight_valid_mask(dbg_weight_valid_mask),

        .dbg_activation_bus(dbg_activation_bus),
        .dbg_weight_bus(dbg_weight_bus)
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
        $dumpfile("tb_convolution_engine_4x4.vcd");
        $dumpvars(0, tb_convolution_engine_4x4);
    end

    // ============================================================
    // Buffer Write Helpers
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
    // Engine Control Helpers
    // ============================================================
    task pulse_start;
        begin
            @(negedge clk);
            start = 1'b1;

            @(posedge clk);
            #1;

            @(negedge clk);
            start = 1'b0;
        end
    endtask

    task pulse_tile_accept;
        begin
            @(negedge clk);
            tile_accept = 1'b1;

            @(posedge clk);
            #1;

            @(negedge clk);
            tile_accept = 1'b0;
        end
    endtask

    task wait_for_tile_ready;
        begin
            timeout_count = 0;

            while ((tile_ready !== 1'b1) && (timeout_count < 200)) begin
                @(posedge clk);
                #1;
                timeout_count = timeout_count + 1;
            end

            if (tile_ready !== 1'b1) begin
                fail_count = fail_count + 1;
                $display("[FAIL] Timeout waiting for tile_ready");
            end
        end
    endtask

    task wait_for_done;
        begin
            timeout_count = 0;

            while ((done !== 1'b1) && (timeout_count < 100)) begin
                @(posedge clk);
                #1;
                timeout_count = timeout_count + 1;
            end

            if (done !== 1'b1) begin
                fail_count = fail_count + 1;
                $display("[FAIL] Timeout waiting for DONE");
            end
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

    task check16;
        input [8*80-1:0] name;
        input [15:0] got;
        input [15:0] expected;
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

    task check32;
        input [8*80-1:0] name;
        input [31:0] got;
        input [31:0] expected;
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
    // Verify One Completed Output Row Tile
    //
    // One tile contains:
    //   4 output positions x 4 output channels
    //
    // Filters are constants:
    //   OC0 = all 1
    //   OC1 = all 2
    //   OC2 = all 3
    //   OC3 = all 4
    //
    // Therefore each PE row is:
    //   neighborhood_sum * [1,2,3,4]
    // ============================================================
    task verify_tile;
        input [15:0] expected_oh;

        input signed [31:0] sum0;
        input signed [31:0] sum1;
        input signed [31:0] sum2;
        input signed [31:0] sum3;

        input integer hold_cycles;

        integer h;
        begin

            wait_for_tile_ready();

            check16("tile_oh",      tile_oh,      expected_oh);
            check16("tile_ow_base", tile_ow_base, 16'd0);
            check16("tile_oc_base", tile_oc_base, 16'd0);

            // Row 0 / output position 0
            check32s("PE00", acc_00, sum0);
            check32s("PE01", acc_01, sum0 * 2);
            check32s("PE02", acc_02, sum0 * 3);
            check32s("PE03", acc_03, sum0 * 4);

            // Row 1 / output position 1
            check32s("PE10", acc_10, sum1);
            check32s("PE11", acc_11, sum1 * 2);
            check32s("PE12", acc_12, sum1 * 3);
            check32s("PE13", acc_13, sum1 * 4);

            // Row 2 / output position 2
            check32s("PE20", acc_20, sum2);
            check32s("PE21", acc_21, sum2 * 2);
            check32s("PE22", acc_22, sum2 * 3);
            check32s("PE23", acc_23, sum2 * 4);

            // Row 3 / output position 3
            check32s("PE30", acc_30, sum3);
            check32s("PE31", acc_31, sum3 * 2);
            check32s("PE32", acc_32, sum3 * 3);
            check32s("PE33", acc_33, sum3 * 4);

            // tile_ready must hold until downstream accepts.
            for (h = 0; h < hold_cycles; h = h + 1) begin
                @(posedge clk);
                #1;
                check1("tile_ready hold", tile_ready, 1'b1);
            end

            pulse_tile_accept();

        end
    endtask

    // ============================================================
    // Global Watchdog
    // ============================================================
    initial begin
        #1000000;
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

        rst          = 1'b1;
        clear        = 1'b0;
        buffer_clear = 1'b0;

        start        = 1'b0;
        tile_accept  = 1'b0;

        input_write_data  = 32'd0;
        input_write_valid = 1'b0;

        weight_write_data  = 32'd0;
        weight_write_valid = 1'b0;

        // --------------------------------------------------------
        // Small full convolution:
        //
        // Input  = 1 x 4 x 4
        // Output = 4 x 4 x 4
        // K=3, S=1, P=1
        //
        // With PE Array 4x4:
        //   one tile covers one whole output row (4 W positions)
        //   and all 4 output channels.
        //
        // Total = 4 output tiles.
        // --------------------------------------------------------
        input_h     = 16'd4;
        input_w     = 16'd4;
        cin         = 16'd1;
        cout        = 16'd4;

        kernel_size = 8'd3;
        stride      = 8'd1;
        padding     = 8'd1;

        out_h       = 16'd4;
        out_w       = 16'd4;

        repeat (3) @(posedge clk);
        #1;

        $display("");
        $display("==================================================");
        $display(" Convolution Engine 4x4 End-to-End Testbench");
        $display("==================================================");
        $display("");

        // ========================================================
        // TEST 1: Reset
        // ========================================================
        $display("---- TEST 1: Reset ----");

        check1("busy after reset", busy, 1'b0);
        check1("done after reset", done, 1'b0);
        check1("tile_ready after reset", tile_ready, 1'b0);

        @(negedge clk);
        rst = 1'b0;

        // ========================================================
        // TEST 2: Load Input and Weights
        //
        // Input:
        //
        //   1   2   3   4
        //   5   6   7   8
        //   9  10  11  12
        //  13  14  15  16
        //
        // OC0 kernel = all 1
        // OC1 kernel = all 2
        // OC2 kernel = all 3
        // OC3 kernel = all 4
        // ========================================================
        $display("");
        $display("---- TEST 2: Load Input / Weights ----");

        write_input_word(32'h0403_0201);
        write_input_word(32'h0807_0605);
        write_input_word(32'h0C0B_0A09);
        write_input_word(32'h100F_0E0D);

        write_weight_word(32'h0101_0101);
        write_weight_word(32'h0101_0101);
        write_weight_word(32'h0202_0201);
        write_weight_word(32'h0202_0202);
        write_weight_word(32'h0303_0202);
        write_weight_word(32'h0303_0303);
        write_weight_word(32'h0403_0303);
        write_weight_word(32'h0404_0404);
        write_weight_word(32'h0404_0404);

        check32("input count", input_stored_count, 32'd16);
        check32("weight count", weight_stored_count, 32'd36);

        check1("input overflow", input_overflow_error, 1'b0);
        check1("weight overflow", weight_overflow_error, 1'b0);

        // ========================================================
        // TEST 3: Single START -> Automatic Full Convolution
        // ========================================================
        $display("");
        $display("---- TEST 3: Automatic Full Convolution ----");

        pulse_start();

        check1("engine busy after START", busy, 1'b1);

        // --------------------------------------------------------
        // Expected 3x3 zero-padded neighborhood sums:
        //
        // Row 0: 14, 24, 30, 22
        // Row 1: 33, 54, 63, 45
        // Row 2: 57, 90, 99, 69
        // Row 3: 46, 72, 78, 54
        // --------------------------------------------------------

        // Hold first tile for two extra cycles to verify handshake.
        verify_tile(
            16'd0,
            32'sd14, 32'sd24, 32'sd30, 32'sd22,
            2
        );

        verify_tile(
            16'd1,
            32'sd33, 32'sd54, 32'sd63, 32'sd45,
            0
        );

        verify_tile(
            16'd2,
            32'sd57, 32'sd90, 32'sd99, 32'sd69,
            0
        );

        verify_tile(
            16'd3,
            32'sd46, 32'sd72, 32'sd78, 32'sd54,
            1
        );

        // ========================================================
        // TEST 4: DONE
        // ========================================================
        $display("");
        $display("---- TEST 4: DONE ----");

        wait_for_done();

        check1("engine done", done, 1'b1);
        check1("engine busy low in DONE", busy, 1'b0);
        check1("tile_ready low in DONE", tile_ready, 1'b0);

        // DONE should hold until CLEAR.
        repeat (3) @(posedge clk);
        #1;

        check1("DONE holds", done, 1'b1);

        // ========================================================
        // TEST 5: CLEAR -> IDLE
        // ========================================================
        $display("");
        $display("---- TEST 5: CLEAR -> IDLE ----");

        @(negedge clk);
        clear = 1'b1;

        @(posedge clk);
        #1;

        @(negedge clk);
        clear = 1'b0;

        #1;

        check1("done cleared", done, 1'b0);
        check1("busy after clear", busy, 1'b0);
        check1("tile_ready after clear", tile_ready, 1'b0);

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

        $display(" VCD: tb_convolution_engine_4x4.vcd");
        $display("==================================================");
        $display("");

        repeat (3) @(posedge clk);
        $finish;
    end

endmodule
