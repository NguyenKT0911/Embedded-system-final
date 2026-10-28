#ifndef RUNTIME_PROTOCOL_H
#define RUNTIME_PROTOCOL_H

#include <stdint.h>
#include "model_image.h"

void runtime_protocol_init(
    model_header_t *model,
    uint8_t sd_ready,
    uint8_t model_ready
);
void runtime_protocol_poll(void);
void runtime_protocol_set_cnn_busy(uint8_t busy);

#endif
