`timescale 1ns/1ps

// UART bootloader for the fixed FPGA hardware image.
// Request (little-endian):
//   55 AA | CMD:u8 | BYTE_ADDRESS:u32 | LENGTH:u16 | PAYLOAD | CRC32:u32
// CRC32 is IEEE/zlib over CMD, ADDRESS, LENGTH and PAYLOAD.
// Commands: 01=WRITE_IMEM, 02=WRITE_DMEM, 03=RUN, 04=PING.
// Replies: 79=ACK, A5=PONG, 1F=NACK.
module uart_bootloader #(
    parameter integer CLK_FREQ    = 5_400_000,
    parameter integer BAUD_RATE   = 115200,
    parameter integer IMEM_WORDS  = 2048,
    parameter integer DMEM_WORDS  = 2048,
    parameter integer MAX_PAYLOAD = 256
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        uart_rx_i,
    output wire        uart_tx_o,
    output reg         imem_we,
    output reg  [15:0] imem_word_addr,
    output reg  [31:0] imem_write_data,
    output reg         dmem_we,
    output reg  [15:0] dmem_word_addr,
    output reg  [31:0] dmem_write_data,
    output reg         cpu_release,
    output reg  [6:0]  run_sample,
    output reg         active,
    output reg         error,
    output reg  [15:0] imem_write_count,
    output reg  [15:0] dmem_write_count
);
    localparam [7:0] SOF0 = 8'h55;
    localparam [7:0] SOF1 = 8'hAA;
    localparam [7:0] CMD_WRITE_IMEM = 8'h01;
    localparam [7:0] CMD_WRITE_DMEM = 8'h02;
    localparam [7:0] CMD_RUN = 8'h03;
    localparam [7:0] CMD_PING = 8'h04;
    localparam [7:0] RESPONSE_ACK = 8'h79;
    localparam [7:0] RESPONSE_PONG = 8'hA5;
    localparam [7:0] RESPONSE_NACK = 8'h1F;

    localparam [4:0] RX_SOF0 = 5'd0;
    localparam [4:0] RX_SOF1 = 5'd1;
    localparam [4:0] RX_CMD = 5'd2;
    localparam [4:0] RX_ADDR0 = 5'd3;
    localparam [4:0] RX_ADDR1 = 5'd4;
    localparam [4:0] RX_ADDR2 = 5'd5;
    localparam [4:0] RX_ADDR3 = 5'd6;
    localparam [4:0] RX_LEN0 = 5'd7;
    localparam [4:0] RX_LEN1 = 5'd8;
    localparam [4:0] RX_PAYLOAD = 5'd9;
    localparam [4:0] RX_CRC0 = 5'd10;
    localparam [4:0] RX_CRC1 = 5'd11;
    localparam [4:0] RX_CRC2 = 5'd12;
    localparam [4:0] RX_CRC3 = 5'd13;
    localparam [4:0] TX_ARM = 5'd14;
    localparam [4:0] TX_WAIT_BUSY = 5'd15;
    localparam [4:0] TX_WAIT_DONE = 5'd16;

    function [31:0] crc32_byte;
        input [31:0] crc_in;
        input [7:0] data_in;
        integer bit_index;
        reg [31:0] value;
        begin
            value = crc_in ^ data_in;
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1)
                value = value[0] ? ((value >> 1) ^ 32'hEDB8_8320)
                                 : (value >> 1);
            crc32_byte = value;
        end
    endfunction

    wire [7:0] rx_byte;
    wire rx_valid;
    wire rx_framing_error;
    reg [7:0] tx_data;
    reg tx_valid;
    wire tx_ready;
    reg [4:0] state;
    reg [7:0] command;
    reg [31:0] byte_address;
    reg [15:0] payload_length;
    reg [15:0] payload_index;
    reg [31:0] word_data;
    reg [31:0] crc;
    reg [31:0] received_crc;
    reg packet_valid;
    reg [7:0] response;
    reg run_after_response;

    uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_boot_rx (
        .clk(clk), .rst(rst), .rx(uart_rx_i), .data_out(rx_byte),
        .data_valid(rx_valid), .framing_error(rx_framing_error)
    );
    uart_tx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_boot_tx (
        .clk(clk), .rst(rst), .tx_data(tx_data), .tx_valid(tx_valid),
        .tx_ready(tx_ready), .tx(uart_tx_o)
    );

    always @(posedge clk) begin
        if (rst) begin
            state <= RX_SOF0;
            command <= 8'd0;
            byte_address <= 32'd0;
            payload_length <= 16'd0;
            payload_index <= 16'd0;
            word_data <= 32'd0;
            crc <= 32'hFFFF_FFFF;
            received_crc <= 32'd0;
            packet_valid <= 1'b0;
            response <= RESPONSE_NACK;
            run_after_response <= 1'b0;
            tx_data <= 8'd0;
            tx_valid <= 1'b0;
            imem_we <= 1'b0;
            imem_word_addr <= 16'd0;
            imem_write_data <= 32'd0;
            dmem_we <= 1'b0;
            dmem_word_addr <= 16'd0;
            dmem_write_data <= 32'd0;
            cpu_release <= 1'b0;
            run_sample <= 7'd0;
            active <= 1'b1;
            error <= 1'b0;
            imem_write_count <= 16'd0;
            dmem_write_count <= 16'd0;
        end else begin
            tx_valid <= 1'b0;
            imem_we <= 1'b0;
            dmem_we <= 1'b0;
            if (active && rx_framing_error) begin
                error <= 1'b1;
                state <= RX_SOF0;
            end
            if (active) begin
                case (state)
                    RX_SOF0: if (rx_valid && rx_byte == SOF0) state <= RX_SOF1;
                    RX_SOF1: if (rx_valid) begin
                        if (rx_byte == SOF1) state <= RX_CMD;
                        else if (rx_byte != SOF0) state <= RX_SOF0;
                    end
                    RX_CMD: if (rx_valid) begin
                        command <= rx_byte;
                        crc <= crc32_byte(32'hFFFF_FFFF, rx_byte);
                        state <= RX_ADDR0;
                    end
                    RX_ADDR0: if (rx_valid) begin
                        byte_address[7:0] <= rx_byte;
                        crc <= crc32_byte(crc, rx_byte);
                        state <= RX_ADDR1;
                    end
                    RX_ADDR1: if (rx_valid) begin
                        byte_address[15:8] <= rx_byte;
                        crc <= crc32_byte(crc, rx_byte);
                        state <= RX_ADDR2;
                    end
                    RX_ADDR2: if (rx_valid) begin
                        byte_address[23:16] <= rx_byte;
                        crc <= crc32_byte(crc, rx_byte);
                        state <= RX_ADDR3;
                    end
                    RX_ADDR3: if (rx_valid) begin
                        byte_address[31:24] <= rx_byte;
                        crc <= crc32_byte(crc, rx_byte);
                        state <= RX_LEN0;
                    end
                    RX_LEN0: if (rx_valid) begin
                        payload_length[7:0] <= rx_byte;
                        crc <= crc32_byte(crc, rx_byte);
                        state <= RX_LEN1;
                    end
                    RX_LEN1: if (rx_valid) begin
                        payload_length[15:8] <= rx_byte;
                        payload_index <= 16'd0;
                        word_data <= 32'd0;
                        crc <= crc32_byte(crc, rx_byte);
                        packet_valid <=
                            (((command == CMD_WRITE_IMEM) ||
                              (command == CMD_WRITE_DMEM)) &&
                             (byte_address[1:0] == 2'b00) &&
                             ({rx_byte, payload_length[7:0]} != 16'd0) &&
                             ({rx_byte, payload_length[7:0]} <= MAX_PAYLOAD) &&
                             (payload_length[1:0] == 2'b00) &&
                             ((command == CMD_WRITE_IMEM &&
                               byte_address + {16'd0, rx_byte, payload_length[7:0]}
                                   <= IMEM_WORDS * 4) ||
                              (command == CMD_WRITE_DMEM &&
                               byte_address + {16'd0, rx_byte, payload_length[7:0]}
                                   <= DMEM_WORDS * 4))) ||
                            (((command == CMD_RUN) &&
                              (byte_address < 32'd100) &&
                              ({rx_byte, payload_length[7:0]} == 16'd0)) ||
                             ((command == CMD_PING) &&
                              (byte_address == 32'd0) &&
                              ({rx_byte, payload_length[7:0]} == 16'd0)));
                        state <= ({rx_byte, payload_length[7:0]} == 16'd0)
                               ? RX_CRC0 : RX_PAYLOAD;
                    end
                    RX_PAYLOAD: if (rx_valid) begin
                        crc <= crc32_byte(crc, rx_byte);
                        case (payload_index[1:0])
                            2'd0: word_data[7:0] <= rx_byte;
                            2'd1: word_data[15:8] <= rx_byte;
                            2'd2: word_data[23:16] <= rx_byte;
                            default: begin
                                word_data[31:24] <= rx_byte;
                                if (packet_valid && command == CMD_WRITE_IMEM) begin
                                    imem_word_addr <= byte_address[17:2] + payload_index[15:2];
                                    imem_write_data <= {rx_byte, word_data[23:0]};
                                    imem_we <= 1'b1;
                                    imem_write_count <= imem_write_count + 1'b1;
                                end else if (packet_valid && command == CMD_WRITE_DMEM) begin
                                    dmem_word_addr <= byte_address[17:2] + payload_index[15:2];
                                    dmem_write_data <= {rx_byte, word_data[23:0]};
                                    dmem_we <= 1'b1;
                                    dmem_write_count <= dmem_write_count + 1'b1;
                                end
                            end
                        endcase
                        if (payload_index + 1'b1 == payload_length)
                            state <= RX_CRC0;
                        else
                            payload_index <= payload_index + 1'b1;
                    end
                    RX_CRC0: if (rx_valid) begin
                        received_crc[7:0] <= rx_byte;
                        state <= RX_CRC1;
                    end
                    RX_CRC1: if (rx_valid) begin
                        received_crc[15:8] <= rx_byte;
                        state <= RX_CRC2;
                    end
                    RX_CRC2: if (rx_valid) begin
                        received_crc[23:16] <= rx_byte;
                        state <= RX_CRC3;
                    end
                    RX_CRC3: if (rx_valid) begin
                        response <= RESPONSE_NACK;
                        run_after_response <= 1'b0;
                        if (!packet_valid ||
                            ({rx_byte, received_crc[23:0]} != (crc ^ 32'hFFFF_FFFF))) begin
                            error <= 1'b1;
                        end else if (command == CMD_PING) begin
                            response <= RESPONSE_PONG;
                            error <= 1'b0;
                        end else if (command == CMD_RUN) begin
                            if (imem_write_count != 16'd0 && dmem_write_count != 16'd0) begin
                                response <= RESPONSE_ACK;
                                run_after_response <= 1'b1;
                                run_sample <= byte_address[6:0];
                                error <= 1'b0;
                            end else begin
                                error <= 1'b1;
                            end
                        end else begin
                            response <= RESPONSE_ACK;
                            error <= 1'b0;
                        end
                        state <= TX_ARM;
                    end
                    TX_ARM: if (tx_ready) begin
                        tx_data <= response;
                        tx_valid <= 1'b1;
                        state <= TX_WAIT_BUSY;
                    end
                    TX_WAIT_BUSY: if (!tx_ready) state <= TX_WAIT_DONE;
                    TX_WAIT_DONE: if (tx_ready) begin
                        if (run_after_response && response == RESPONSE_ACK) begin
                            cpu_release <= 1'b1;
                            active <= 1'b0;
                        end
                        run_after_response <= 1'b0;
                        state <= RX_SOF0;
                    end
                    default: state <= RX_SOF0;
                endcase
            end
        end
    end
endmodule
