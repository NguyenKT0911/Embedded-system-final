#include "accelerator.h"
#include "cnn.h"
#include "memory_map.h"
#include "model_image.h"

#define CONV1_INPUT_BYTES 784u
#define CONV1_WEIGHT_BYTES 144u
#define CONV1_OUTPUTS 12544u
#define CONV2_INPUT_BYTES 3136u
#define CONV2_WEIGHT_BYTES 4608u
#define CONV2_OUTPUTS 6272u
#define FEATURE_COUNT 1568u
#define HIDDEN_COUNT 128u
#define UI_IMAGE_CONTROL (UI_BASE + 0x08u)
#define UI_IMAGE_WORDS   (UI_BASE + 0x100u)

static union {
    int8_t conv2_input[CONV2_INPUT_BYTES];
    int8_t feature_q[FEATURE_COUNT];
} workspace;
static int32_t hidden_acc[HIDDEN_COUNT];
static int8_t hidden_q[HIDDEN_COUNT];
static int64_t fc2_bias_k[10];
static int32_t first_row[28];

int cnn_preview_from_sd(const model_header_t *model, uint32_t sample_index) {
    const model_section_t *sample = model_find(model, MODEL_SAMPLE);
    uint32_t record_offset;
    uint32_t word;

    if (sample_index >= model->sample_count) {
        return MODEL_ERR_SECTION;
    }
    mmio_write32(UI_IMAGE_CONTROL, 0u);
    record_offset = sample_index * model->sample_record_size;
    (void)model_read_slice(
        sample,
        record_offset + MODEL_SAMPLE_HEADER_SIZE,
        (uint8_t *)workspace.conv2_input,
        CONV1_INPUT_BYTES
    );

    // A one-bit preview keeps the original 28x28 handwriting visible on HDMI
    // without consuming another block RAM (all BSRAMs are used by the SoC).
    for (word = 0u; word < 25u; ++word) {
        uint32_t packed = 0u;
        uint32_t bit;
        for (bit = 0u; bit < 32u; ++bit) {
            uint32_t pixel = word * 32u + bit;
            if (pixel < CONV1_INPUT_BYTES && workspace.conv2_input[pixel] > 0) {
                packed |= 1u << bit;
            }
        }
        mmio_write32(UI_IMAGE_WORDS + word * 4u, packed);
    }
    mmio_write32(UI_IMAGE_CONTROL, 1u);
    return 0;
}

static int stream_byte_adapter(void *context, uint8_t *value) {
    return model_stream_read((model_stream_t *)context, value);
}

static int load_section(
    const model_section_t *section,
    int8_t *destination,
    uint32_t expected_bytes
) {
    model_stream_t stream;
    uint32_t index;
    int status;
    if (section == (const model_section_t *)0
        || section->byte_length != expected_bytes) {
        return MODEL_ERR_SECTION;
    }
    model_stream_open(&stream, section);
    for (index = 0u; index < expected_bytes; ++index) {
        status = model_stream_read(&stream, (uint8_t *)&destination[index]);
        if (status != MODEL_OK) {
            return status;
        }
    }
    return model_stream_finish(&stream);
}

static int run_accelerator(
    const accel_config_t *config,
    const int8_t *input,
    uint32_t input_bytes,
    const model_section_t *weight,
    uint32_t weight_bytes
) {
    model_stream_t stream;
    int status;
    if (weight == (const model_section_t *)0
        || weight->byte_length != weight_bytes) {
        return MODEL_ERR_SECTION;
    }
    model_stream_open(&stream, weight);
    status = accelerator_run(
        config,
        input,
        input_bytes,
        stream_byte_adapter,
        &stream,
        weight_bytes
    );
    if (status != ACCEL_OK) {
        return status;
    }
    return model_stream_finish(&stream);
}

static uint32_t rounded_div_u32(uint32_t value, uint32_t denominator) {
    return (value + denominator / 2u) / denominator;
}

