#ifndef ACCELERATOR_H
#define ACCELERATOR_H

#include <stdint.h>

enum {
    ACCEL_OK = 0,
    ACCEL_ERR_TIMEOUT = -1,
    ACCEL_ERR_HW = -2,
    ACCEL_ERR_COUNT = -3,
    ACCEL_ERR_STREAM = -4
};

typedef int (*byte_reader_fn)(void *context, uint8_t *value);

typedef struct {
    uint16_t input_h;
    uint16_t input_w;
    uint16_t cin;
    uint16_t cout;
    uint8_t kernel;
    uint8_t stride;
    uint8_t padding;
    uint8_t relu;
} accel_config_t;

int accelerator_run(
    const accel_config_t *config,
    const int8_t *input,
    uint32_t input_bytes,
    byte_reader_fn weight_reader,
    void *weight_context,
    uint32_t weight_bytes
);
int32_t accelerator_read_output(void);
uint32_t accelerator_output_count(void);
uint32_t accelerator_error_code(void);
void accelerator_clear(void);

#endif

