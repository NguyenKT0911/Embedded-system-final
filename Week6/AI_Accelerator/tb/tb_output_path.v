`timescale 1ns/1ps

module tb_output_path;

    // ============================================================
    // Small Output Buffer for Fast Integration Testing
    // ============================================================
    localparam integer MAX_VALUES = 32;
    localparam integer ADDR_WIDTH = 5;

    // ============================================================
    // DUT Inputs
    // ============================================================
    reg clk;
    reg rst;
    reg clear;

    reg         tile_ready;

    reg [15:0]  tile_oh;
    reg [15:0]  tile_ow_base;
    reg [15:0]  tile_oc_base;

    reg [15:0]  out_h;
    reg [15:0]  out_w;
    reg [15:0]  cout;

    reg         relu_en;

    reg [511:0] accumulator_bus;

    reg         output_read_next;

    // ============================================================
    // DUT Outputs
    // ============================================================
    wire        tile_accept;

    wire signed [31:0] output_data;

    wire [31:0] output_count;
    wire [31:0] output_read_index;

    wire        output_empty;
    wire        output_full;
    wire        output_overflow_error;

    wire        writer_busy;

    // ============================================================
    // Test Counters
    // ============================================================
    integer pass_count;
    integer fail_count;

    integer tile_accept_count;
    integer timeout_count;

    integer i;

    // ============================================================
    // DUT
    // ============================================================
    output_path #(
        .MAX_VALUES(MAX_VALUES),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .clear(clear),

        .tile_ready(tile_ready),
        .tile_accept(tile_accept),

        .tile_oh(tile_oh),
        .tile_ow_base(tile_ow_base),
        .tile_oc_base(tile_oc_base),

        .out_h(out_h),
        .out_w(out_w),
        .cout(cout),

        .relu_en(relu_en),

        .accumulator_bus(accumulator_bus),

        .output_data(output_data),
        .output_read_next(output_read_next),

        .output_count(output_count),
        .output_read_index(output_read_index),

        .output_empty(output_empty),
        .output_full(output_full),
        .output_overflow_error(output_overflow_error),

        .writer_busy(writer_busy)
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
        $dumpfile("tb_output_path.vcd");
        $dumpvars(0, tb_output_path);
    end

    // ============================================================
    // Count tile_accept pulses
    // ============================================================
    always @(posedge clk) begin
        #1;

        if (tile_accept)
            tile_accept_count = tile_accept_count + 1;
    end

    // ============================================================
    // Set One PE Lane in accumulator_bus
    // ============================================================
    task set_lane;
        input integer lane;
        input signed [31:0] value;
        begin
            accumulator_bus[lane*32 +: 32] = value;
        end
    endtask

    // ============================================================
    // Clear Output Path
    // ============================================================
    task clear_output_path;
        begin
            @(negedge clk);
            clear = 1'b1;

            @(posedge clk);
            #1;

            @(negedge clk);
            clear = 1'b0;

            repeat (2) @(posedge clk);
            #1;
        end
    endtask

    // ============================================================
    // Send One Tile
    //
    // Producer-style handshake:
    // keep tile_ready high until tile_accept is sampled.
    // ============================================================
    task send_tile;
        begin
            @(negedge clk);
            tile_ready = 1'b1;

            timeout_count = 0;

            while ((tile_accept !== 1'b1) && (timeout_count < 50)) begin
                @(negedge clk);
                timeout_count = timeout_count + 1;
            end

            if (tile_accept !== 1'b1) begin
                fail_count = fail_count + 1;
                $display("[FAIL] Timeout waiting for tile_accept");
            end
            else begin

                // Producer samples tile_accept on this rising edge.
                @(posedge clk);
                #1;

                tile_ready = 1'b0;

                // Let writer exit WAIT_RELEASE and return to IDLE.
                repeat (2) @(posedge clk);
                #1;

            end
        end
    endtask

    // ============================================================
    // Advance Sequential MMIO Read Pointer
    // ============================================================
    task advance_read;
        begin
            @(negedge clk);
            output_read_next = 1'b1;

            @(posedge clk);
            #1;

            @(negedge clk);
            output_read_next = 1'b0;
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
    // Global Watchdog
    // ============================================================
    initial begin
        #300000;
        $display("");
        $display("[FAIL] GLOBAL TESTBENCH TIMEOUT");
        $finish;
    end

    // ============================================================
    // Main Test Sequence
    // ============================================================
    initial begin

        pass_count        = 0;
        fail_count        = 0;
        tile_accept_count = 0;

        rst               = 1'b1;
        clear             = 1'b0;

        tile_ready        = 1'b0;

        tile_oh           = 16'd0;
        tile_ow_base      = 16'd0;
        tile_oc_base      = 16'd0;

        out_h             = 16'd0;
        out_w             = 16'd0;
        cout              = 16'd0;

        relu_en           = 1'b0;

        accumulator_bus   = 512'd0;

        output_read_next  = 1'b0;

        repeat (3) @(posedge clk);
        #1;

        $display("");
        $display("==================================================");
        $display(" Output Path Integration Testbench");
        $display("==================================================");
        $display("");

        // ========================================================
        // TEST 1: Reset
        // ========================================================
        $display("---- TEST 1: Reset ----");

        check1 ("tile_accept after reset", tile_accept, 1'b0);
        check1 ("writer_busy after reset", writer_busy, 1'b0);

        check32("output_count after reset", output_count, 32'd0);
        check32("read_index after reset", output_read_index, 32'd0);

        check1 ("output_empty after reset", output_empty, 1'b1);
        check1 ("output_full after reset", output_full, 1'b0);
        check1 ("overflow after reset", output_overflow_error, 1'b0);

        check32s("output_data after reset", output_data, 32'sd0);

        @(negedge clk);
        rst = 1'b0;

        // ========================================================
        // TEST 2: Full 4x4 Tile + ReLU ON
        //
        // Configuration:
        //   OUT_H = 1
        //   OUT_W = 4
        //   COUT  = 4
        //
        // The writer scans PE row-major, but the buffer must store
        // results in [COUT][OUT_H][OUT_W] layout.
        // ========================================================
        $display("");
        $display("---- TEST 2: Full Tile -> ReLU -> Output Buffer ----");

        accumulator_bus = 512'd0;

        out_h = 16'd1;
        out_w = 16'd4;
        cout  = 16'd4;

        tile_oh      = 16'd0;
        tile_ow_base = 16'd0;
        tile_oc_base = 16'd0;

        relu_en = 1'b1;

        // row 0 / ow=0
        set_lane(0,   32'sd10);
        set_lane(1,  -32'sd20);
        set_lane(2,   32'sd30);
        set_lane(3,  -32'sd40);

        // row 1 / ow=1
        set_lane(4,   32'sd50);
        set_lane(5,  -32'sd60);
        set_lane(6,   32'sd70);
        set_lane(7,  -32'sd80);

        // row 2 / ow=2
        set_lane(8,   32'sd90);
        set_lane(9,  -32'sd100);
        set_lane(10,  32'sd110);
        set_lane(11, -32'sd120);

        // row 3 / ow=3
        set_lane(12,  32'sd130);
        set_lane(13, -32'sd140);
        set_lane(14,  32'sd150);
        set_lane(15, -32'sd160);

        send_tile();

        check32("full tile output_count", output_count, 32'd16);
        check32("read index still zero", output_read_index, 32'd0);

        check1("output not empty", output_empty, 1'b0);
        check1("output not full", output_full, 1'b0);
        check1("no output overflow", output_overflow_error, 1'b0);

        check32("tile_accept exactly once", tile_accept_count, 32'd1);

        // --------------------------------------------------------
        // Sequential readback in [COUT][H][W] order:
        //
        // OC0: 10, 50, 90, 130
        // OC1: 0,  0,  0,   0
        // OC2: 30, 70,110, 150
        // OC3: 0,  0,  0,   0
        // --------------------------------------------------------
        check32s("output[0] OC0/W0", output_data, 32'sd10);

        advance_read();
        check32s("output[1] OC0/W1", output_data, 32'sd50);

        advance_read();
        check32s("output[2] OC0/W2", output_data, 32'sd90);

        advance_read();
        check32s("output[3] OC0/W3", output_data, 32'sd130);

        advance_read();
        check32s("output[4] OC1/W0 ReLU", output_data, 32'sd0);

        advance_read();
        check32s("output[5] OC1/W1 ReLU", output_data, 32'sd0);

        advance_read();
        check32s("output[6] OC1/W2 ReLU", output_data, 32'sd0);

        advance_read();
        check32s("output[7] OC1/W3 ReLU", output_data, 32'sd0);

        advance_read();
        check32s("output[8] OC2/W0", output_data, 32'sd30);

        advance_read();
        check32s("output[9] OC2/W1", output_data, 32'sd70);

        advance_read();
        check32s("output[10] OC2/W2", output_data, 32'sd110);

        advance_read();
        check32s("output[11] OC2/W3", output_data, 32'sd150);

        advance_read();
        check32s("output[12] OC3/W0 ReLU", output_data, 32'sd0);

        advance_read();
        check32s("output[13] OC3/W1 ReLU", output_data, 32'sd0);

        advance_read();
        check32s("output[14] OC3/W2 ReLU", output_data, 32'sd0);

        advance_read();
        check32s("output[15] OC3/W3 ReLU", output_data, 32'sd0);

        advance_read();

        check32("read index after 16 reads",
                output_read_index, 32'd16);

        check1("output empty after 16 reads",
               output_empty, 1'b1);

        check32s("output_data when empty",
                 output_data, 32'sd0);

        // ========================================================
        // TEST 3: Clear Entire Output Path
        // ========================================================
        $display("");
        $display("---- TEST 3: Clear Output Path ----");

        clear_output_path();

        check32("count after clear", output_count, 32'd0);
        check32("read index after clear", output_read_index, 32'd0);

        check1("empty after clear", output_empty, 1'b1);
        check1("writer idle after clear", writer_busy, 1'b0);

        // ========================================================
        // TEST 4: Tail Tile + ReLU OFF
        //
        // OUT_H=1, OUT_W=2, COUT=2
        // Valid PE lanes:
        //   row 0..1
        //   channel 0..1
        //
        // Output tensor has 4 values total.
        // ========================================================
        $display("");
        $display("---- TEST 4: Tail Tile / ReLU OFF ----");

        tile_accept_count = 0;
        accumulator_bus   = 512'd0;

        out_h = 16'd1;
        out_w = 16'd2;
        cout  = 16'd2;

        tile_oh      = 16'd0;
        tile_ow_base = 16'd0;
        tile_oc_base = 16'd0;

        relu_en = 1'b0;

        set_lane(0, -32'sd1);  // OC0, W0 -> addr 0
        set_lane(1, -32'sd2);  // OC1, W0 -> addr 2

        set_lane(4, -32'sd5);  // OC0, W1 -> addr 1
        set_lane(5, -32'sd6);  // OC1, W1 -> addr 3

        // Invalid tail lanes contain junk; they must be ignored.
        set_lane(2,  32'sd777);
        set_lane(3,  32'sd888);
        set_lane(8,  32'sd999);
        set_lane(12, 32'sd1111);

        send_tile();

        check32("tail output_count", output_count, 32'd4);
        check32("tail tile_accept once", tile_accept_count, 32'd1);

        // Sequential [COUT][H][W] layout:
        // OC0: -1, -5
        // OC1: -2, -6
        check32s("tail output[0]", output_data, -32'sd1);

        advance_read();
        check32s("tail output[1]", output_data, -32'sd5);

        advance_read();
        check32s("tail output[2]", output_data, -32'sd2);

        advance_read();
        check32s("tail output[3]", output_data, -32'sd6);

        advance_read();

        check1("tail output empty after reads",
               output_empty, 1'b1);

        // ========================================================
        // TEST 5: Reset Priority
        // ========================================================
        $display("");
        $display("---- TEST 5: Reset Priority ----");

        @(negedge clk);

        rst              = 1'b1;
        clear            = 1'b1;
        tile_ready       = 1'b1;
        output_read_next = 1'b1;

        @(posedge clk);
        #1;

        check32("count after reset priority",
                output_count, 32'd0);

        check32("read index after reset priority",
                output_read_index, 32'd0);

        check1("empty after reset priority",
               output_empty, 1'b1);

        check1("writer idle after reset priority",
               writer_busy, 1'b0);

        @(negedge clk);

        rst              = 1'b0;
        clear            = 1'b0;
        tile_ready       = 1'b0;
        output_read_next = 1'b0;

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

        $display(" VCD: tb_output_path.vcd");
        $display("==================================================");
        $display("");

        repeat (3) @(posedge clk);
        $finish;
    end

endmodule
