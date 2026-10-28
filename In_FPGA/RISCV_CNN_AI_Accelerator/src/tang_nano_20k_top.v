`timescale 1ns/1ps

// Tang Nano 20K UART-boot integration:
//   * the onboard BL616 UART loads RV32I IMEM and DMEM; no INIT_FILE is used
//   * the loaded firmware reads model/images from the onboard TF slot
//   * S2 selects one of 100 stored samples; S1 starts its inference
//   * HDMI shows the actual input image, sample number, prediction/confidence
module tang_nano_20k_top #(
    parameter integer IMEM_WORDS = 2048,
    parameter integer DMEM_WORDS = 2048,
    parameter [3:0] DEFAULT_DIGIT = 4'd0
)(
    input  wire sys_clk,
    input  wire run_btn,       // S1: run selected digit, active high
    input  wire digit_btn,     // S2: select next sample 00..99, active high
    input  wire uart_boot_btn, // External button: pin 72 to 3V3, active high
    input  wire uart_rx,
    output wire uart_tx,

    output wire sd_clk,
    output wire sd_cmd,
    input  wire sd_dat0,
    output wire sd_dat1,
    output wire sd_dat2,
    output wire sd_dat3,

    output wire led_busy,      // Pin 15: accelerator busy
    output wire led_done,      // Pin 16: accelerator done
    output wire led_error,     // Pin 17: accelerator error
    output wire cpu_trap,      // Pin 18: CPU trap
    output wire led_heartbeat, // Pin 19: FPGA heartbeat
    output wire led_hdmi,      // Pin 20: HDMI PLL lock

    output wire       tmds_clk_p,
    output wire       tmds_clk_n,
    output wire [2:0] tmds_d_p,
    output wire [2:0] tmds_d_n
);

    // Deterministic power-on reset.
    reg [15:0] por_count = 16'd0;
    always @(posedge sys_clk) begin
        if (!(&por_count))
            por_count <= por_count + 16'd1;
    end
    wire por_reset = !(&por_count);

    // The dedicated external UART button is independent of S1/S2. Holding it
    // for 0.5 s resets only the SoC and returns UART ownership to the loader.
    reg [2:0]  boot_btn_sync;
    reg [24:0] reload_hold_count;
    reg        reload_armed;
    reg        reload_pulse;
    always @(posedge sys_clk) begin
        // Do not re-arm the detector on reload_pulse.  Re-arming while the
        // button is still held high would generate another SoC reset every
        // 0.5 s and continuously return the CPU to the UART loader.
        if (por_reset) begin
            boot_btn_sync     <= 3'b000;
            reload_hold_count <= 25'd0;
            reload_armed      <= 1'b1;
            reload_pulse      <= 1'b0;
        end else begin
            boot_btn_sync <= {boot_btn_sync[1:0], uart_boot_btn};
            reload_pulse <= 1'b0;
            if (boot_btn_sync[2]) begin
                if (reload_armed && (reload_hold_count == 25'd13_499_999)) begin
                    reload_pulse <= 1'b1;
                    reload_armed <= 1'b0;
                end else if (reload_armed) begin
                    reload_hold_count <= reload_hold_count + 1'b1;
                end
            end else begin
                reload_hold_count <= 25'd0;
                reload_armed      <= 1'b1;
            end
        end
    end
    // A UART reload resets only the SoC and user controls.  Stretch the request
    // in the 27 MHz domain so the slower 5.4 MHz SoC cannot miss a one-cycle
    // button pulse.  The clock divider and HDMI PLL stay running.
    wire software_reload;
    reg [7:0] button_reset_stretch;
    always @(posedge sys_clk) begin
        if (por_reset)
            button_reset_stretch <= 8'hff;
        else if (reload_pulse)
            button_reset_stretch <= 8'hff;
        else if (button_reset_stretch != 8'd0)
            button_reset_stretch <= button_reset_stretch - 1'b1;
    end
    wire ui_reset = por_reset | (button_reset_stretch != 8'd0);
    // software_reload is generated in the SoC clock domain and is therefore
    // consumed synchronously below; keeping it out of the 27 MHz UI logic
    // avoids a cross-domain timing path.

    // 27 MHz / 5 = 5.4 MHz CPU/accelerator clock.
    wire soc_clk;
    CLKDIV u_soc_clkdiv (
        .HCLKIN(sys_clk),
        .RESETN(~por_reset),
        .CALIB(1'b0),
        .CLKOUT(soc_clk)
    );
    defparam u_soc_clkdiv.DIV_MODE = "5";
    defparam u_soc_clkdiv.GSREN = "false";

    reg [2:0] soc_reset_sync;
    always @(posedge soc_clk or posedge ui_reset) begin
        if (ui_reset || software_reload)
            soc_reset_sync <= 3'b111;
        else
            soc_reset_sync <= {soc_reset_sync[1:0], 1'b0};
    end
    wire soc_rst = soc_reset_sync[2];

    // S2 debounce in the 27 MHz domain. Both board buttons idle low.
    reg [2:0]  button_sync;
    reg        button_stable;
    reg        button_stable_d;
    reg [18:0] debounce_count;
    always @(posedge sys_clk) begin
        if (ui_reset) begin
            button_sync     <= 3'b000;
            button_stable   <= 1'b0;
            button_stable_d <= 1'b0;
            debounce_count  <= 19'd0;
        end else begin
            button_sync     <= {button_sync[1:0], digit_btn};
            button_stable_d <= button_stable;
            if (button_sync[2] == button_stable) begin
                debounce_count <= 19'd0;
            end else if (debounce_count == 19'd269_999) begin
                button_stable  <= button_sync[2];
                debounce_count <= 19'd0;
            end else begin
                debounce_count <= debounce_count + 19'd1;
            end
        end
    end
    wire button_pressed = button_stable & ~button_stable_d;

    // Holding S2 for 0.5 s auto-advances every 0.1 s, so any of the 100
    // samples can be reached quickly without adding another control device.
    reg [23:0] button_hold_count;
    reg        button_repeat;
    always @(posedge sys_clk) begin
        if (ui_reset) begin
            button_hold_count <= 24'd0;
            button_repeat     <= 1'b0;
        end else begin
            button_repeat <= 1'b0;
            if (!button_stable || button_pressed) begin
                button_hold_count <= 24'd0;
            end else if (button_hold_count == 24'd13_499_999) begin
                button_hold_count <= 24'd10_800_000;
                button_repeat <= 1'b1;
            end else begin
                button_hold_count <= button_hold_count + 24'd1;
            end
        end
    end
    wire sample_advance = button_pressed | button_repeat;

    // S1 debounce. Each release starts one inference; Loader control is on the
    // separate pin-72 button, so S1 never changes the UART mode.
    reg [2:0]  run_sync;
    reg        run_stable;
    reg        run_stable_d;
    reg [18:0] run_debounce_count;
    always @(posedge sys_clk) begin
        if (ui_reset) begin
            run_sync           <= 3'b000;
            run_stable         <= 1'b0;
            run_stable_d       <= 1'b0;
            run_debounce_count <= 19'd0;
        end else begin
            run_sync     <= {run_sync[1:0], run_btn};
            run_stable_d <= run_stable;
            if (run_sync[2] == run_stable) begin
                run_debounce_count <= 19'd0;
            end else if (run_debounce_count == 19'd269_999) begin
                run_stable         <= run_sync[2];
                run_debounce_count <= 19'd0;
            end else begin
                run_debounce_count <= run_debounce_count + 19'd1;
            end
        end
    end
    wire run_released = ~run_stable & run_stable_d;

    reg [6:0] selected_sample;
    reg [6:0] shuffle_position;
    reg [6:0] shuffle_step;
    reg [6:0] shuffle_lfsr;
    reg       run_toggle;
    wire [6:0] boot_run_sample;
    wire       boot_cpu_released;
    reg  [6:0] boot_run_sample_meta;
    reg  [6:0] boot_run_sample_sys;
    reg  [2:0] boot_release_sys;
    always @(posedge sys_clk) begin
        if (ui_reset) begin
            boot_run_sample_meta <= 7'd0;
            boot_run_sample_sys  <= 7'd0;
            boot_release_sys     <= 3'b000;
        end else begin
            boot_run_sample_meta <= boot_run_sample;
            boot_run_sample_sys  <= boot_run_sample_meta;
            boot_release_sys     <= {boot_release_sys[1:0], boot_cpu_released};
        end
    end
    wire boot_started = boot_release_sys[1] & ~boot_release_sys[2];
    always @(posedge sys_clk) begin
        if (ui_reset) begin
            selected_sample <= 7'd0;
            shuffle_position <= 7'd0;
            shuffle_step     <= 7'd7;
            shuffle_lfsr     <= 7'h5d;
            run_toggle       <= 1'b0;
        end else begin
            // CMD_RUN carries the sample requested by the PC.  Selecting it
            // here makes "replace image and run" deterministic instead of
            // requiring up to 100 S2 presses after the UART reload.
            if (boot_started) begin
                selected_sample  <= boot_run_sample_sys;
                shuffle_position <= 7'd0;
            end else if (sample_advance) begin
                // A step coprime with 100 visits every slot exactly once.
                // At the cycle boundary choose a new offset and step.
                if (shuffle_position == 7'd99) begin
                    shuffle_lfsr <= {shuffle_lfsr[5:0],
                                     shuffle_lfsr[6] ^ shuffle_lfsr[5]};
                    selected_sample <= (shuffle_lfsr < 7'd100)
                                     ? shuffle_lfsr : shuffle_lfsr - 7'd100;
                    case (shuffle_lfsr[1:0])
                        2'd0: shuffle_step <= 7'd3;
                        2'd1: shuffle_step <= 7'd7;
                        2'd2: shuffle_step <= 7'd9;
                        default: shuffle_step <= 7'd11;
                    endcase
                    shuffle_position <= 7'd0;
                end else begin
                    selected_sample <= (selected_sample + shuffle_step >= 7'd100)
                                     ? selected_sample + shuffle_step - 7'd100
                                     : selected_sample + shuffle_step;
                    shuffle_position <= shuffle_position + 1'b1;
                end
            end
            if (run_released)
                run_toggle <= ~run_toggle;
        end
    end

    // Stable multi-cycle controls crossing into the 5.4 MHz SoC domain.
    reg [6:0] selected_sample_meta;
    reg [6:0] selected_sample_soc;
    reg [1:0] run_toggle_soc;
    reg [1:0] hdmi_locked_soc;
    always @(posedge soc_clk) begin
        if (soc_rst) begin
            selected_sample_meta <= 7'd0;
            selected_sample_soc  <= 7'd0;
            run_toggle_soc      <= 2'b00;
            hdmi_locked_soc     <= 2'b00;
        end else begin
            selected_sample_meta <= selected_sample;
            selected_sample_soc  <= selected_sample_meta;
            run_toggle_soc      <= {run_toggle_soc[0], run_toggle};
            hdmi_locked_soc     <= {hdmi_locked_soc[0], hdmi_locked};
        end
    end

    wire        accel_busy;
    wire        accel_done;
    wire        accel_error;
    wire        trap_status;
    wire        boot_active;
    wire        boot_error;
    wire        hdmi_locked;
    wire [15:0] boot_imem_words;
    wire [15:0] boot_dmem_words;
    wire [3:0]  soc_prediction;
    wire [31:0] soc_prediction_sample_id;
    wire        soc_prediction_valid;
    wire [799:0] soc_display_image_bits;
    wire         soc_display_image_valid;
    wire [31:0] unused_result_data;
    wire        unused_result_valid;

    // The bootloader owns UART until it has received IMEM, DMEM and RUN.
    // Afterwards the loaded firmware owns UART and accesses the SD controller.
    riscv_ai_soc #(
        .IMEM_WORDS(IMEM_WORDS),
        .DMEM_WORDS(DMEM_WORDS),
        .CLK_FREQ(5_400_000),
        .BAUD_RATE(115200)
    ) u_soc (
        .clk(soc_clk),
        .rst(soc_rst),
        .uart_rx_i(uart_rx),
        .uart_tx_o(uart_tx),
        .sd_clk_o(sd_clk),
        .sd_cs_n_o(sd_dat3),
        .sd_mosi_o(sd_cmd),
        .sd_miso_i(sd_dat0),
        .ui_selected_sample_i(selected_sample_soc),
        .ui_run_toggle_i(run_toggle_soc[1]),
        .ui_hdmi_locked_i(hdmi_locked_soc[1]),
        .reload_request_o(software_reload),
        .dbg_pc(),
        .dbg_instr(),
        .cpu_trap(trap_status),
        .cpu_trap_pc(),
        .cpu_trap_cause(),
        .dbg_accel_busy(accel_busy),
        .dbg_accel_done(accel_done),
        .dbg_accel_error(accel_error),
        .dbg_accel_error_code(),
        .dbg_input_count(),
        .dbg_weight_count(),
        .dbg_output_count(),
        .dbg_output_read_index(),
        .dbg_uart_rx_valid(),
        .dbg_uart_tx_ready(),
        .dbg_uart_overrun(),
        .dbg_uart_framing_error(),
        .dbg_boot_active(boot_active),
        .dbg_boot_error(boot_error),
        .dbg_boot_imem_words(boot_imem_words),
        .dbg_boot_dmem_words(boot_dmem_words),
        .boot_run_sample(boot_run_sample),
        .boot_cpu_released(boot_cpu_released),
        .prediction(soc_prediction),
        .prediction_sample_id(soc_prediction_sample_id),
        .prediction_valid(soc_prediction_valid),
        .display_image_bits(soc_display_image_bits),
        .display_image_valid(soc_display_image_valid),
        .stream_out_data(unused_result_data),
        .stream_out_valid(unused_result_valid),
        .stream_out_ready(1'b1)
    );

    // Unused SD data pins must stay high while the socket is used in SPI mode.
    assign sd_dat1 = 1'b1;
    assign sd_dat2 = 1'b1;

    // Safe SoC-to-video-domain handoff. The result registers are written
    // before prediction_valid pulses, so the two-stage data synchronizer has
    // ample settling time before the pulse reaches this domain.
    reg [3:0] prediction_meta;
    reg [3:0] prediction_sync;
    reg [6:0] confidence_meta;
    reg [6:0] confidence_sync;
    reg [6:0] result_sample_meta;
    reg [6:0] result_sample_sync;
    reg       prediction_valid_meta;
    reg       prediction_valid_sync;
    reg       image_valid_meta;
    reg       image_valid_sync;
    always @(posedge sys_clk) begin
        if (ui_reset) begin
            prediction_meta       <= DEFAULT_DIGIT;
            prediction_sync       <= DEFAULT_DIGIT;
            confidence_meta       <= 7'd0;
            confidence_sync       <= 7'd0;
            result_sample_meta    <= 7'd0;
            result_sample_sync    <= 7'd0;
            prediction_valid_meta <= 1'b0;
            prediction_valid_sync <= 1'b0;
            image_valid_meta      <= 1'b0;
            image_valid_sync      <= 1'b0;
        end else begin
            prediction_meta       <= soc_prediction;
            prediction_sync       <= prediction_meta;
            confidence_meta       <= soc_prediction_sample_id[6:0];
            confidence_sync       <= confidence_meta;
            result_sample_meta    <= soc_prediction_sample_id[14:8];
            result_sample_sync    <= result_sample_meta;
            prediction_valid_meta <= soc_prediction_valid;
            prediction_valid_sync <= prediction_valid_meta;
            image_valid_meta      <= soc_display_image_valid;
            image_valid_sync      <= image_valid_meta;
        end
    end

    reg [3:0] active_digit;
    reg [6:0] active_confidence;
    reg       confidence_valid;
    always @(posedge sys_clk) begin
        if (ui_reset) begin
            active_digit <= DEFAULT_DIGIT;
            active_confidence <= 7'd0;
            confidence_valid <= 1'b0;
        end else if (sample_advance || boot_started) begin
            // Hide the previous image/result as soon as another slot is
            // selected.  A blocking inference may still finish afterwards,
            // but its tagged result must not be shown under the new IMG id.
            confidence_valid <= 1'b0;
        end else if (prediction_valid_sync
                     && result_sample_sync == selected_sample) begin
            active_digit <= prediction_sync;
            active_confidence <= (confidence_sync > 7'd100) ? 7'd100 : confidence_sync;
            confidence_valid <= 1'b1;
        end
    end

    hdmi_top u_hdmi (
        .sys_clk(sys_clk),
        .rst(por_reset),
        .prediction(active_digit),
        .confidence(active_confidence),
        .confidence_valid(confidence_valid),
        .sample_index(selected_sample),
        .image_bits(soc_display_image_bits),
        // Firmware deasserts image_valid while loading a new preview and
        // asserts it again only after all 28x28 bits are stable.
        .image_valid(image_valid_sync),
        .hdmi_locked(hdmi_locked),
        .tmds_clk_p(tmds_clk_p),
        .tmds_clk_n(tmds_clk_n),
        .tmds_d_p(tmds_d_p),
        .tmds_d_n(tmds_d_n)
    );

    reg [24:0] heartbeat_count;
    always @(posedge sys_clk) begin
        if (ui_reset)
            heartbeat_count <= 25'd0;
        else
            heartbeat_count <= heartbeat_count + 25'd1;
    end

    // All six onboard LEDs are active low.
    assign led_busy      = ~(boot_active | accel_busy);
    assign led_done      = ~accel_done;
    // A stale framing/checksum fault from the loading phase must not look like
    // a runtime CNN failure after RUN has released the CPU.
    assign led_error     = ~((boot_active & boot_error) | accel_error);
    assign cpu_trap      = ~trap_status;
    assign led_heartbeat = ~heartbeat_count[24];
    assign led_hdmi      = ~hdmi_locked;

endmodule