static int32_t rounded_div_i32(int32_t value, uint32_t denominator) {
    uint32_t magnitude;
    uint32_t quotient;
    if (value < 0) {
        magnitude = (uint32_t)(-value);
        quotient = rounded_div_u32(magnitude, denominator);
        return -(int32_t)quotient;
    }
    return (int32_t)rounded_div_u32((uint32_t)value, denominator);
}

static uint64_t multiply_u32_u32(uint32_t left, uint32_t right) {
    uint64_t result = 0u;
    uint64_t shifted = left;
    while (right != 0u) {
        if ((right & 1u) != 0u) {
            result += shifted;
        }
        shifted <<= 1;
        right >>= 1;
    }
    return result;
}

static uint64_t divide_u64(uint64_t numerator, uint64_t denominator) {
    uint64_t quotient = 0u;
    uint64_t remainder = 0u;
    unsigned bit;
    if (denominator == 0u) {
        return UINT64_MAX;
    }
    for (bit = 64u; bit != 0u; --bit) {
        remainder = (remainder << 1) | ((numerator >> (bit - 1u)) & 1u);
        if (remainder >= denominator) {
            remainder -= denominator;
            quotient |= (uint64_t)1u << (bit - 1u);
        }
    }
    return quotient;
}

static int32_t rounded_div_i64(int64_t value, uint64_t denominator) {
    uint64_t magnitude;
    uint64_t quotient;
    if (value < 0) {
        magnitude = (~(uint64_t)value) + 1u;
        quotient = divide_u64(magnitude + denominator / 2u, denominator);
        return -(int32_t)quotient;
    }
    quotient = divide_u64((uint64_t)value + denominator / 2u, denominator);
    return (int32_t)quotient;
}

static int32_t multiply_s8(int8_t left, int8_t right) {
    uint32_t a = left < 0 ? (uint32_t)(-(int32_t)left) : (uint32_t)left;
    uint32_t b = right < 0 ? (uint32_t)(-(int32_t)right) : (uint32_t)right;
    uint32_t result = 0u;
    while (b != 0u) {
        if ((b & 1u) != 0u) {
            result += a;
        }
        a <<= 1;
        b >>= 1;
    }
    return ((left < 0) != (right < 0)) ? -(int32_t)result : (int32_t)result;
}

static int pool_and_requantize_conv1(uint32_t multiplier_q20) {
    uint32_t channel;
    uint32_t pair_y;
    uint32_t x;
    uint32_t destination = 0u;
    for (channel = 0u; channel < 16u; ++channel) {
        for (pair_y = 0u; pair_y < 14u; ++pair_y) {
            for (x = 0u; x < 28u; ++x) {
                first_row[x] = accelerator_read_output();
            }
            for (x = 0u; x < 28u; x += 2u) {
                int32_t lower0 = accelerator_read_output();
                int32_t lower1 = accelerator_read_output();
                int32_t maximum = first_row[x];
                uint32_t quantized;
                if (first_row[x + 1u] > maximum) maximum = first_row[x + 1u];
                if (lower0 > maximum) maximum = lower0;
                if (lower1 > maximum) maximum = lower1;
                if (maximum < 0) maximum = 0;
                quantized =
                    ((uint32_t)maximum * multiplier_q20 + (1u << 19)) >> 20;
                if (quantized > 127u) quantized = 127u;
                workspace.conv2_input[destination++] = (int8_t)quantized;
            }
        }
    }
    return destination == CONV2_INPUT_BYTES ? 0 : -40;
}

