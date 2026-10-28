`timescale 1ns/1ps

// Legacy LED-only wrapper retained for simulation/bring-up. Firmware is now
// loaded through the same onboard-UART boot protocol as the main board top.
module riscv_ai_fpga_top #(
    parameter integer DMEM_WORDS = 4096
)(
    input  wire        sys_clk,
    input  wire        reset_n,
    input  wire        uart_rx,
    output wire        uart_tx,

    output wire        led_busy,
    output wire        led_done,
    output wire        led_error,
    output wire        cpu_trap
);
    // The current single-cycle CPU/accelerator critical path does not meet
    // the raw 27 MHz board clock.  Use the device's global clock divider so
    // the SoC runs at 27/5 = 5.4 MHz with a proper clock network.
    wire soc_clk;
    CLKDIV u_clkdiv (
        .HCLKIN(sys_clk),
        .RESETN(reset_n),
        .CALIB(1'b0),
        .CLKOUT(soc_clk)
    );
    defparam u_clkdiv.DIV_MODE = "5";

    reg [1:0] reset_sync;
    always @(posedge soc_clk or negedge reset_n) begin
        if (!reset_n)
            reset_sync <= 2'b11;
        else
            reset_sync <= {reset_sync[0], 1'b0};
    end
    wire rst = reset_sync[1];

    wire [31:0] dbg_pc;
    wire [31:0] dbg_instr;
    wire [31:0] cpu_trap_pc;
    wire [31:0] cpu_trap_cause;
    wire [31:0] dbg_error_code;
    wire [31:0] dbg_input_count;
    wire [31:0] dbg_weight_count;
    wire [31:0] dbg_output_count;
    wire [31:0] dbg_output_read_index;
    wire        accel_busy;
    wire        accel_done;
    wire        accel_error;
    wire        trap_status;
    wire        boot_active;
    wire        boot_error;
    wire [31:0] result_data_unused;
    wire        result_valid_unused;

    // Tang Nano 20K onboard LEDs are active-low.
    assign led_busy  = ~(boot_active | accel_busy);
    assign led_done  = ~accel_done;
    assign led_error = ~((boot_active & boot_error) | accel_error);
    assign cpu_trap  = ~trap_status;

    riscv_ai_soc #(
        .IMEM_WORDS(256),
        .DMEM_WORDS(DMEM_WORDS)
    ) u_soc (
        .clk(soc_clk),
        .rst(rst),
        .uart_rx_i(uart_rx),
        .uart_tx_o(uart_tx),
        .sd_clk_o(),
        .sd_cs_n_o(),
        .sd_mosi_o(),
        .sd_miso_i(1'b1),
        .ui_selected_sample_i(7'd0),
        .ui_run_toggle_i(1'b0),
        .ui_hdmi_locked_i(1'b0),
        .reload_request_o(),
        .dbg_pc(dbg_pc),
        .dbg_instr(dbg_instr),
        .cpu_trap(trap_status),
        .cpu_trap_pc(cpu_trap_pc),
        .cpu_trap_cause(cpu_trap_cause),
        .dbg_accel_busy(accel_busy),
        .dbg_accel_done(accel_done),
        .dbg_accel_error(accel_error),
        .dbg_accel_error_code(dbg_error_code),
        .dbg_input_count(dbg_input_count),
        .dbg_weight_count(dbg_weight_count),
        .dbg_output_count(dbg_output_count),
        .dbg_output_read_index(dbg_output_read_index),
        .dbg_uart_rx_valid(),
        .dbg_uart_tx_ready(),
        .dbg_uart_overrun(),
        .dbg_uart_framing_error(),
        .dbg_boot_active(boot_active),
        .dbg_boot_error(boot_error),
        .dbg_boot_imem_words(),
        .dbg_boot_dmem_words(),
        .prediction(),
        .prediction_sample_id(),
        .prediction_valid(),
        .display_image_bits(),
        .display_image_valid(),
        .stream_out_data(result_data_unused),
        .stream_out_valid(result_valid_unused),
        .stream_out_ready(1'b1)
    );
endmodule
