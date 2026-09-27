`timescale 1ns/1ps

module tb_conv_sequencer_4x4;

    // ============================================================
    // DUT Inputs
    // ============================================================
    reg clk;
    reg rst;
    reg clear;

    reg start;

    reg [15:0] cin;
    reg [15:0] cout;
    reg [7:0]  kernel_size;

    reg [15:0] out_h;
    reg [15:0] out_w;

    reg step_busy;
    reg step_done;

    reg tile_accept;

    // ============================================================
    // DUT Outputs
    // ============================================================
    wire start_step;
    wire clear_acc;
    wire tile_ready;

    wire [15:0] oh;
    wire [15:0] ow_base;
    wire [15:0] oc_base;

    wire [15:0] ic;
    wire [7:0]  kh;
    wire [7:0]  kw;

    wire busy;
    wire done;

    // ============================================================
    // Test Counters
    // ============================================================
    integer pass_count;
    integer fail_count;

    integer mock_latency;

    // ============================================================
    // DUT
    // ============================================================
    conv_sequencer_4x4 dut (
        .clk(clk),
        .rst(rst),
        .clear(clear),

        .start(start),

        .cin(cin),
        .cout(cout),
        .kernel_size(kernel_size),

        .out_h(out_h),
        .out_w(out_w),

        .step_busy(step_busy),
        .step_done(step_done),

        .start_step(start_step),
        .clear_acc(clear_acc),

        .tile_ready(tile_ready),
        .tile_accept(tile_accept),

        .oh(oh),
        .ow_base(ow_base),
        .oc_base(oc_base),

        .ic(ic),
        .kh(kh),
        .kw(kw),

        .busy(busy),
        .done(done)
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
        $dumpfile("tb_conv_sequencer_4x4.vcd");
        $dumpvars(0, tb_conv_sequencer_4x4);
    end

    // ============================================================
    // Mock Datapath
    //
    // Each accepted start_step:
    //   1) raises step_busy
    //   2) waits a small fixed latency
    //   3) pulses step_done for one clock
    //
    // This lets us verify the sequencer independently from the
    // real convolution datapath.
    // ============================================================
    always @(posedge clk) begin

        if (rst || clear) begin

            step_busy    <= 1'b0;
            step_done    <= 1'b0;
            mock_latency <= 0;

        end
        else begin

            step_done <= 1'b0;

            if (start_step && !step_busy) begin

                step_busy    <= 1'b1;
                mock_latency <= 1;

            end
            else if (step_busy) begin

                if (mock_latency == 0) begin

                    step_busy <= 1'b0;
                    step_done <= 1'b1;

                end
                else begin

                    mock_latency <= mock_latency - 1;

                end

            end

        end

    end

    // ============================================================
    // Basic Check Tasks
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

    // ============================================================
    // Pulse START
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

    // ============================================================
    // Pulse TILE_ACCEPT
    // ============================================================
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

    // ============================================================
    // Wait for START_STEP with timeout
    // ============================================================
    task wait_for_start_step;
        output integer timed_out;
        integer wait_count;
        begin
            timed_out = 0;
            wait_count = 0;

            while ((start_step !== 1'b1) && (wait_count < 30)) begin
                @(negedge clk);
                wait_count = wait_count + 1;
            end

            if (start_step !== 1'b1)
                timed_out = 1;
        end
    endtask

    // ============================================================
    // Wait for TILE_READY with timeout
    // ============================================================
    task wait_for_tile_ready;
        output integer timed_out;
        integer wait_count;
        begin
            timed_out = 0;
            wait_count = 0;

            while ((tile_ready !== 1'b1) && (wait_count < 60)) begin
                @(negedge clk);
                wait_count = wait_count + 1;
            end

            if (tile_ready !== 1'b1)
                timed_out = 1;
        end
    endtask

    // ============================================================
    // Verify One Complete Output Tile
    //
    // Current test configuration:
    //   CIN = 2
    //   K   = 3
    //
    // Therefore each tile requires:
    //   2 * 3 * 3 = 18 convolution steps.
    //
    // Expected inner-loop order:
    //   kw -> kh -> ic
    // ============================================================
    task verify_tile;
        input [15:0] expected_oh;
        input [15:0] expected_ow;
        input [15:0] expected_oc;
        input integer hold_ready_cycles;
        input integer final_tile;

        integer step_index;
        integer expected_ic;
        integer expected_kh;
        integer expected_kw;
        integer remainder;

        integer timeout_flag;
        integer tile_ok;
        integer hold_index;

        begin
            tile_ok = 1;

            // ----------------------------------------------------
            // Verify all 18 start_step requests for this tile.
            // ----------------------------------------------------
            for (step_index = 0;
                 step_index < 18;
                 step_index = step_index + 1) begin

                wait_for_start_step(timeout_flag);

                if (timeout_flag) begin

                    tile_ok = 0;
                    fail_count = fail_count + 1;

                    $display(
                        "[FAIL] Timeout waiting start_step for tile oh=%0d ow=%0d oc=%0d step=%0d",
                        expected_oh,
                        expected_ow,
                        expected_oc,
                        step_index
                    );

                    // Prevent endless additional waits for this tile.
                    step_index = 18;

                end
                else begin

                    expected_ic = step_index / 9;
                    remainder   = step_index % 9;
                    expected_kh = remainder / 3;
                    expected_kw = remainder % 3;

                    if (
                        (oh      !== expected_oh) ||
                        (ow_base !== expected_ow) ||
                        (oc_base !== expected_oc) ||
                        (ic      !== expected_ic) ||
                        (kh      !== expected_kh) ||
                        (kw      !== expected_kw)
                    ) begin

                        tile_ok = 0;

                        $display(
                            "[FAIL] Step sequence mismatch: tile(%0d,%0d,%0d) step=%0d got ic/kh/kw=%0d/%0d/%0d expected=%0d/%0d/%0d",
                            expected_oh,
                            expected_ow,
                            expected_oc,
                            step_index,
                            ic,
                            kh,
                            kw,
                            expected_ic,
                            expected_kh,
                            expected_kw
                        );

                    end

                    // Wait until this mocked datapath transaction
                    // has completed before looking for next request.
                    while (step_busy || !step_done)
                        @(negedge clk);

                    // Let sequencer consume step_done.
                    @(posedge clk);
                    #1;

                end

            end

            if (tile_ok) begin
                pass_count = pass_count + 1;
                $display(
                    "[PASS] Tile (%0d,%0d,%0d) inner ic/kh/kw sequence = 18 steps correct",
                    expected_oh,
                    expected_ow,
                    expected_oc
                );
            end
            else begin
                fail_count = fail_count + 1;
                $display(
                    "[FAIL] Tile (%0d,%0d,%0d) inner sequence",
                    expected_oh,
                    expected_ow,
                    expected_oc
                );
            end

            // ----------------------------------------------------
            // Completed tile must enter TILE_READY.
            // ----------------------------------------------------
            wait_for_tile_ready(timeout_flag);

            if (timeout_flag) begin

                fail_count = fail_count + 1;
                $display(
                    "[FAIL] Tile (%0d,%0d,%0d) never reached TILE_READY",
                    expected_oh,
                    expected_ow,
                    expected_oc
                );

            end
            else begin

                if (
                    (oh      === expected_oh) &&
                    (ow_base === expected_ow) &&
                    (oc_base === expected_oc)
                ) begin

                    pass_count = pass_count + 1;
                    $display(
                        "[PASS] TILE_READY for tile (%0d,%0d,%0d)",
                        expected_oh,
                        expected_ow,
                        expected_oc
                    );

                end
                else begin

                    fail_count = fail_count + 1;
                    $display(
                        "[FAIL] TILE_READY indices got (%0d,%0d,%0d) expected (%0d,%0d,%0d)",
                        oh,
                        ow_base,
                        oc_base,
                        expected_oh,
                        expected_ow,
                        expected_oc
                    );

                end

            end

            // ----------------------------------------------------
            // TILE_READY must remain asserted until tile_accept.
            // ----------------------------------------------------
            for (hold_index = 0;
                 hold_index < hold_ready_cycles;
                 hold_index = hold_index + 1) begin

                @(posedge clk);
                #1;

                if (tile_ready !== 1'b1) begin
                    fail_count = fail_count + 1;
                    $display("[FAIL] TILE_READY did not hold before tile_accept");
                end

            end

            if (hold_ready_cycles > 0) begin
                pass_count = pass_count + 1;
                $display(
                    "[PASS] TILE_READY held for %0d cycle(s) before accept",
                    hold_ready_cycles
                );
            end

            // ----------------------------------------------------
            // Downstream captures tile.
            // ----------------------------------------------------
            pulse_tile_accept();

            if (final_tile) begin

                // Final tile must go to DONE.
                #1;

                if (done === 1'b1) begin
                    pass_count = pass_count + 1;
                    $display("[PASS] Final tile -> DONE");
                end
                else begin
                    fail_count = fail_count + 1;
                    $display("[FAIL] Final tile did not enter DONE");
                end

            end
            else begin

                // Every non-final tile must clear PE accumulators
                // before starting the next tile.
                #1;

                if (clear_acc === 1'b1) begin
                    pass_count = pass_count + 1;
                    $display("[PASS] Next tile begins with clear_acc");
                end
                else begin
                    fail_count = fail_count + 1;
                    $display("[FAIL] clear_acc missing between tiles");
                end

            end

        end
    endtask

    // ============================================================
    // Global Watchdog
    // ============================================================
    initial begin
        #500000;

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

        rst         = 1'b1;
        clear       = 1'b0;
        start       = 1'b0;
        tile_accept = 1'b0;

        // The mock datapath always starts idle.
        step_busy   = 1'b0;
        step_done   = 1'b0;
        mock_latency = 0;

        // --------------------------------------------------------
        // Test a configuration that exercises all nested loops:
        //
        // CIN  = 2       -> tests ic loop
        // K    = 3       -> tests kh / kw loops
        // OUT_H= 2       -> tests oh loop
        // OUT_W= 5       -> tiles ow_base = 0,4
        // COUT = 5       -> tiles oc_base = 0,4
        //
        // Total output tiles:
        //   ceil(5/4) * 2 * ceil(5/4)
        //   = 2 * 2 * 2
        //   = 8 tiles
        // --------------------------------------------------------
        cin         = 16'd2;
        cout        = 16'd5;
        kernel_size = 8'd3;

        out_h       = 16'd2;
        out_w       = 16'd5;

        repeat (3) @(posedge clk);
        #1;

        $display("");
        $display("==================================================");
        $display(" Convolution Sequencer 4x4 Testbench");
        $display("==================================================");
        $display("");

        // ========================================================
        // TEST 1: Reset / IDLE
        // ========================================================
        $display("---- TEST 1: Reset / IDLE ----");

        check1("busy after reset", busy, 1'b0);
        check1("done after reset", done, 1'b0);
        check1("start_step after reset", start_step, 1'b0);
        check1("tile_ready after reset", tile_ready, 1'b0);

        check16("oh after reset", oh, 16'd0);
        check16("ow_base after reset", ow_base, 16'd0);
        check16("oc_base after reset", oc_base, 16'd0);
        check16("ic after reset", ic, 16'd0);

        @(negedge clk);
        rst = 1'b0;

        // ========================================================
        // TEST 2: START
        // ========================================================
        $display("");
        $display("---- TEST 2: START / First Tile Clear ----");

        pulse_start();

        check1("busy after START", busy, 1'b1);
        check1("clear_acc before first tile", clear_acc, 1'b1);

        // ========================================================
        // TEST 3: Full Nested Sequencing
        //
        // Traversal order is:
        //   ow_base -> oh -> oc_base
        // ========================================================
        $display("");
        $display("---- TEST 3: Full Nested Tile Traversal ----");

        // OC group 0..3
        verify_tile(16'd0, 16'd0, 16'd0, 2, 0);
        verify_tile(16'd0, 16'd4, 16'd0, 0, 0);
        verify_tile(16'd1, 16'd0, 16'd0, 0, 0);
        verify_tile(16'd1, 16'd4, 16'd0, 0, 0);

        // OC group 4 (tail group)
        verify_tile(16'd0, 16'd0, 16'd4, 0, 0);
        verify_tile(16'd0, 16'd4, 16'd4, 0, 0);
        verify_tile(16'd1, 16'd0, 16'd4, 0, 0);
        verify_tile(16'd1, 16'd4, 16'd4, 2, 1);

        // ========================================================
        // TEST 4: DONE Holds
        // ========================================================
        $display("");
        $display("---- TEST 4: DONE Hold ----");

        repeat (3) @(posedge clk);
        #1;

        check1("done holds without CLEAR", done, 1'b1);
        check1("busy low in DONE", busy, 1'b0);
        check1("tile_ready low in DONE", tile_ready, 1'b0);
        check1("start_step low in DONE", start_step, 1'b0);

        // ========================================================
        // TEST 5: CLEAR returns to IDLE
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
        check1("busy after CLEAR", busy, 1'b0);

        check16("oh reset by CLEAR", oh, 16'd0);
        check16("ow_base reset by CLEAR", ow_base, 16'd0);
        check16("oc_base reset by CLEAR", oc_base, 16'd0);
        check16("ic reset by CLEAR", ic, 16'd0);

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

        $display(" VCD: tb_conv_sequencer_4x4.vcd");
        $display("==================================================");
        $display("");

        repeat (3) @(posedge clk);
        $finish;
    end

endmodule
