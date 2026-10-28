#include <stdint.h>

#include "cnn.h"
#include "memory_map.h"
#include "model_image.h"
#include "runtime_protocol.h"
#include "sd_spi.h"
#include "uart.h"

#define RESULT_PREDICTION (RESULT_BASE + 0x00u)
#define RESULT_SAMPLE_ID  (RESULT_BASE + 0x04u)
#define RESULT_CONTROL    (RESULT_BASE + 0x08u)
#define UI_SELECTED_SAMPLE (UI_BASE + 0x00u)
#define UI_RUN_TOGGLE     (UI_BASE + 0x04u)

static model_header_t model;
static cnn_result_t inference;

static void publish_result(
    uint32_t prediction,
    uint32_t sample_id,
    uint32_t confidence
) {
    mmio_write32(RESULT_CONTROL, 0x2u);
    mmio_write32(RESULT_PREDICTION, prediction);
    mmio_write32(
        RESULT_SAMPLE_ID,
        (sample_id << 8) | confidence
    );
    mmio_write32(RESULT_CONTROL, 0x1u);
}

#ifdef FIRMWARE_UART_SELFTEST
int main(void) {
    uart_init();
    uart_puts("C_FW_READY\r\n");
    for (;;) {
        char command = uart_getc();
        if (command == 'p') {
            uart_puts("PONG\r\n");
        } else {
            uart_putc(command);
        }
    }
}
#elif defined(FIRMWARE_PREVIEW_DIAGNOSTIC)
/*
 * Board diagnostic for the path that is not exercised by batch inference:
 * SD init -> model header -> selected sample -> preview MMIO -> HDMI renderer.
 * Status bytes: D0=start, D1=SD OK, D2=model OK, D3=preview OK;
 * E0/E1/E2 are followed by the low byte of the failing status code.
 */
int main(void) {
    int status;
    uint32_t selected_sample;

    uart_init();
    uart_putc((char)0xD0);
    status = sd_init();
    if (status != SD_OK) {
        uart_putc((char)0xE0);
        uart_putc((char)status);
        for (;;) { }
    }
    uart_putc((char)0xD1);
    status = model_open(&model);
    if (status != MODEL_OK) {
        uart_putc((char)0xE1);
        uart_putc((char)status);
        for (;;) { }
    }
    uart_putc((char)0xD2);
    selected_sample = mmio_read32(UI_SELECTED_SAMPLE) & 0x7Fu;
    status = cnn_preview_from_sd(&model, selected_sample);
    if (status != MODEL_OK) {
        uart_putc((char)0xE2);
        uart_putc((char)status);
        for (;;) { }
    }
    uart_putc((char)0xD3);
    uart_putc((char)selected_sample);
    for (;;) { }
}
#elif defined(FIRMWARE_BATCH_SELFTEST)
/*
 * Hardware-only accuracy test.  The host sends 'S', then the FPGA runs every
 * sample from the SD card and returns one fixed six-byte record per image:
 *   A5, sample_index, expected_label, prediction, confidence, status
 * followed by: 5A, correct_count, sample_count.
 */
int main(void) {
    uint32_t sample_index;
    uint32_t correct_count = 0u;
    int status;

    uart_init();
    status = sd_init();
    if (status != SD_OK) {
        uart_putc((char)0xE0);
        for (;;) { }
    }
    status = model_open(&model);
    if (status != MODEL_OK) {
        uart_putc((char)0xE1);
        for (;;) { }
    }

    while (uart_getc() != 'S') { }
    uart_putc((char)0xB0);
    for (sample_index = 0u; sample_index < model.sample_count; ++sample_index) {
        status = cnn_run_from_sd(&model, sample_index, &inference);
        uart_putc((char)0xA5);
        uart_putc((char)sample_index);
        uart_putc((char)inference.expected_label);
        uart_putc((char)inference.prediction);
        uart_putc((char)inference.confidence);
        uart_putc((char)(status == 0 ? 0u : 1u));
        if ((status == 0) && (inference.prediction == inference.expected_label)) {
            ++correct_count;
        }
    }
    uart_putc((char)0x5A);
    uart_putc((char)correct_count);
    uart_putc((char)model.sample_count);
    for (;;) { }
}
#elif defined(FIRMWARE_DATASET_MANAGER)
int main(void) {
    uint8_t sd_ready;
    uint8_t model_ready;
    uart_init();
    sd_ready = sd_init() == SD_OK;
    model_ready = sd_ready && model_open(&model) == MODEL_OK;
    runtime_protocol_init(&model, sd_ready, model_ready);
    for (;;) runtime_protocol_poll();
}
#else
int main(void) {
    uint32_t last_run_toggle = 0u;
    uint32_t displayed_sample = 128u;

    if (sd_init() != SD_OK) {
        for (;;) { }
    }
    if (model_open(&model) != MODEL_OK) {
        for (;;) { }
    }

    for (;;) {
        uint32_t selected_sample = mmio_read32(UI_SELECTED_SAMPLE) & 0x7Fu;
        uint32_t current_toggle = mmio_read32(UI_RUN_TOGGLE) & 1u;
        if (selected_sample != displayed_sample) {
            displayed_sample = selected_sample;
            (void)cnn_preview_from_sd(&model, selected_sample);
        }
        /* S2 only selects/previews.  Inference starts explicitly on S1. */
        if (current_toggle != last_run_toggle) {
            last_run_toggle = current_toggle;
            if (cnn_run_from_sd(&model, selected_sample, &inference) == 0) {
                publish_result(
                    inference.prediction,
                    selected_sample,
                    inference.confidence
                );
            }
        }
    }
}
#endif
