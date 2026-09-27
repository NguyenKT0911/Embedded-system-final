`timescale 1ns/1ps

// Tang Nano 20K wrapper for a fixed Conv1/Conv2 demo image.
// The result stream is consumed internally for this LED-only hardware demo;
// a later UART wrapper can expose the computed values without using 32 GPIOs.
module riscv_ai_fpga_top #(
    parameter IMEM_INIT_FILE = "conv1_firmware.hex",
    parameter DMEM_INIT_FILE = "conv1_data.hex",
    parameter integer DMEM_WORDS = 4096
)(
    input  wire        sys_clk,
    input  wire        reset_n,

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
    wire [31:0] result_data_unused;
    wire        result_valid_unused;

    // Tang Nano 20K onboard LEDs are active-low.
    assign led_busy  = ~accel_busy;
    assign led_done  = ~accel_done;
    assign led_error = ~accel_error;
    assign cpu_trap  = ~trap_status;

    riscv_ai_soc #(
        .IMEM_WORDS(256),
        .DMEM_WORDS(DMEM_WORDS),
        .IMEM_INIT_FILE(IMEM_INIT_FILE),
        .DMEM_INIT_FILE(DMEM_INIT_FILE)
    ) u_soc (
        .clk(soc_clk),
        .rst(rst),
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
        .stream_out_data(result_data_unused),
        .stream_out_valid(result_valid_unused),
        .stream_out_ready(1'b1)
    );
endmodule
