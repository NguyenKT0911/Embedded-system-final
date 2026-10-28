`timescale 1ns/1ps

module tb_riscv_conv1_real_digit;
    riscv_conv_golden_checker #(
        .INPUT_H(28), .INPUT_W(28), .CIN(1), .COUT(16),
        .INPUT_WORDS(196), .WEIGHT_WORDS(36), .OUTPUT_VALUES(12544),
        .INPUT_HEX_FILE("Real_Digits/simulation/conv1_real_digit_input.hex"),
        .WEIGHT_HEX_FILE("TangNano20K_RISCV_CNN/model/conv1_real/conv1_real_weight_packed32.hex"),
        .GOLDEN_HEX_FILE("Real_Digits/simulation/conv1_real_digit_golden.hex"),
        .FIRMWARE_HEX_FILE("TangNano20K_RISCV_CNN/firmware/conv1_firmware.hex"),
        .DATA_HEX_FILE("Real_Digits/simulation/conv1_real_digit_data.hex"),
        .TEST_NAME("CONV1_REAL_4_01")
    ) u_checker (.unused(1'b0));
endmodule

module tb_riscv_conv2_real_digit;
    riscv_conv_golden_checker #(
        .INPUT_H(14), .INPUT_W(14), .CIN(16), .COUT(32),
        .INPUT_WORDS(784), .WEIGHT_WORDS(1152), .OUTPUT_VALUES(6272),
        .INPUT_HEX_FILE("Real_Digits/simulation/conv2_real_digit_input.hex"),
        .WEIGHT_HEX_FILE("TangNano20K_RISCV_CNN/model/conv2_real/conv2_real_weight_packed32.hex"),
        .GOLDEN_HEX_FILE("Real_Digits/simulation/conv2_real_digit_golden.hex"),
        .FIRMWARE_HEX_FILE("TangNano20K_RISCV_CNN/firmware/conv2_firmware.hex"),
        .DATA_HEX_FILE("Real_Digits/simulation/conv2_real_digit_data.hex"),
        .TEST_NAME("CONV2_REAL_4_01")
    ) u_checker (.unused(1'b0));
endmodule