static int pool_conv2(uint32_t calibration_max, uint32_t *maximum_out) {
    uint32_t channel;
    uint32_t pair_y;
    uint32_t x;
    uint32_t destination = 0u;
    uint32_t overall_max = 0u;
    for (channel = 0u; channel < 32u; ++channel) {
        for (pair_y = 0u; pair_y < 7u; ++pair_y) {
            for (x = 0u; x < 14u; ++x) {
                first_row[x] = accelerator_read_output();
            }
            for (x = 0u; x < 14u; x += 2u) {
                int32_t lower0 = accelerator_read_output();
                int32_t lower1 = accelerator_read_output();
                int32_t maximum = first_row[x];
                if (first_row[x + 1u] > maximum) maximum = first_row[x + 1u];
                if (lower0 > maximum) maximum = lower0;
                if (lower1 > maximum) maximum = lower1;
                if (maximum < 0) maximum = 0;
                {
                    uint32_t quantized = rounded_div_u32(
                        (uint32_t)maximum * 127u,
                        calibration_max
                    );
                    if (quantized > 127u) quantized = 127u;
                    workspace.feature_q[destination++] = (int8_t)quantized;
                }
                if ((uint32_t)maximum > overall_max) {
                    overall_max = (uint32_t)maximum;
                }
            }
        }
    }
    *maximum_out = overall_max;
    return destination == FEATURE_COUNT && overall_max != 0u ? 0 : -41;
}

static int run_fc1(const model_header_t *model, uint32_t pooled_max, uint32_t *hidden_max_out) {
    const model_section_t *bias_section = model_find(model, MODEL_FC1_BIAS_K);
    const model_section_t *weight_section = model_find(model, MODEL_FC1_WEIGHT);
    model_stream_t bias_stream;
    model_stream_t weight_stream;
    uint32_t output;
    uint32_t input;
    uint32_t hidden_max = 0u;
    int status;

    if (bias_section == (const model_section_t *)0
        || bias_section->byte_length != HIDDEN_COUNT * 4u
        || weight_section == (const model_section_t *)0
        || weight_section->byte_length != HIDDEN_COUNT * FEATURE_COUNT) {
        return MODEL_ERR_SECTION;
    }
    model_stream_open(&bias_stream, bias_section);
    for (output = 0u; output < HIDDEN_COUNT; ++output) {
        status = model_stream_read_i32(&bias_stream, &hidden_acc[output]);
        if (status != MODEL_OK) return status;
    }
    status = model_stream_finish(&bias_stream);
    if (status != MODEL_OK) return status;

    model_stream_open(&weight_stream, weight_section);
    for (output = 0u; output < HIDDEN_COUNT; ++output) {
        int32_t accumulator = 0;
        int32_t bias = rounded_div_i32(hidden_acc[output], pooled_max);
        for (input = 0u; input < FEATURE_COUNT; ++input) {
            uint8_t raw_weight;
            status = model_stream_read(&weight_stream, &raw_weight);
            if (status != MODEL_OK) return status;
            accumulator += multiply_s8(workspace.feature_q[input], (int8_t)raw_weight);
        }
        accumulator += bias;
        if (accumulator < 0) accumulator = 0;
        hidden_acc[output] = accumulator;
        if ((uint32_t)accumulator > hidden_max) {
            hidden_max = (uint32_t)accumulator;
        }
    }
    status = model_stream_finish(&weight_stream);
    if (status != MODEL_OK) return status;
    if (hidden_max == 0u) return -42;

    for (output = 0u; output < HIDDEN_COUNT; ++output) {
        uint32_t quantized = rounded_div_u32(
            (uint32_t)hidden_acc[output] * 127u,
            hidden_max
        );
        if (quantized > 127u) quantized = 127u;
        hidden_q[output] = (int8_t)quantized;
    }
    *hidden_max_out = hidden_max;
    return 0;
}

