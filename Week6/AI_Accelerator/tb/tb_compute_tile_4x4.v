`timescale 1ns/1ps

module tb_compute_tile_4x4;

    // ============================================================
    // Small Buffer Parameters for Fast Verification
    // ============================================================
    localparam integer INPUT_MAX_VALUES  = 16;
    localparam integer WEIGHT_MAX_VALUES = 16;

    localparam integer INPUT_ADDR_WIDTH  = 4;
    localparam integer WEIGHT_ADDR_WIDTH = 4;

    // ============================================================
    // Clock / Reset
    // ============================================================
    reg clk;
    reg rst;

    // ============================================================
    // Buffer Write Interfaces
    // ============================================================
    reg [31:0] input_write_data;
    reg        input_write_valid;

    reg [31:0] weight_write_data;
    reg        weight_write_valid;

    reg        buffer_clear;

    // ============================================================
    // Compute Tile Control
    // ============================================================
    reg feeder_clear;
    reg clear_acc;
    reg start_fetch;

    reg [INPUT_ADDR_WIDTH-1:0]  input_base_addr;
    reg [WEIGHT_ADDR_WIDTH-1:0] weight_base_addr;

    // ============================================================
    // Buffer <-> Compute Tile Read Signals
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
    // Compute Tile Outputs
    // ============================================================
    wire        feeder_busy;
    wire        bundle_valid;

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
    // Compute Tile
    // ============================================================
    compute_tile_4x4 #(
        .INPUT_ADDR_WIDTH(INPUT_ADDR_WIDTH),
        .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),

        .feeder_clear(feeder_clear),
        .clear_acc(clear_acc),
        .start_fetch(start_fetch),

        .input_base_addr(input_base_addr),
        .weight_base_addr(weight_base_addr),

        .input_read_en(input_read_en),
        .input_read_addr(input_read_addr),
        .input_read_data(input_read_data),

        .weight_read_en(weight_read_en),
        .weight_read_addr(weight_read_addr),
        .weight_read_data(weight_read_data),

        .feeder_busy(feeder_busy),
        .bundle_valid(bundle_valid),

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
        $dumpfile("tb_compute_tile_4x4.vcd");
        $dumpvars(0, tb_compute_tile_4x4);
    end

    // ============================================================
    // Write One Packed Input Word
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

    // ============================================================
    // Write One Packed Weight Word
    // ============================================================
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
    // Start One Fetch
    // ============================================================
    task pulse_start_fetch;
        begin
            @(negedge clk);
            start_fetch = 1'b1;

            @(posedge clk);
            #1;

            @(negedge clk);
            start_fetch = 1'b0;
        end
    endtask

    // ============================================================
    // Wait Until Bundle Becomes Valid
    // ============================================================
    task wait_for_bundle;
        begin
            timeout_count = 0;

            while ((bundle_valid !== 1'b1) && (timeout_count < 20)) begin
                @(posedge clk);
                #1;
                timeout_count = timeout_count + 1;
            end

            if (bundle_valid !== 1'b1) begin
                fail_count = fail_count + 1;
                $display("[FAIL] Timeout waiting for bundle_valid");
            end
        end
    endtask

    // ============================================================
    // Wait for PE Array to Consume bundle_valid
    //
    // bundle_valid is asserted by the feeder after a posedge.
    // The PE array consumes that pulse at the following posedge.
    // ============================================================
    task wait_for_pe_accumulate;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    // ============================================================
    // Clear All PE Accumulators
    // ============================================================
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
    // Check 32-bit Unsigned/Raw Bus
    // ============================================================
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

    // ============================================================
    // Check Signed INT32
    // ============================================================
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
    // Check 1-bit
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
        start_fetch  = 1'b0;

        input_write_data  = 32'd0;
        input_write_valid = 1'b0;

        weight_write_data  = 32'd0;
        weight_write_valid = 1'b0;

        input_base_addr  = {INPUT_ADDR_WIDTH{1'b0}};
        weight_base_addr = {WEIGHT_ADDR_WIDTH{1'b0}};

        repeat (3) @(posedge clk);
        #1;

        $display("");
        $display("==================================================");
        $display(" Compute Tile 4x4 Integration Testbench");
        $display("==================================================");
        $display("");

        // ========================================================
        // TEST 1: Reset
        // ========================================================
        $display("---- TEST 1: Reset ----");

        check1("feeder_busy after reset", feeder_busy, 1'b0);
        check1("bundle_valid after reset", bundle_valid, 1'b0);

        check32s("PE00 after reset", acc_00, 32'sd0);
        check32s("PE11 after reset", acc_11, 32'sd0);
        check32s("PE22 after reset", acc_22, 32'sd0);
        check32s("PE33 after reset", acc_33, 32'sd0);

        @(negedge clk);
        rst = 1'b0;

        // ========================================================
        // TEST 2: Load Buffers
        //
        // Input addresses:
        //   0..3 = [1,2,3,4]
        //   4..7 = [1,1,1,1]
        //
        // Weight addresses:
        //   0..3 = [5,6,7,8]
        //   4..7 = [1,2,3,4]
        // ========================================================
        $display("");
        $display("---- TEST 2: Load Buffers ----");

        write_input_word(32'h0403_0201);
        write_input_word(32'h0101_0101);

        write_weight_word(32'h0807_0605);
        write_weight_word(32'h0403_0201);

        check32("input_stored_count",
                input_stored_count, 32'd8);

        check32("weight_stored_count",
                weight_stored_count, 32'd8);

        // ========================================================
        // TEST 3: First Bundle -> First Outer Product
        //
        // A = [1,2,3,4]
        // W = [5,6,7,8]
        // ========================================================
        $display("");
        $display("---- TEST 3: First Buffer -> Feeder -> PE Array ----");

        input_base_addr  = 4'd0;
        weight_base_addr = 4'd0;

        pulse_start_fetch();

        check1("feeder busy after start",
               feeder_busy, 1'b1);

        wait_for_bundle();

        check32("activation_bus first bundle",
                activation_bus, 32'h0403_0201);

        check32("weight_bus first bundle",
                weight_bus, 32'h0807_0605);

        // PE array consumes bundle_valid on next rising edge.
        wait_for_pe_accumulate();

        check32s("PE00 first result", acc_00, 32'sd5);
        check32s("PE01 first result", acc_01, 32'sd6);
        check32s("PE02 first result", acc_02, 32'sd7);
        check32s("PE03 first result", acc_03, 32'sd8);

        check32s("PE10 first result", acc_10, 32'sd10);
        check32s("PE11 first result", acc_11, 32'sd12);
        check32s("PE12 first result", acc_12, 32'sd14);
        check32s("PE13 first result", acc_13, 32'sd16);

        check32s("PE20 first result", acc_20, 32'sd15);
        check32s("PE21 first result", acc_21, 32'sd18);
        check32s("PE22 first result", acc_22, 32'sd21);
        check32s("PE23 first result", acc_23, 32'sd24);

        check32s("PE30 first result", acc_30, 32'sd20);
        check32s("PE31 first result", acc_31, 32'sd24);
        check32s("PE32 first result", acc_32, 32'sd28);
        check32s("PE33 first result", acc_33, 32'sd32);

        // ========================================================
        // TEST 4: Second Bundle -> Accumulation
        //
        // A = [1,1,1,1]
        // W = [1,2,3,4]
        //
        // Each row adds [1,2,3,4].
        // ========================================================
        $display("");
        $display("---- TEST 4: Second Bundle Accumulation ----");

        input_base_addr  = 4'd4;
        weight_base_addr = 4'd4;

        pulse_start_fetch();
        wait_for_bundle();
        wait_for_pe_accumulate();

        check32s("PE00 accumulated", acc_00, 32'sd6);
        check32s("PE03 accumulated", acc_03, 32'sd12);

        check32s("PE10 accumulated", acc_10, 32'sd11);
        check32s("PE13 accumulated", acc_13, 32'sd20);

        check32s("PE20 accumulated", acc_20, 32'sd16);
        check32s("PE23 accumulated", acc_23, 32'sd28);

        check32s("PE30 accumulated", acc_30, 32'sd21);
        check32s("PE33 accumulated", acc_33, 32'sd36);

        // ========================================================
        // TEST 5: Clear PE Accumulators
        // ========================================================
        $display("");
        $display("---- TEST 5: Clear PE Accumulators ----");

        clear_accumulators();

        check32s("PE00 after clear", acc_00, 32'sd0);
        check32s("PE11 after clear", acc_11, 32'sd0);
        check32s("PE22 after clear", acc_22, 32'sd0);
        check32s("PE33 after clear", acc_33, 32'sd0);

        // ========================================================
        // TEST 6: Signed End-to-End Data
        //
        // Clear buffers and load:
        //
        // A = [-1, 2, -3, 4]
        // W = [ 5,-6,  7,-8]
        // ========================================================
        $display("");
        $display("---- TEST 6: Signed End-to-End Data ----");

        // Clear buffer logical contents.
        @(negedge clk);
        buffer_clear = 1'b1;

        @(posedge clk);
        #1;

        @(negedge clk);
        buffer_clear = 1'b0;

        write_input_word(32'h04FD_02FF);
        write_weight_word(32'hF807_FA05);

        input_base_addr  = 4'd0;
        weight_base_addr = 4'd0;

        pulse_start_fetch();
        wait_for_bundle();

        check32("signed activation_bus",
                activation_bus, 32'h04FD_02FF);

        check32("signed weight_bus",
                weight_bus, 32'hF807_FA05);

        wait_for_pe_accumulate();

        check32s("signed PE00", acc_00, -32'sd5);
        check32s("signed PE01", acc_01,  32'sd6);
        check32s("signed PE02", acc_02, -32'sd7);
        check32s("signed PE03", acc_03,  32'sd8);

        check32s("signed PE10", acc_10,  32'sd10);
        check32s("signed PE11", acc_11, -32'sd12);
        check32s("signed PE12", acc_12,  32'sd14);
        check32s("signed PE13", acc_13, -32'sd16);

        check32s("signed PE20", acc_20, -32'sd15);
        check32s("signed PE21", acc_21,  32'sd18);
        check32s("signed PE22", acc_22, -32'sd21);
        check32s("signed PE23", acc_23,  32'sd24);

        check32s("signed PE30", acc_30,  32'sd20);
        check32s("signed PE31", acc_31, -32'sd24);
        check32s("signed PE32", acc_32,  32'sd28);
        check32s("signed PE33", acc_33, -32'sd32);

        // ========================================================
        // TEST 7: Feeder Clear Does Not Clear PE Accumulators
        //
        // feeder_clear only aborts feeder state. PE state should
        // remain untouched unless clear_acc is asserted.
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
                 acc_00, -32'sd5);

        check32s("PE33 preserved after feeder clear",
                 acc_33, -32'sd32);

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

        $display(" VCD: tb_compute_tile_4x4.vcd");
        $display("==================================================");
        $display("");

        repeat (3) @(posedge clk);
        $finish;
    end

endmodule
