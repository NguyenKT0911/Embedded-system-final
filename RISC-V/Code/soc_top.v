`timescale 1ns / 1ps

module soc_top(
    input wire clk,
    output wire uart_tx_pin,
    input wire uart_rx_pin
);

    // =====================================
    // 1. POWER-ON RESET AND AUTOMATIC START
    // =====================================
    // Hold the design in reset for 100 ms after FPGA configuration.
    // Gowin FPGA register initialization supplies the initial values.
    reg [21:0] powerup_count = 22'd0;
    reg powerup_done = 1'b0;
    wire system_reset;
    wire cpu_reset;
    wire program_loaded;

    always @(posedge clk) begin
        if (!powerup_done) begin
            if (powerup_count == 22'd2_699_999)
                powerup_done <= 1'b1;
            else
                powerup_count <= powerup_count + 1'b1;
        end
    end

    assign system_reset = !powerup_done;
    // Keep the CPU stopped while waiting for UART data and during loading.
    assign cpu_reset = system_reset || !program_loaded;


    // =====================================
    // 2. UART RECEIVER
    // =====================================

    wire [7:0] uart_data;
    wire uart_valid;

    uart_rx #(
        .CLKS_PER_BIT(234)
    ) rx0 (
        .clk(clk),
        .reset(system_reset),
        .rx(uart_rx_pin),
        .data(uart_data),
        .data_valid(uart_valid)
    );


    // =====================================
    // 3. UART PROGRAM LOADER
    // =====================================

    wire        loader_we;
    wire [7:0]  loader_addr;
    wire [31:0] loader_data;

    uart_loader loader0 (
        .clk(clk),
        .reset(system_reset),

        .rx_data(uart_data),
        .rx_valid(uart_valid),

        .loader_we(loader_we),
        .loader_addr(loader_addr),
        .loader_data(loader_data),
        .program_loaded(program_loaded)
    );
    // =====================================
    // 4. MEMORY INTERFACE
    // =====================================

    wire [31:0] mem_addr;
    wire [31:0] mem_write_data;
    wire [31:0] mem_read_data;

    wire [31:0] ram_read_data;
    wire       mem_write;
    wire [2:0] mem_funct3;
    
    // =====================================
    // 5. MEMORY ADDRESS DECODER
    // =====================================
    localparam UART_TX_ADDR     = 32'h1000_0000; // Ghi byte can truyen
    localparam UART_STATUS_ADDR = 32'h1000_0004;
    localparam RAM_BASE = 32'h0000_0000;
    localparam RAM_END  = 32'h0000_03FF;
    
    wire ram_select;
    wire ram_write;
    wire uart_write;
    wire uart_status_read;

    assign ram_select = (mem_addr >= RAM_BASE) &&
                        (mem_addr <= RAM_END);

    assign ram_write = mem_write && ram_select;

    assign uart_write = mem_write &&
                        (mem_addr == UART_TX_ADDR);
    assign uart_status_read = (mem_addr == UART_STATUS_ADDR);
    // =====================================
    // 6. UART TX CONTROLLER
    // =====================================

    // Tín hiệu truyền UART
    reg [7:0] tx_data;
    reg tx_start;

    wire tx_busy;
    wire tx_done;

    // Phát hiện một lần ghi mới
    reg uart_write_prev;
    
    wire tx_ready; // cho uart tx nhan
    assign tx_ready = !tx_busy && !tx_start && !cpu_reset;

    always @(posedge clk or posedge cpu_reset) begin
        if (cpu_reset) begin
            tx_data         <= 8'd0;
            tx_start        <= 1'b0;
            uart_write_prev <= 1'b0;
        end
        else begin
            tx_start <= 1'b0;
            uart_write_prev <= uart_write;
            if (uart_write &&
                !uart_write_prev &&
                tx_ready) begin

                tx_data  <= mem_write_data[7:0];
                tx_start <= 1'b1;
            end
        end
    end

    uart_tx #(
        .CLKS_PER_BIT(234)
    ) tx0 (
        .clk(clk),
        .reset(cpu_reset),

        .tx_data(tx_data),
        .tx_start(tx_start),

        .tx(uart_tx_pin),
        .tx_busy(tx_busy),
        .tx_done(tx_done)
    );

    // =====================================
    // 7. MEMORY READ MULTIPLEXER
    // =====================================

    // UART_STATUS:
    // Bit 0 = TX_READY
    // Bits 31:1 = 0

    assign mem_read_data =
        uart_status_read ? {31'd0, tx_ready}
            : ram_select ? ram_read_data
            : 32'd0;


    // =====================================
    // 8. RISC-V CPU
    // =====================================

    ricsv_cpu cpu0 (
        .clk(clk),
        .reset(cpu_reset),

        .mem_read_data(mem_read_data),

        .mem_addr(mem_addr),
        .mem_write_data(mem_write_data),
        .mem_write(mem_write),
        .mem_funct3(mem_funct3),

        .loader_addr(loader_addr),
        .loader_data(loader_data),
        .loader_we(loader_we),

        .debug_pc()
    );


    // =====================================
    // 9. DATA MEMORY
    // =====================================

    data_memory dm0 (
        .clk(clk),
        .mem_write(ram_write),
        .address(mem_addr),
        .write_data(mem_write_data),
        .read_data(ram_read_data),
        .funct3(mem_funct3)
    );

endmodule