static int run_fc2(
    const model_header_t *model,
    uint32_t pooled_max,
    uint32_t hidden_max,
    cnn_result_t *result
) {
    const model_section_t *bias_section = model_find(model, MODEL_FC2_BIAS_K);
    const model_section_t *weight_section = model_find(model, MODEL_FC2_WEIGHT);
    model_stream_t bias_stream;
    model_stream_t weight_stream;
    uint64_t denominator = multiply_u32_u32(pooled_max, hidden_max);
    uint32_t output;
    uint32_t input;
    int status;
    uint32_t best = 0u;

    if (bias_section == (const model_section_t *)0
        || bias_section->byte_length != 80u
        || weight_section == (const model_section_t *)0
        || weight_section->byte_length != 1280u) {
        return MODEL_ERR_SECTION;
    }
    model_stream_open(&bias_stream, bias_section);
    for (output = 0u; output < 10u; ++output) {
        status = model_stream_read_i64(&bias_stream, &fc2_bias_k[output]);
        if (status != MODEL_OK) return status;
    }
    status = model_stream_finish(&bias_stream);
    if (status != MODEL_OK) return status;

    model_stream_open(&weight_stream, weight_section);
    for (output = 0u; output < 10u; ++output) {
        int32_t accumulator = 0;
        for (input = 0u; input < HIDDEN_COUNT; ++input) {
            uint8_t raw_weight;
            status = model_stream_read(&weight_stream, &raw_weight);
            if (status != MODEL_OK) return status;
            accumulator += multiply_s8(hidden_q[input], (int8_t)raw_weight);
        }
        result->logits[output] = accumulator
            + rounded_div_i64(fc2_bias_k[output], denominator);
        if (output == 0u || result->logits[output] > result->logits[best]) {
            best = output;
        }
    }
    status = model_stream_finish(&weight_stream);
    if (status != MODEL_OK) return status;
    result->prediction = best;
    return 0;
}

int cnn_run_from_sd(
    const model_header_t *model,
    uint32_t sample_index,
    cnn_result_t *result
) {
    static const accel_config_t conv1 = {28u, 28u, 1u, 16u, 3u, 1u, 1u, 1u};
    static const accel_config_t conv2 = {14u, 14u, 16u, 32u, 3u, 1u, 1u, 1u};
    const model_section_t *sample = model_find(model, MODEL_SAMPLE);
    uint8_t sample_header[MODEL_SAMPLE_HEADER_SIZE];
    uint32_t record_offset;
    uint32_t calibration_max;
    uint32_t index;
    int status;

    if (sample_index >= model->sample_count) {
        return MODEL_ERR_SECTION;
    }
    record_offset = sample_index * model->sample_record_size;
    status = model_read_slice(sample, record_offset, sample_header,
                              MODEL_SAMPLE_HEADER_SIZE);
    if (status != MODEL_OK) return status;
    result->expected_label = sample_header[4];
    result->sample_index = sample_index;
    calibration_max = (uint32_t)sample_header[16]
        | ((uint32_t)sample_header[17] << 8)
        | ((uint32_t)sample_header[18] << 16)
        | ((uint32_t)sample_header[19] << 24);
    status = model_read_slice(
        sample, record_offset + MODEL_SAMPLE_HEADER_SIZE,
        (uint8_t *)workspace.conv2_input, CONV1_INPUT_BYTES
    );
    if (status != MODEL_OK) return status;
    status = run_accelerator(
        &conv1,
        workspace.conv2_input,
        CONV1_INPUT_BYTES,
        model_find(model, MODEL_CONV1_WEIGHT),
        CONV1_WEIGHT_BYTES
    );
    if (status != 0) return status;
    result->conv1_outputs = accelerator_output_count();
    if (result->conv1_outputs != CONV1_OUTPUTS) return ACCEL_ERR_COUNT;
    status = pool_and_requantize_conv1(model->conv1_mul_q20);
    if (status != 0) return status;

    status = run_accelerator(
        &conv2,
        workspace.conv2_input,
        CONV2_INPUT_BYTES,
        model_find(model, MODEL_CONV2_WEIGHT),
        CONV2_WEIGHT_BYTES
    );
    if (status != 0) return status;
    result->conv2_outputs = accelerator_output_count();
    if (result->conv2_outputs != CONV2_OUTPUTS) return ACCEL_ERR_COUNT;
    status = pool_conv2(calibration_max, &result->pooled2_max);
    if (status != 0) return status;
    status = run_fc1(model, calibration_max, &result->hidden_max);
    if (status != 0) return status;
    status = run_fc2(
        model,
        calibration_max,
        result->hidden_max,
        result
    );
    if (status != 0) return status;
    result->confidence = sample_header[20u + result->prediction];
    return 0;
}

