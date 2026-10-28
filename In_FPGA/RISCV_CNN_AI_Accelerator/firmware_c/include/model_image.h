#ifndef MODEL_IMAGE_H
#define MODEL_IMAGE_H

#include <stdint.h>

#define MODEL_SECTION_COUNT 7u
#define MODEL_SAMPLE_HEADER_SIZE 32u
#define MODEL_SAMPLE_IMAGE_SIZE 784u
#define MODEL_SAMPLE_RECORD_SIZE 816u

enum {
    MODEL_CONV1_WEIGHT = 1,
    MODEL_CONV2_WEIGHT = 2,
    MODEL_FC1_WEIGHT = 3,
    MODEL_FC1_BIAS_K = 4,
    MODEL_FC2_WEIGHT = 5,
    MODEL_FC2_BIAS_K = 6,
    MODEL_SAMPLE = 7
};

typedef struct {
    uint32_t type;
    uint32_t sector;
    uint32_t byte_length;
    uint32_t crc32;
} model_section_t;

typedef struct {
    uint32_t sample_count;
    uint32_t samples_per_digit;
    uint32_t conv1_mul_q20;
    uint32_t total_sectors;
    uint32_t feature_calibration_max;
    uint32_t sample_record_size;
    model_section_t sections[MODEL_SECTION_COUNT];
} model_header_t;

typedef struct {
    const model_section_t *section;
    uint32_t position;
    uint32_t cached_sector;
    uint32_t crc;
    uint8_t cache_valid;
} model_stream_t;

enum {
    MODEL_OK = 0,
    MODEL_ERR_IO = -20,
    MODEL_ERR_MAGIC = -21,
    MODEL_ERR_VERSION = -22,
    MODEL_ERR_HEADER_CRC = -23,
    MODEL_ERR_SECTION = -24,
    MODEL_ERR_SECTION_CRC = -25,
    MODEL_ERR_EOF = -26,
    MODEL_ERR_SAMPLE_CRC = -27,
    MODEL_ERR_SAMPLE_INVALID = -28
};

int model_open(model_header_t *header);
const model_section_t *model_find(const model_header_t *header, uint32_t type);
void model_stream_open(model_stream_t *stream, const model_section_t *section);
int model_stream_read(model_stream_t *stream, uint8_t *value);
int model_stream_finish(model_stream_t *stream);
int model_stream_read_i32(model_stream_t *stream, int32_t *value);
int model_stream_read_i64(model_stream_t *stream, int64_t *value);
int model_read_slice(
    const model_section_t *section,
    uint32_t offset,
    uint8_t *destination,
    uint32_t length
);
int model_write_slice(
    const model_section_t *section,
    uint32_t offset,
    const uint8_t *source,
    uint32_t length
);
uint32_t model_crc32(const uint8_t *data, uint32_t length);

#endif

