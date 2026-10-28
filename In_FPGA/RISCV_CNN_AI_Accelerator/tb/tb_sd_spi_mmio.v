`timescale 1ns/1ps

module tb_sd_spi_mmio;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg [31:0] bus_addr = 32'd0;
    reg [31:0] bus_wdata = 32'd0;
    reg bus_re = 1'b0;
    reg bus_we = 1'b0;
    wire [31:0] bus_rdata;
    wire bus_hit;
    wire wait_o;
    wire sd_clk;
    wire sd_cs_n;
    wire sd_mosi;
    wire sd_miso = sd_mosi;

    always #5 clk = ~clk;

    sd_spi_mmio dut (
        .clk(clk), .rst(rst),
        .bus_addr(bus_addr), .bus_wdata(bus_wdata),
        .bus_re(bus_re), .bus_we(bus_we),
        .bus_rdata(bus_rdata), .bus_hit(bus_hit), .wait_o(wait_o),
        .sd_clk(sd_clk), .sd_cs_n(sd_cs_n),
        .sd_mosi(sd_mosi), .sd_miso(sd_miso)
    );

    task write_reg(input [31:0] address, input [31:0] value);
        begin
            @(negedge clk);
            bus_addr = address;
            bus_wdata = value;
            bus_we = 1'b1;
            @(negedge clk);
            bus_we = 1'b0;
        end
    endtask

    task read_reg(input [31:0] address, output [31:0] value);
        begin
            @(negedge clk);
            bus_addr = address;
            bus_re = 1'b1;
            #1 value = bus_rdata;
            @(negedge clk);
            bus_re = 1'b0;
        end
    endtask

    reg [31:0] value;
    integer timeout;
    initial begin
        repeat (4) @(posedge clk);
        rst = 1'b0;
        write_reg(32'h3000_0000, 32'd0);
        if (sd_cs_n !== 1'b0) $fatal(1, "CS_N did not assert");
        write_reg(32'h3000_000c, 32'd1);
        write_reg(32'h3000_0008, 32'h0000_00a5);

        timeout = 1000;
        value = 0;
        while ((value & 2) == 0 && timeout > 0) begin
            read_reg(32'h3000_0004, value);
            timeout = timeout - 1;
        end
        if (timeout == 0) $fatal(1, "SPI transfer timeout");
        read_reg(32'h3000_0008, value);
        if (value[7:0] !== 8'ha5)
            $fatal(1, "SPI loopback mismatch: %02x", value[7:0]);
        read_reg(32'h3000_0004, value);
        if ((value & 2) != 0) $fatal(1, "RX_VALID did not clear");
        write_reg(32'h3000_0000, 32'd1);
        if (sd_cs_n !== 1'b1) $fatal(1, "CS_N did not deassert");
        $display("RESULT: SD SPI MMIO TEST PASSED");
        $finish;
    end
endmodule
