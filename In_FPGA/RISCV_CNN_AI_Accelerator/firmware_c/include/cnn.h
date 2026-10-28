#ifndef CNN_H
#define CNN_H

#include <stdint.h>
#include "model_image.h"

typedef struct {
    uint32_t prediction;
    uint32_t confidence;
    uint32_t expected_label;
    uint32_t sample_index;
    int32_t logits[10];
    uint32_t conv1_outputs;
    uint32_t conv2_outputs;
    uint32_t pooled2_max;
    uint32_t hidden_max;
} cnn_result_t;

int cnn_preview_from_sd(const model_header_t *model, uint32_t sample_index);

int cnn_run_from_sd(
    const model_header_t *model,
    uint32_t sample_index,
    cnn_result_t *result
);

#endif

