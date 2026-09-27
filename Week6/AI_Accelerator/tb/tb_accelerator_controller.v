`timescale 1ns/1ps

module tb_accelerator_controller;

    reg clk;
    reg rst;

    reg start_pulse;
    reg clear_pulse;
    reg validation_ok;
    reg compute_done;
    reg compute_error;

    wire busy;
    wire done;
    wire error;
    wire core_enable;

    integer pass_count;
    integer fail_count;

    accelerator_controller dut (
        .clk(clk),
        .rst(rst),
        .start_pulse(start_pulse),
        .clear_pulse(clear_pulse),
        .validation_ok(validation_ok),
        .compute_done(compute_done),
        .compute_error(compute_error),
        .busy(busy),
        .done(done),
        .error(error),
        .core_enable(core_enable)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("tb_accelerator_controller.vcd");
        $dumpvars(0, tb_accelerator_controller);
    end

    task check_outputs;
        input [8*64-1:0] name;
        input expected_busy;
        input expected_done;
        input expected_error;
        input expected_core_enable;
        begin
            if ((busy === expected_busy) &&
                (done === expected_done) &&
                (error === expected_error) &&
                (core_enable === expected_core_enable)) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s | B/D/E/EN=%b/%b/%b/%b",
                         name, busy, done, error, core_enable);
            end
            else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s | got=%b/%b/%b/%b expected=%b/%b/%b/%b",
                         name, busy, done, error, core_enable,
                         expected_busy, expected_done,
                         expected_error, expected_core_enable);
            end
        end
    endtask

    task issue_start;
        begin
            @(negedge clk);
            start_pulse = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            start_pulse = 1'b0;
        end
    endtask

    task issue_clear;
        begin
            @(negedge clk);
            clear_pulse = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            clear_pulse = 1'b0;
        end
    endtask

    task issue_compute_done;
        begin
            @(negedge clk);
            compute_done = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            compute_done = 1'b0;
        end
    endtask

    task issue_compute_error;
        begin
            @(negedge clk);
            compute_error = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            compute_error = 1'b0;
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;

        rst = 1'b1;
        start_pulse = 1'b0;
        clear_pulse = 1'b0;
        validation_ok = 1'b0;
        compute_done = 1'b0;
        compute_error = 1'b0;

        repeat (3) @(posedge clk);
        #1;

        check_outputs("RESET -> IDLE", 1'b0, 1'b0, 1'b0, 1'b0);

        @(negedge clk);
        rst = 1'b0;

        $display("");
        $display("==============================================");
        $display(" AI Accelerator Controller FSM Testbench");
        $display("==============================================");

        // TEST 1: IDLE hold
        repeat (2) @(posedge clk);
        #1;
        check_outputs("IDLE hold", 1'b0, 1'b0, 1'b0, 1'b0);

        // TEST 2: Valid flow
        validation_ok = 1'b1;

        issue_start();
        check_outputs("START -> CHECK", 1'b1, 1'b0, 1'b0, 1'b0);

        @(posedge clk);
        #1;
        check_outputs("CHECK valid -> RUN", 1'b1, 1'b0, 1'b0, 1'b1);

        repeat (2) @(posedge clk);
        #1;
        check_outputs("RUN hold", 1'b1, 1'b0, 1'b0, 1'b1);

        issue_compute_done();
        check_outputs("compute_done -> DONE", 1'b0, 1'b1, 1'b0, 1'b0);

        repeat (2) @(posedge clk);
        #1;
        check_outputs("DONE hold", 1'b0, 1'b1, 1'b0, 1'b0);

        issue_clear();
        check_outputs("CLEAR from DONE -> IDLE", 1'b0, 1'b0, 1'b0, 1'b0);

        // TEST 3: Validation failure
        validation_ok = 1'b0;

        issue_start();
        check_outputs("START -> CHECK before failure", 1'b1, 1'b0, 1'b0, 1'b0);

        @(posedge clk);
        #1;
        check_outputs("validation_ok=0 -> ERROR", 1'b0, 1'b0, 1'b1, 1'b0);

        repeat (2) @(posedge clk);
        #1;
        check_outputs("ERROR hold", 1'b0, 1'b0, 1'b1, 1'b0);

        issue_clear();
        check_outputs("CLEAR from ERROR -> IDLE", 1'b0, 1'b0, 1'b0, 1'b0);

        // TEST 4: Compute error during RUN
        validation_ok = 1'b1;

        issue_start();
        @(posedge clk);
        #1;
        check_outputs("Entered RUN", 1'b1, 1'b0, 1'b0, 1'b1);

        issue_compute_error();
        check_outputs("compute_error -> ERROR", 1'b0, 1'b0, 1'b1, 1'b0);

        issue_clear();
        check_outputs("CLEAR after compute error -> IDLE", 1'b0, 1'b0, 1'b0, 1'b0);

        // TEST 5: compute_error priority over compute_done
        validation_ok = 1'b1;

        issue_start();
        @(posedge clk);
        #1;
        check_outputs("RUN before simultaneous done/error", 1'b1, 1'b0, 1'b0, 1'b1);

        @(negedge clk);
        compute_done  = 1'b1;
        compute_error = 1'b1;

        @(posedge clk);
        #1;
        check_outputs("compute_error priority", 1'b0, 1'b0, 1'b1, 1'b0);

        @(negedge clk);
        compute_done  = 1'b0;
        compute_error = 1'b0;

        issue_clear();
        check_outputs("Final CLEAR -> IDLE", 1'b0, 1'b0, 1'b0, 1'b0);

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

        $display(" VCD: tb_accelerator_controller.vcd");
        $display("==============================================");

        repeat (3) @(posedge clk);
        $finish;
    end

endmodule
