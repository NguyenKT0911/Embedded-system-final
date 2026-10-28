#include "model_image.h"
#include "sd_spi.h"

#define MODEL_VERSION 3u
#define MODEL_HEADER_SIZE 512u

static uint8_t sector_cache[512];
static uint32_t crc32_nibble_table[16];

static uint32_t read_u32(const uint8_t *data) {
    return (uint32_t)data[0]
        | ((uint32_t)data[1] << 8)
        | ((uint32_t)data[2] << 16)
        | ((uint32_t)data[3] << 24);
}

static void crc32_init(void) {
    unsigned index;
    for (index = 0u; index < 16u; ++index) {
        uint32_t crc = index;
        unsigned bit;
        for (bit = 0u; bit < 4u; ++bit) {
            crc = (crc >> 1) ^ ((0u - (crc & 1u)) & 0xEDB88320u);
        }
        crc32_nibble_table[index] = crc;
    }
}

static uint32_t crc32_byte(uint32_t crc, uint8_t value) {
    crc ^= value;
    crc = (crc >> 4) ^ crc32_nibble_table[crc & 0x0Fu];
    crc = (crc >> 4) ^ crc32_nibble_table[crc & 0x0Fu];
    return crc;
}

uint32_t model_crc32(const uint8_t *data, uint32_t length) {
    uint32_t crc = 0xFFFFFFFFu;
    uint32_t index;
    for (index = 0u; index < length; ++index) {
        crc = crc32_byte(crc, data[index]);
    }
    return crc ^ 0xFFFFFFFFu;
}

int model_open(model_header_t *header) {
    uint32_t stored_crc;
    uint32_t calculated_crc;
    uint32_t index;
    crc32_init();
    if (sd_read_sector(0u, sector_cache) != SD_OK) {
        return MODEL_ERR_IO;
    }
    if (sector_cache[0] != 'R' || sector_cache[1] != 'C'
        || sector_cache[2] != 'N' || sector_cache[3] != '1') {
        return MODEL_ERR_MAGIC;
    }
    if (read_u32(&sector_cache[4]) != MODEL_VERSION
        || read_u32(&sector_cache[8]) != MODEL_HEADER_SIZE) {
        return MODEL_ERR_VERSION;
    }
    stored_crc = read_u32(&sector_cache[56]);
    sector_cache[56] = 0u;
    sector_cache[57] = 0u;
    sector_cache[58] = 0u;
    sector_cache[59] = 0u;
    calculated_crc = model_crc32(sector_cache, 512u);
    if (calculated_crc != stored_crc) {
        return MODEL_ERR_HEADER_CRC;
    }

    header->sample_count = read_u32(&sector_cache[16]);
    header->conv1_mul_q20 = read_u32(&sector_cache[24]);
    header->sample_record_size = read_u32(&sector_cache[40]);
#if defined(FIRMWARE_DATASET_MANAGER)
    header->samples_per_digit = read_u32(&sector_cache[20]);
    header->total_sectors = read_u32(&sector_cache[32]);
    header->feature_calibration_max = read_u32(&sector_cache[36]);
#endif
    for (index = 0u; index < MODEL_SECTION_COUNT; ++index) {
        uint32_t offset = 64u + index * 16u;
        header->sections[index].type = read_u32(&sector_cache[offset + 0u]);
        header->sections[index].sector = read_u32(&sector_cache[offset + 4u]);
        header->sections[index].byte_length = read_u32(&sector_cache[offset + 8u]);
        header->sections[index].crc32 = read_u32(&sector_cache[offset + 12u]);
    }
    return MODEL_OK;
}

const model_section_t *model_find(const model_header_t *header, uint32_t type) {
    uint32_t index;
    for (index = 0u; index < MODEL_SECTION_COUNT; ++index) {
        if (header->sections[index].type == type) {
            return &header->sections[index];
        }
    }
    return (const model_section_t *)0;
}

