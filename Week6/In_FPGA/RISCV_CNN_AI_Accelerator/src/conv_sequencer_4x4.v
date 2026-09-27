`timescale 1ns/1ps

module conv_sequencer_4x4 (
    // ============================================================
    // Clock / Reset / Clear
    // ============================================================
    input  wire        clk,
    input  wire        rst,
    input  wire        clear,

    // ============================================================
    // Command
    // ============================================================
    input  wire        start,

    // ============================================================
    // Convolution Configuration
    //
    // Configuration is assumed to have already passed the
    // accelerator validation block before START is accepted.
    // ============================================================
    input  wire [15:0] cin,
    input  wire [15:0] cout,
    input  wire [7:0]  kernel_size,

    input  wire [15:0] out_h,
    input  wire [15:0] out_w,

    // ============================================================
    // Datapath Handshake
    // ============================================================
    input  wire        step_busy,
    input  wire        step_done,

    output reg         start_step,
    output reg         clear_acc,

    // ============================================================
    // Output-Tile Handshake
    //
    // tile_ready = current 4x4 accumulator tile is complete.
    // tile_accept = downstream output path has captured the tile.
    //
    // The sequencer MUST wait here so the PE accumulators are not
    // cleared before their results are stored.
    // ============================================================
    output reg         tile_ready,
    input  wire        tile_accept,

    // ============================================================
    // Current Convolution Indices
    //
    // One PE-array tile represents:
    //   4 output positions along W
    //   x
    //   4 output channels
    // ============================================================
    output reg  [15:0] oh,
    output reg  [15:0] ow_base,
    output reg  [15:0] oc_base,

    output reg  [15:0] ic,
    output reg  [7:0]  kh,
    output reg  [7:0]  kw,

    // ============================================================
    // Sequencer Status
    // ============================================================
    output reg         busy,
    output reg         done
);

    // ============================================================
    // FSM States
    // ============================================================
    localparam [2:0] IDLE       = 3'd0;
    localparam [2:0] CLEAR_TILE = 3'd1;
    localparam [2:0] ISSUE_STEP = 3'd2;
    localparam [2:0] WAIT_STEP  = 3'd3;
    localparam [2:0] TILE_READY = 3'd4;
    localparam [2:0] DONE       = 3'd5;

    reg [2:0] state;
    reg [2:0] next_state;

    // ============================================================
    // State Register + Index Counters
    // ============================================================
    always @(posedge clk) begin

        if (rst) begin

            state   <= IDLE;

            oh      <= 16'd0;
            ow_base <= 16'd0;
            oc_base <= 16'd0;

            ic      <= 16'd0;
            kh      <= 8'd0;
            kw      <= 8'd0;

        end
        else if (clear) begin

            state   <= IDLE;

            oh      <= 16'd0;
            ow_base <= 16'd0;
            oc_base <= 16'd0;

            ic      <= 16'd0;
            kh      <= 8'd0;
            kw      <= 8'd0;

        end
        else begin

            state <= next_state;

            case (state)

                // ------------------------------------------------
                // New convolution starts from the first tile.
                // ------------------------------------------------
                IDLE: begin

                    if (start) begin

                        oh      <= 16'd0;
                        ow_base <= 16'd0;
                        oc_base <= 16'd0;

                        ic      <= 16'd0;
                        kh      <= 8'd0;
                        kw      <= 8'd0;

                    end

                end

                // ------------------------------------------------
                // A completed datapath step corresponds to one
                // (ic, kh, kw) contribution.
                //
                // Loop order inside one tile:
                //   kw -> kh -> ic
                // ------------------------------------------------
                WAIT_STEP: begin

                    if (step_done) begin

                        if ((kw + 1'b1) < kernel_size) begin

                            kw <= kw + 1'b1;

                        end
                        else begin

                            kw <= 8'd0;

                            if ((kh + 1'b1) < kernel_size) begin

                                kh <= kh + 1'b1;

                            end
                            else begin

                                kh <= 8'd0;

                                if ((ic + 1'b1) < cin) begin

                                    ic <= ic + 1'b1;

                                end

                            end

                        end

                    end

                end

                // ------------------------------------------------
                // Current output tile has been captured.
                //
                // Tile traversal order:
                //   ow_base -> oh -> oc_base
                //
                // Each new tile restarts ic/kh/kw from zero.
                // ------------------------------------------------
                TILE_READY: begin

                    if (tile_accept) begin

                        ic <= 16'd0;
                        kh <= 8'd0;
                        kw <= 8'd0;

                        // Next 4 output positions in same row.
                        if ((ow_base + 16'd4) < out_w) begin

                            ow_base <= ow_base + 16'd4;

                        end
                        else begin

                            ow_base <= 16'd0;

                            // Next output row.
                            if ((oh + 1'b1) < out_h) begin

                                oh <= oh + 1'b1;

                            end
                            else begin

                                oh <= 16'd0;

                                // Next 4 output channels.
                                if ((oc_base + 16'd4) < cout) begin

                                    oc_base <= oc_base + 16'd4;

                                end

                            end

                        end

                    end

                end

                default: begin
                    // Counters hold their current values.
                end

            endcase

        end

    end

    // ============================================================
    // Next-State Logic
    // ============================================================
    always @(*) begin

        next_state = state;

        case (state)

            // ----------------------------------------------------
            // Wait for START.
            // ----------------------------------------------------
            IDLE: begin

                if (start)
                    next_state = CLEAR_TILE;

            end

            // ----------------------------------------------------
            // Clear all 16 PE accumulators for one clock.
            // ----------------------------------------------------
            CLEAR_TILE: begin

                next_state = ISSUE_STEP;

            end

            // ----------------------------------------------------
            // Issue exactly one datapath request when it is free.
            // ----------------------------------------------------
            ISSUE_STEP: begin

                if (!step_busy)
                    next_state = WAIT_STEP;

            end

            // ----------------------------------------------------
            // Wait until feeder + PE step reaches its consume edge.
            //
            // If this was the final (ic,kh,kw), the tile is ready.
            // Otherwise issue the next kernel/channel step.
            // ----------------------------------------------------
            WAIT_STEP: begin

                if (step_done) begin

                    if (
                        (kw == (kernel_size - 1'b1)) &&
                        (kh == (kernel_size - 1'b1)) &&
                        (ic == (cin - 1'b1))
                    )
                        next_state = TILE_READY;
                    else
                        next_state = ISSUE_STEP;

                end

            end

            // ----------------------------------------------------
            // Hold completed accumulator tile until downstream
            // output logic confirms that it has stored the result.
            // ----------------------------------------------------
            TILE_READY: begin

                if (tile_accept) begin

                    if (
                        ((ow_base + 16'd4) >= out_w) &&
                        ((oh + 1'b1) >= out_h) &&
                        ((oc_base + 16'd4) >= cout)
                    )
                        next_state = DONE;
                    else
                        next_state = CLEAR_TILE;

                end

            end

            // ----------------------------------------------------
            // Hold DONE until CLEAR.
            // ----------------------------------------------------
            DONE: begin

                next_state = DONE;

            end

            default: begin

                next_state = IDLE;

            end

        endcase

    end

    // ============================================================
    // Moore-Style Output Logic
    // ============================================================
    always @(*) begin

        start_step = 1'b0;
        clear_acc  = 1'b0;
        tile_ready = 1'b0;

        busy       = 1'b0;
        done       = 1'b0;

        case (state)

            IDLE: begin
                busy = 1'b0;
            end

            CLEAR_TILE: begin
                busy      = 1'b1;
                clear_acc = 1'b1;
            end

            ISSUE_STEP: begin
                busy = 1'b1;

                if (!step_busy)
                    start_step = 1'b1;
            end

            WAIT_STEP: begin
                busy = 1'b1;
            end

            TILE_READY: begin
                busy       = 1'b1;
                tile_ready = 1'b1;
            end

            DONE: begin
                busy = 1'b0;
                done = 1'b1;
            end

            default: begin
                busy = 1'b0;
            end

        endcase

    end

endmodule
