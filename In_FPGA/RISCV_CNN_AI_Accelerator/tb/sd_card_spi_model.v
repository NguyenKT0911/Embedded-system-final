`timescale 1ns/1ps

// Simulation-only SDHC model implementing the commands used by sd_spi.c.
module sd_card_spi_model #(
    parameter IMAGE_FILE = "sd_image/model_sd.hex",
    parameter integer IMAGE_BYTES = 289280
)(
    input  wire cs_n,
    input  wire sclk,
    input  wire mosi,
    output reg  miso
);
    reg [7:0] storage [0:IMAGE_BYTES-1];
    reg [7:0] command [0:5];
    reg [7:0] response [0:519];
    integer command_count;
    integer response_length;
    integer response_index;
    integer bit_count;
    reg [7:0] input_shift;
    reg [7:0] output_byte;
    reg ready;
    integer i;

    initial begin
        miso = 1'b1;
        command_count = 0;
        response_length = 0;
        response_index = 0;
        bit_count = 0;
        input_shift = 8'd0;
        output_byte = 8'hff;
        ready = 1'b0;
        $readmemh(IMAGE_FILE, storage);
    end

    task prepare_command_response;
        reg [5:0] command_id;
        reg [31:0] argument;
        integer sector_base;
        begin
            command_id = command[0][5:0];
            argument = {command[1], command[2], command[3], command[4]};
            response_index = 0;
            response_length = 1;
            response[0] = 8'h04;
            case (command_id)
                6'd0: begin
                    ready = 1'b0;
                    response[0] = 8'h01;
                end
                6'd8: begin
                    response_length = 5;
                    response[0] = 8'h01;
                    response[1] = 8'h00;
                    response[2] = 8'h00;
                    response[3] = 8'h01;
                    response[4] = 8'haa;
                end
                6'd55: begin
                    response[0] = ready ? 8'h00 : 8'h01;
                end
                6'd41: begin
                    ready = 1'b1;
                    response[0] = 8'h00;
                end
                6'd58: begin
                    response_length = 5;
                    response[0] = ready ? 8'h00 : 8'h01;
                    response[1] = 8'h40;
                    response[2] = 8'h00;
                    response[3] = 8'h00;
                    response[4] = 8'h00;
                end
                6'd17: begin
                    sector_base = argument * 512;
                    if (!ready || sector_base < 0
                        || sector_base + 511 >= IMAGE_BYTES) begin
                        response[0] = 8'h04;
                    end else begin
                        response_length = 516;
                        response[0] = 8'h00;
                        response[1] = 8'hff;
                        response[2] = 8'hfe;
                        for (i = 0; i < 512; i = i + 1)
                            response[3 + i] = storage[sector_base + i];
                        response[515] = 8'hff;
                    end
                end
                default: begin
                    response[0] = 8'h04;
                end
            endcase
        end
    endtask

    always @(posedge cs_n) begin
        command_count = 0;
        response_length = 0;
        response_index = 0;
        bit_count = 0;
        miso = 1'b1;
    end

    always @(posedge sclk) begin
        if (!cs_n) begin
            input_shift = {input_shift[6:0], mosi};
            if (bit_count == 7) begin
                bit_count = 0;
                if (command_count == 0) begin
                    if (input_shift[7:6] == 2'b01) begin
                        command[0] = input_shift;
                        command_count = 1;
                    end
                end else begin
                    command[command_count] = input_shift;
                    command_count = command_count + 1;
                    if (command_count == 6) begin
                        prepare_command_response();
                        command_count = 0;
                    end
                end
            end else begin
                bit_count = bit_count + 1;
            end
        end
    end

    always @(negedge sclk) begin
        if (cs_n) begin
            miso = 1'b1;
        end else if (bit_count == 0) begin
            if (response_index < response_length) begin
                output_byte = response[response_index];
                response_index = response_index + 1;
            end else begin
                output_byte = 8'hff;
            end
            miso = output_byte[7];
        end else begin
            miso = output_byte[7-bit_count];
        end
    end
endmodule