void model_stream_open(model_stream_t *stream, const model_section_t *section) {
    stream->section = section;
    stream->position = 0u;
    stream->cached_sector = 0u;
    stream->crc = 0xFFFFFFFFu;
    stream->cache_valid = 0u;
}

int model_stream_read(model_stream_t *stream, uint8_t *value) {
    uint32_t sector_offset;
    uint32_t wanted_sector;
    if (stream->position >= stream->section->byte_length) {
        return MODEL_ERR_EOF;
    }
    sector_offset = stream->position & 511u;
    wanted_sector = stream->section->sector + (stream->position >> 9);
    if (stream->cache_valid == 0u || stream->cached_sector != wanted_sector) {
        if (sd_read_sector(wanted_sector, sector_cache) != SD_OK) {
            return MODEL_ERR_IO;
        }
        stream->cached_sector = wanted_sector;
        stream->cache_valid = 1u;
    }
    *value = sector_cache[sector_offset];
    stream->crc = crc32_byte(stream->crc, *value);
    ++stream->position;
    return MODEL_OK;
}

int model_stream_finish(model_stream_t *stream) {
    uint8_t value;
    int status;
    while (stream->position < stream->section->byte_length) {
        status = model_stream_read(stream, &value);
        if (status != MODEL_OK) {
            return status;
        }
    }
    if (stream->section->crc32 != 0u
        && (stream->crc ^ 0xFFFFFFFFu) != stream->section->crc32) {
        return MODEL_ERR_SECTION_CRC;
    }
    return MODEL_OK;
}

int model_write_slice(
    const model_section_t *section,
    uint32_t offset,
    const uint8_t *source,
    uint32_t length
) {
    uint32_t position = 0u;
    if (section == (const model_section_t *)0
        || offset > section->byte_length
        || length > section->byte_length - offset) {
        return MODEL_ERR_EOF;
    }
    while (position < length) {
        uint32_t absolute = offset + position;
        uint32_t sector = section->sector + (absolute >> 9);
        uint32_t in_sector = absolute & 511u;
        uint32_t amount = 512u - in_sector;
        uint32_t index;
        int status;
        if (amount > length - position) amount = length - position;
        status = sd_read_sector(sector, sector_cache);
        if (status != SD_OK) return MODEL_ERR_IO;
        for (index = 0u; index < amount; ++index)
            sector_cache[in_sector + index] = source[position + index];
        status = sd_write_sector_verified(sector, sector_cache);
        if (status != SD_OK) return MODEL_ERR_IO;
        position += amount;
    }
    return MODEL_OK;
}

int model_stream_read_i32(model_stream_t *stream, int32_t *value) {
    uint8_t bytes[4];
    unsigned index;
    for (index = 0u; index < 4u; ++index) {
        int status = model_stream_read(stream, &bytes[index]);
        if (status != MODEL_OK) {
            return status;
        }
    }
    *value = (int32_t)read_u32(bytes);
    return MODEL_OK;
}

int model_stream_read_i64(model_stream_t *stream, int64_t *value) {
    uint64_t result = 0u;
    unsigned index;
    for (index = 0u; index < 8u; ++index) {
        uint8_t byte;
        int status = model_stream_read(stream, &byte);
        if (status != MODEL_OK) {
            return status;
        }
        result |= (uint64_t)byte << (index * 8u);
    }
    *value = (int64_t)result;
    return MODEL_OK;
}

int model_read_slice(
    const model_section_t *section,
    uint32_t offset,
    uint8_t *destination,
    uint32_t length
) {
    model_stream_t stream;
    uint32_t index;
    if (section == (const model_section_t *)0
        || offset > section->byte_length
        || length > section->byte_length - offset) {
        return MODEL_ERR_EOF;
    }
    model_stream_open(&stream, section);
    stream.position = offset;
    for (index = 0u; index < length; ++index) {
        int status = model_stream_read(&stream, &destination[index]);
        if (status != MODEL_OK) return status;
    }
    return MODEL_OK;
}

