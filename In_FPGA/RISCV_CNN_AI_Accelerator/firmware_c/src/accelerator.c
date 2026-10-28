#include "accelerator.h"
#include "memory_map.h"

#define REG_CTRL         (ACCEL_BASE + 0x00u)
#define REG_STATUS       (ACCEL_BASE + 0x04u)
#define REG_INPUT_H      (ACCEL_BASE + 0x08u)
#define REG_INPUT_W      (ACCEL_BASE + 0x0Cu)
#define REG_CIN          (ACCEL_BASE + 0x10u)
#define REG_COUT         (ACCEL_BASE + 0x14u)
#define REG_KERNEL       (ACCEL_BASE + 0x18u)
#define REG_STRIDE       (ACCEL_BASE + 0x1Cu)
#define REG_PADDING      (ACCEL_BASE + 0x20u)
#define REG_RELU         (ACCEL_BASE + 0x24u)
#define REG_INPUT_DATA   (ACCEL_BASE + 0x30u)
#define REG_WEIGHT_DATA  (ACCEL_BASE + 0x34u)
#define REG_OUTPUT_DATA  (ACCEL_BASE + 0x38u)
#define REG_INPUT_COUNT  (ACCEL_BASE + 0x3Cu)
#define REG_WEIGHT_COUNT (ACCEL_BASE + 0x40u)
#define REG_OUTPUT_COUNT (ACCEL_BASE + 0x44u)
#define REG_ERROR_CODE   (ACCEL_BASE + 0x48u)

#define STATUS_BUSY  0x1u
#define STATUS_DONE  0x2u
#define STATUS_ERROR 0x4u
#define POLL_LIMIT   100000000u

static uint32_t pack4(const uint8_t bytes[4]) {
    return (uint32_t)bytes[0]
        | ((uint32_t)bytes[1] << 8)
        | ((uint32_t)bytes[2] << 16)
        | ((uint32_t)bytes[3] << 24);
}

void accelerator_clear(void) {
    mmio_write32(REG_CTRL, 0x2u);
}

uint32_t accelerator_output_count(void) {
    return mmio_read32(REG_OUTPUT_COUNT);
}

uint32_t accelerator_error_code(void) {
    return mmio_read32(REG_ERROR_CODE);
}

int32_t accelerator_read_output(void) {
    return (int32_t)mmio_read32(REG_OUTPUT_DATA);
}

int accelerator_run(
    const accel_config_t *config,
    const int8_t *input,
    uint32_t input_bytes,
    byte_reader_fn weight_reader,
    void *weight_context,
    uint32_t weight_bytes
) {
    uint32_t offset;
    uint32_t polls;
    uint32_t status;
    uint8_t bytes[4];
    unsigned lane;

    if (((input_bytes | weight_bytes) & 3u) != 0u) {
        return ACCEL_ERR_COUNT;
    }

    accelerator_clear();
    mmio_write32(REG_INPUT_H, config->input_h);
    mmio_write32(REG_INPUT_W, config->input_w);
    mmio_write32(REG_CIN, config->cin);
    mmio_write32(REG_COUT, config->cout);
    mmio_write32(REG_KERNEL, config->kernel);
    mmio_write32(REG_STRIDE, config->stride);
    mmio_write32(REG_PADDING, config->padding);
    mmio_write32(REG_RELU, config->relu);

    for (offset = 0u; offset < input_bytes; offset += 4u) {
        bytes[0] = (uint8_t)input[offset + 0u];
        bytes[1] = (uint8_t)input[offset + 1u];
        bytes[2] = (uint8_t)input[offset + 2u];
        bytes[3] = (uint8_t)input[offset + 3u];
        mmio_write32(REG_INPUT_DATA, pack4(bytes));
    }

    for (offset = 0u; offset < weight_bytes; offset += 4u) {
        for (lane = 0u; lane < 4u; ++lane) {
            if (weight_reader(weight_context, &bytes[lane]) != 0) {
                return ACCEL_ERR_STREAM;
            }
        }
        mmio_write32(REG_WEIGHT_DATA, pack4(bytes));
    }

    if (mmio_read32(REG_INPUT_COUNT) != input_bytes
        || mmio_read32(REG_WEIGHT_COUNT) != weight_bytes) {
        return ACCEL_ERR_COUNT;
    }

    mmio_write32(REG_CTRL, 0x1u);
    polls = POLL_LIMIT;
    do {
        status = mmio_read32(REG_STATUS);
        if ((status & STATUS_ERROR) != 0u) {
            return ACCEL_ERR_HW;
        }
        if ((status & STATUS_DONE) != 0u) {
            return ACCEL_OK;
        }
    } while (--polls != 0u);
    return ACCEL_ERR_TIMEOUT;
}

