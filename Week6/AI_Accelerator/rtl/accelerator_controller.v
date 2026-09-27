`timescale 1ns/1ps

module accelerator_controller (
    // Clock and Reset
    input  wire clk,
    input  wire rst,

    // Commands from MMIO
    input  wire start_pulse,
    input  wire clear_pulse,

    // Validation Result
    input  wire validation_ok,

    // Compute Core Status
    input  wire compute_done,
    input  wire compute_error,

    // Controller Status / Control Outputs
    output reg  busy,
    output reg  done,
    output reg  error,
    output reg  core_enable
);

    // State Encoding
    // IDLE  = 000
    // CHECK = 001
    // RUN   = 010
    // DONE  = 011
    // ERROR = 100

    localparam [2:0] IDLE  = 3'b000;
    localparam [2:0] CHECK = 3'b001;
    localparam [2:0] RUN   = 3'b010;
    localparam [2:0] DONE  = 3'b011;
    localparam [2:0] ERROR = 3'b100;

    reg [2:0] current_state;
    reg [2:0] next_state;

    // State Register
    // Synchronous active-high reset
    always @(posedge clk) begin
        if (rst)
            current_state <= IDLE;
        else
            current_state <= next_state;
    end

    // Next-State Logic
    always @(*) begin

        // Default behavior: remain in the current state.
        next_state = current_state;

        case (current_state)

            // IDLE
            // Wait for software START command.
            IDLE: begin
                if (start_pulse)
                    next_state = CHECK;
            end

            // CHECK
            // Validate configuration, data counts, and capacity.
            CHECK: begin
                if (validation_ok)
                    next_state = RUN;
                else
                    next_state = ERROR;
            end

            // RUN
            // compute_error has priority over compute_done.
            RUN: begin
                if (compute_error)
                    next_state = ERROR;
                else if (compute_done)
                    next_state = DONE;
            end

            // DONE
            // Hold DONE until software issues CLEAR.
            DONE: begin
                if (clear_pulse)
                    next_state = IDLE;
            end

            // ERROR
            // Hold ERROR until software issues CLEAR.
            ERROR: begin
                if (clear_pulse)
                    next_state = IDLE;
            end

            // Recovery from an illegal/unknown state.
            default: begin
                next_state = IDLE;
            end

        endcase
    end

    // Output Logic
    // Moore-style outputs: depend only on current_state.
    always @(*) begin
        // Safe defaults
        busy        = 1'b0;
        done        = 1'b0;
        error       = 1'b0;
        core_enable = 1'b0;

        case (current_state)

            IDLE: begin
                busy        = 1'b0;
                done        = 1'b0;
                error       = 1'b0;
                core_enable = 1'b0;
            end

            CHECK: begin
                busy        = 1'b1;
                done        = 1'b0;
                error       = 1'b0;
                core_enable = 1'b0;
            end

            RUN: begin
                busy        = 1'b1;
                done        = 1'b0;
                error       = 1'b0;
                core_enable = 1'b1;
            end

            DONE: begin
                busy        = 1'b0;
                done        = 1'b1;
                error       = 1'b0;
                core_enable = 1'b0;
            end

            ERROR: begin
                busy        = 1'b0;
                done        = 1'b0;
                error       = 1'b1;
                core_enable = 1'b0;
            end

            default: begin
                busy        = 1'b0;
                done        = 1'b0;
                error       = 1'b0;
                core_enable = 1'b0;
            end

        endcase
    end

endmodule
