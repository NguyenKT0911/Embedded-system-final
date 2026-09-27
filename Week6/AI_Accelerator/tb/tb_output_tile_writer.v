`timescale 1ns/1ps

module tb_output_tile_writer;

    localparam integer OUTPUT_ADDR_WIDTH = 14;

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

    // ============================================================
    // DUT Outputs
    // ============================================================
    wire        tile_accept;

    wire [OUTPUT_ADDR_WIDTH-1:0] write_addr;
    wire signed [31:0]           write_data;
    wire                         write_valid;

    wire                         busy;

    // ============================================================
    // Captured Write Stream
    // ============================================================
    reg [OUTPUT_ADDR_WIDTH-1:0] captured_addr [0:63];
    reg signed [31:0]           captured_data [0:63];

    integer captured_count;
    integer tile_accept_count;

    integer pass_count;
    integer fail_count;
    integer timeout_count;

    integer i;

    // ============================================================
    // DUT
    // ============================================================
    output_tile_writer #(
        .OUTPUT_ADDR_WIDTH(OUTPUT_ADDR_WIDTH)
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

        .write_addr(write_addr),
        .write_data(write_data),
        .write_valid(write_valid),

        .busy(busy)
    );

    // ============================================================
    // 100 MHz Clock
    // ============================================================
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // ============================================================
    // Waveform
    // ============================================================
    initial begin
        $dumpfile("tb_output_tile_writer.vcd");
        $dumpvars(0, tb_output_tile_writer);
    end

    // ============================================================
    // Monitor emitted writes / accepts
    // ============================================================
    always @(posedge clk) begin
        #1;

        if (write_valid) begin
            captured_addr[captured_count] = write_addr;
            captured_data[captured_count] = write_data;
            captured_count = captured_count + 1;
        end

        if (tile_accept)
            tile_accept_count = tile_accept_count + 1;
    end

    // ============================================================
    // Helpers
    // ============================================================
    task set_lane;
        input integer lane;
        input signed [31:0] value;
        begin
            accumulator_bus[lane*32 +: 32] = value;
        end
    endtask

    task reset_capture;
        begin
            captured_count   = 0;
            tile_accept_count = 0;

            for (i = 0; i < 64; i = i + 1) begin
                captured_addr[i] = {OUTPUT_ADDR_WIDTH{1'b0}};
                captured_data[i] = 32'sd0;
            end
        end
    endtask

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

    task check_int;
        input [8*80-1:0] name;
        input integer got;
        input integer expected;
        begin
            if (got == expected) begin
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

    task check_write;
        input integer index;
        input [OUTPUT_ADDR_WIDTH-1:0] expected_addr;
        input signed [31:0] expected_data;
        begin
            if ((captured_addr[index] === expected_addr) &&
                (captured_data[index] === expected_data)) begin

                pass_count = pass_count + 1;

                $display(
                    "[PASS] write[%0d] addr=%0d data=%0d",
                    index,
                    captured_addr[index],
                    captured_data[index]
                );

            end
            else begin

                fail_count = fail_count + 1;

                $display(
                    "[FAIL] write[%0d] got addr=%0d data=%0d expected addr=%0d data=%0d",
                    index,
                    captured_addr[index],
                    captured_data[index],
                    expected_addr,
                    expected_data
                );

            end
        end
    endtask

    // ============================================================
    // Real producer-style handshake:
    //
    // Keep tile_ready high until tile_accept is observed.
    // Then keep tile_ready high through the next rising edge
    // (the producer consumes tile_accept on that edge), and only
    // then deassert tile_ready.
    // ============================================================
    task send_tile_and_wait_accept;
        begin
            @(negedge clk);
            tile_ready = 1'b1;

            timeout_count = 0;

            while ((tile_accept !== 1'b1) && (timeout_count < 40)) begin
                @(negedge clk);
                timeout_count = timeout_count + 1;
            end

            if (tile_accept !== 1'b1) begin
                fail_count = fail_count + 1;
                $display("[FAIL] Timeout waiting for tile_accept");
            end
            else begin

                // Producer samples tile_accept here.
                @(posedge clk);
                #1;

                tile_ready = 1'b0;

                // Give writer time to observe released tile_ready.
                repeat (2) @(posedge clk);
                #1;

            end
        end
    endtask

    // ============================================================
    // Global Watchdog
    // ============================================================
    initial begin
        #200000;
        $display("[FAIL] GLOBAL TESTBENCH TIMEOUT");
        $finish;
    end

    // ============================================================
    // Main
    // ============================================================
    initial begin

        pass_count = 0;
        fail_count = 0;

        rst         = 1'b1;
        clear       = 1'b0;
        tile_ready  = 1'b0;

        tile_oh      = 16'd0;
        tile_ow_base = 16'd0;
        tile_oc_base = 16'd0;

        out_h = 16'd0;
        out_w = 16'd0;
        cout  = 16'd0;

        relu_en = 1'b0;

        accumulator_bus = 512'd0;

        reset_capture();

        repeat (3) @(posedge clk);
        #1;

        $display("");
        $display("==================================================");
        $display(" Output Tile Writer Testbench");
        $display("==================================================");
        $display("");

        // ========================================================
        // TEST 1: Reset
        // ========================================================
        $display("---- TEST 1: Reset ----");

        check1("busy after reset", busy, 1'b0);
        check1("tile_accept after reset", tile_accept, 1'b0);
        check1("write_valid after reset", write_valid, 1'b0);

        @(negedge clk);
        rst = 1'b0;

        // ========================================================
        // TEST 2: Full 4x4 Tile + ReLU ON
        //
        // out_h = 2, out_w = 4, cout = 4
        // tile is output row oh=1, W lanes 0..3, OC lanes 0..3.
        //
        // Output layout is [COUT][OUT_H][OUT_W].
        // ========================================================
        $display("");
        $display("---- TEST 2: Full Tile / ReLU ON ----");

        reset_capture();
        accumulator_bus = 512'd0;

        out_h = 16'd2;
        out_w = 16'd4;
        cout  = 16'd4;

        tile_oh      = 16'd1;
        tile_ow_base = 16'd0;
        tile_oc_base = 16'd0;

        relu_en = 1'b1;

        // Row 0
        set_lane(0,   32'sd10);
        set_lane(1,  -32'sd20);
        set_lane(2,   32'sd30);
        set_lane(3,  -32'sd40);

        // Row 1
        set_lane(4,   32'sd50);
        set_lane(5,  -32'sd60);
        set_lane(6,   32'sd70);
        set_lane(7,  -32'sd80);

        // Row 2
        set_lane(8,   32'sd90);
        set_lane(9,  -32'sd100);
        set_lane(10,  32'sd110);
        set_lane(11, -32'sd120);

        // Row 3
        set_lane(12,  32'sd130);
        set_lane(13, -32'sd140);
        set_lane(14,  32'sd150);
        set_lane(15, -32'sd160);

        send_tile_and_wait_accept();

        check_int("full tile write count", captured_count, 16);
        check_int("tile_accept pulse count", tile_accept_count, 1);

        // Writer scans PE lanes row-major.
        check_write(0,  14'd4,  32'sd10);
        check_write(1,  14'd12, 32'sd0);
        check_write(2,  14'd20, 32'sd30);
        check_write(3,  14'd28, 32'sd0);

        check_write(4,  14'd5,  32'sd50);
        check_write(5,  14'd13, 32'sd0);
        check_write(6,  14'd21, 32'sd70);
        check_write(7,  14'd29, 32'sd0);

        check_write(8,  14'd6,  32'sd90);
        check_write(9,  14'd14, 32'sd0);
        check_write(10, 14'd22, 32'sd110);
        check_write(11, 14'd30, 32'sd0);

        check_write(12, 14'd7,  32'sd130);
        check_write(13, 14'd15, 32'sd0);
        check_write(14, 14'd23, 32'sd150);
        check_write(15, 14'd31, 32'sd0);

        // Critical handshake regression:
        // same tile must NOT be captured/written twice.
        repeat (3) @(posedge clk);
        #1;

        check_int("no duplicate writes after accept", captured_count, 16);
        check_int("no duplicate tile_accept", tile_accept_count, 1);

        // ========================================================
        // TEST 3: Tail Lanes + ReLU OFF
        //
        // out_h=1, out_w=2, cout=2:
        // only rows 0..1 and channel lanes 0..1 are valid.
        // ========================================================
        $display("");
        $display("---- TEST 3: Tail Mask / ReLU OFF ----");

        reset_capture();
        accumulator_bus = 512'd0;

        out_h = 16'd1;
        out_w = 16'd2;
        cout  = 16'd2;

        tile_oh      = 16'd0;
        tile_ow_base = 16'd0;
        tile_oc_base = 16'd0;

        relu_en = 1'b0;

        set_lane(0, -32'sd1);
        set_lane(1, -32'sd2);
        set_lane(2, -32'sd3);
        set_lane(3, -32'sd4);

        set_lane(4, -32'sd5);
        set_lane(5, -32'sd6);
        set_lane(6, -32'sd7);
        set_lane(7, -32'sd8);

        send_tile_and_wait_accept();

        check_int("tail tile valid write count", captured_count, 4);
        check_int("tail tile accept count", tile_accept_count, 1);

        // Flatten [COUT][H][W]:
        // OC0 -> addr 0,1
        // OC1 -> addr 2,3
        check_write(0, 14'd0, -32'sd1);
        check_write(1, 14'd2, -32'sd2);
        check_write(2, 14'd1, -32'sd5);
        check_write(3, 14'd3, -32'sd6);

        // ========================================================
        // TEST 4: Non-zero Tile Bases
        //
        // Verify flat-address calculation with offsets.
        // Only one valid W lane and one valid OC lane are left.
        // ========================================================
        $display("");
        $display("---- TEST 4: Non-zero Tile Base / Tail ----");

        reset_capture();
        accumulator_bus = 512'd0;

        out_h = 16'd3;
        out_w = 16'd5;
        cout  = 16'd5;

        tile_oh      = 16'd2;
        tile_ow_base = 16'd4;
        tile_oc_base = 16'd4;

        relu_en = 1'b1;

        set_lane(0, 32'sd777);
        set_lane(1, 32'sd888);
        set_lane(4, 32'sd999);

        send_tile_and_wait_accept();

        // Only row lane 0 (ow=4) and channel lane 0 (oc=4) valid.
        check_int("offset tail write count", captured_count, 1);

        // ((4*3)+2)*5 + 4 = 74
        check_write(0, 14'd74, 32'sd777);

        // ========================================================
        // TEST 5: Clear During Write
        // ========================================================
        $display("");
        $display("---- TEST 5: Clear During Write ----");

        reset_capture();
        accumulator_bus = 512'd0;

        out_h = 16'd2;
        out_w = 16'd4;
        cout  = 16'd4;

        tile_oh      = 16'd0;
        tile_ow_base = 16'd0;
        tile_oc_base = 16'd0;

        relu_en = 1'b0;

        for (i = 0; i < 16; i = i + 1)
            set_lane(i, i + 1);

        @(negedge clk);
        tile_ready = 1'b1;

        // Wait until a few writes have occurred.
        while (captured_count < 3)
            @(posedge clk);

        @(negedge clk);
        clear = 1'b1;

        @(posedge clk);
        #1;

        tile_ready = 1'b0;

        @(negedge clk);
        clear = 1'b0;

        repeat (3) @(posedge clk);
        #1;

        check1("busy low after clear", busy, 1'b0);
        check1("tile_accept low after aborted tile", tile_accept, 1'b0);

        if (captured_count < 16) begin
            pass_count = pass_count + 1;
            $display("[PASS] clear aborted tile before all 16 writes | writes=%0d",
                     captured_count);
        end
        else begin
            fail_count = fail_count + 1;
            $display("[FAIL] clear did not abort tile write");
        end

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

        $display(" VCD: tb_output_tile_writer.vcd");
        $display("==================================================");
        $display("");

        repeat (3) @(posedge clk);
        $finish;
    end

endmodule
