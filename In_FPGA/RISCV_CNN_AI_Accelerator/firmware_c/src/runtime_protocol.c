#include <stdint.h>

#include "memory_map.h"
#include "model_image.h"
#include "runtime_protocol.h"
#include "uart.h"

#define SOF0 0x55u
#define SOF1 0xAAu
#define MAX_PAYLOAD 128u

#define CMD_STATUS      0x20u
#define CMD_SLOT_INFO   0x21u
#define CMD_SLOT_BEGIN  0x22u
#define CMD_SLOT_WRITE  0x23u
#define CMD_SLOT_COMMIT 0x24u
#define CMD_REBOOT_LOADER 0x26u

#define PROTO_OK          0u
#define PROTO_BAD_COMMAND 1u
#define PROTO_BAD_PACKET  2u
#define PROTO_BAD_SLOT    3u
#define PROTO_SD_ERROR    4u
#define PROTO_CRC_ERROR   5u
#define PROTO_NOT_READY   6u

#define UI_HDMI_STATUS (UI_BASE + 0x0Cu)
#define UI_RELOAD_CONTROL (UI_BASE + 0x10u)

static model_header_t *active_model;
static const model_section_t *sample_section;
static uint8_t flag_sd_ready;
static uint8_t flag_model_ready;
static uint8_t flag_cnn_busy;

static uint8_t state;
static uint8_t command;
static uint32_t address;
static uint16_t length;
static uint16_t position;
static uint8_t payload[MAX_PAYLOAD];
static uint32_t receive_crc;
static uint32_t packet_crc;

static uint32_t crc_byte(uint32_t crc, uint8_t value) {
    unsigned bit;
    crc ^= value;
    for (bit = 0u; bit < 8u; ++bit)
        crc = (crc >> 1) ^ ((0u - (crc & 1u)) & 0xEDB88320u);
    return crc;
}

static uint32_t read_u32(const uint8_t *data) {
    return (uint32_t)data[0] | ((uint32_t)data[1] << 8)
        | ((uint32_t)data[2] << 16) | ((uint32_t)data[3] << 24);
}

static void write_u16(uint8_t *data, uint16_t value) {
    data[0] = (uint8_t)value;
    data[1] = (uint8_t)(value >> 8);
}

static void write_u32(uint8_t *data, uint32_t value) {
    data[0] = (uint8_t)value;
    data[1] = (uint8_t)(value >> 8);
    data[2] = (uint8_t)(value >> 16);
    data[3] = (uint8_t)(value >> 24);
}

static void send_crc_byte(uint8_t value, uint32_t *crc) {
    uart_putc((char)value);
    *crc = crc_byte(*crc, value);
}

static void send_response(
    uint8_t request_command,
    uint32_t status,
    const uint8_t *data,
    uint16_t data_length
) {
    uint32_t crc = 0xFFFFFFFFu;
    uint16_t index;
    uart_putc((char)SOF0);
    uart_putc((char)SOF1);
    send_crc_byte((uint8_t)(request_command | 0x80u), &crc);
    send_crc_byte((uint8_t)status, &crc);
    send_crc_byte((uint8_t)(status >> 8), &crc);
    send_crc_byte((uint8_t)(status >> 16), &crc);
    send_crc_byte((uint8_t)(status >> 24), &crc);
    send_crc_byte((uint8_t)data_length, &crc);
    send_crc_byte((uint8_t)(data_length >> 8), &crc);
    for (index = 0u; index < data_length; ++index)
        send_crc_byte(data[index], &crc);
    crc ^= 0xFFFFFFFFu;
    uart_putc((char)crc);
    uart_putc((char)(crc >> 8));
    uart_putc((char)(crc >> 16));
    uart_putc((char)(crc >> 24));
}

static uint32_t slot_offset(uint32_t slot) {
    return slot * active_model->sample_record_size;
}

static uint32_t crc_from_sd(uint32_t offset, uint32_t byte_count, uint32_t crc) {
    uint32_t done = 0u;
    while (done < byte_count) {
        uint32_t amount = byte_count - done;
        uint32_t index;
        if (amount > 64u) amount = 64u;
        if (model_read_slice(sample_section, offset + done, payload, amount)
            != MODEL_OK) return 0u;
        for (index = 0u; index < amount; ++index)
            crc = crc_byte(crc, payload[index]);
        done += amount;
    }
    return crc;
}

static uint32_t handle_slot_begin(uint32_t slot) {
    uint32_t index;
    uint32_t calibration_max;
    if (!flag_model_ready || length != 19u) return PROTO_NOT_READY;
    if (slot >= active_model->sample_count || payload[4] > 9u)
        return PROTO_BAD_SLOT;
    calibration_max = read_u32(&payload[5]);
    if (calibration_max == 0u) return PROTO_BAD_PACKET;
    /* Extended BEGIN carries image-specific calibration followed by the ten
       host softmax percentages.  Copy them out of the request area before
       constructing the 32-byte on-card header in the same payload buffer. */
    for (index = 0u; index < 10u; ++index)
        payload[20u + index] = payload[9u + index];
    for (index = 5u; index < 16u; ++index)
        payload[index] = 0u;
    payload[30] = 0u;
    payload[31] = 0u;
    write_u32(&payload[16], calibration_max);
    return model_write_slice(
        sample_section, slot_offset(slot), payload, MODEL_SAMPLE_HEADER_SIZE
    ) == MODEL_OK ? PROTO_OK : PROTO_SD_ERROR;
}

static uint32_t handle_slot_write(uint32_t packed_address) {
    uint32_t slot = packed_address >> 16;
    uint32_t image_offset = packed_address & 0xFFFFu;
    if (!flag_model_ready) return PROTO_NOT_READY;
    if (slot >= active_model->sample_count || length == 0u
        || image_offset >= MODEL_SAMPLE_IMAGE_SIZE
        || length > MODEL_SAMPLE_IMAGE_SIZE - image_offset)
        return PROTO_BAD_SLOT;
    return model_write_slice(
        sample_section,
        slot_offset(slot) + MODEL_SAMPLE_HEADER_SIZE + image_offset,
        payload,
        length
    ) == MODEL_OK ? PROTO_OK : PROTO_SD_ERROR;
}

static uint32_t handle_slot_commit(uint32_t slot) {
    uint32_t expected_image_crc;
    uint32_t image_crc;
    uint32_t record_crc;
    uint32_t index;
    if (!flag_model_ready || length != 4u) return PROTO_NOT_READY;
    if (slot >= active_model->sample_count) return PROTO_BAD_SLOT;
    /* crc_from_sd() uses payload[] as its 64-byte readback scratch buffer.
       Preserve the host CRC before that readback overwrites the request. */
    expected_image_crc = read_u32(payload);
    image_crc = crc_from_sd(
        slot_offset(slot) + MODEL_SAMPLE_HEADER_SIZE,
        MODEL_SAMPLE_IMAGE_SIZE,
        0xFFFFFFFFu
    ) ^ 0xFFFFFFFFu;
    if (image_crc != expected_image_crc) return PROTO_CRC_ERROR;
    if (model_read_slice(sample_section, slot_offset(slot), payload,
                         MODEL_SAMPLE_HEADER_SIZE) != MODEL_OK)
        return PROTO_SD_ERROR;
    payload[5] = 1u;
    write_u32(&payload[8], image_crc);
    write_u32(&payload[12], 0u);
    record_crc = 0xFFFFFFFFu;
    for (index = 0u; index < MODEL_SAMPLE_HEADER_SIZE; ++index)
        record_crc = crc_byte(record_crc, payload[index]);
    record_crc = crc_from_sd(
        slot_offset(slot) + MODEL_SAMPLE_HEADER_SIZE,
        MODEL_SAMPLE_IMAGE_SIZE,
        record_crc
    ) ^ 0xFFFFFFFFu;
    if (record_crc == 0xFFFFFFFFu) return PROTO_SD_ERROR;
    /* crc_from_sd() has reused payload[] again.  Reload the real header before
       committing it; otherwise the final write stores the last image chunk as
       metadata even though the image CRC itself passed. */
    if (model_read_slice(sample_section, slot_offset(slot), payload,
                         MODEL_SAMPLE_HEADER_SIZE) != MODEL_OK)
        return PROTO_SD_ERROR;
    payload[5] = 1u;
    write_u32(&payload[8], image_crc);
    write_u32(&payload[12], record_crc);
    return model_write_slice(
        sample_section, slot_offset(slot), payload, MODEL_SAMPLE_HEADER_SIZE
    ) == MODEL_OK ? PROTO_OK : PROTO_SD_ERROR;
}

static void handle_packet(void) {
    uint32_t status = PROTO_OK;
    uint16_t response_length = 0u;
    uint8_t reboot_after_response = 0u;
    if (command == CMD_STATUS && length == 0u) {
        uint8_t flags = 0x07u;
        if (flag_sd_ready) flags |= 0x08u;
        if (flag_cnn_busy) flags |= 0x10u;
        if ((mmio_read32(UI_HDMI_STATUS) & 1u) != 0u) flags |= 0x20u;
        if (flag_model_ready) flags |= 0x40u;
        payload[0] = 1u;
        payload[1] = flags;
        write_u16(&payload[2], flag_model_ready
            ? (uint16_t)active_model->sample_count : 0u);
        write_u16(&payload[4], MODEL_SAMPLE_RECORD_SIZE);
        payload[6] = 3u;
        payload[7] = 0u;
        response_length = 8u;
    } else if (command == CMD_SLOT_INFO && length == 0u) {
        if (!flag_model_ready) status = PROTO_NOT_READY;
        else if (address >= active_model->sample_count) status = PROTO_BAD_SLOT;
        else if (model_read_slice(sample_section, slot_offset(address), payload,
                                  MODEL_SAMPLE_HEADER_SIZE) != MODEL_OK)
            status = PROTO_SD_ERROR;
        else response_length = MODEL_SAMPLE_HEADER_SIZE;
    } else if (command == CMD_SLOT_BEGIN) {
        status = handle_slot_begin(address);
    } else if (command == CMD_SLOT_WRITE) {
        status = handle_slot_write(address);
    } else if (command == CMD_SLOT_COMMIT) {
        status = handle_slot_commit(address);
    } else if (command == CMD_REBOOT_LOADER && length == 0u) {
        reboot_after_response = 1u;
    } else {
        status = PROTO_BAD_COMMAND;
    }
    send_response(command, status, payload, response_length);
    if (reboot_after_response) {
        volatile uint32_t delay;
        for (delay = 0u; delay < 5000u; ++delay) { }
        mmio_write32(UI_RELOAD_CONTROL, 1u);
    }
}

void runtime_protocol_init(
    model_header_t *model,
    uint8_t sd_ready,
    uint8_t model_ready
) {
    active_model = model;
    flag_sd_ready = sd_ready;
    flag_model_ready = model_ready;
    flag_cnn_busy = 0u;
    sample_section = model_ready ? model_find(model, MODEL_SAMPLE)
                                 : (const model_section_t *)0;
    state = 0u;
    position = 0u;
    uart_init();
}

void runtime_protocol_set_cnn_busy(uint8_t busy) {
    flag_cnn_busy = busy;
}

void runtime_protocol_poll(void) {
    int received = uart_getc_nonblocking();
    uint8_t value;
    if (received < 0) return;
    value = (uint8_t)received;
    switch (state) {
        case 0: if (value == SOF0) state = 1u; break;
        case 1:
            if (value == SOF1) state = 2u;
            else if (value != SOF0) state = 0u;
            break;
        case 2:
            command = value;
            packet_crc = crc_byte(0xFFFFFFFFu, value);
            state = 3u;
            break;
        case 3: address = value; packet_crc = crc_byte(packet_crc, value); state = 4u; break;
        case 4: address |= (uint32_t)value << 8; packet_crc = crc_byte(packet_crc, value); state = 5u; break;
        case 5: address |= (uint32_t)value << 16; packet_crc = crc_byte(packet_crc, value); state = 6u; break;
        case 6: address |= (uint32_t)value << 24; packet_crc = crc_byte(packet_crc, value); state = 7u; break;
        case 7: length = value; packet_crc = crc_byte(packet_crc, value); state = 8u; break;
        case 8:
            length |= (uint16_t)value << 8;
            packet_crc = crc_byte(packet_crc, value);
            position = 0u;
            state = length == 0u ? 10u : 9u;
            if (length > MAX_PAYLOAD) state = 0u;
            break;
        case 9:
            payload[position++] = value;
            packet_crc = crc_byte(packet_crc, value);
            if (position == length) { position = 0u; state = 10u; }
            break;
        case 10: receive_crc = value; state = 11u; break;
        case 11: receive_crc |= (uint32_t)value << 8; state = 12u; break;
        case 12: receive_crc |= (uint32_t)value << 16; state = 13u; break;
        default:
            receive_crc |= (uint32_t)value << 24;
            if (receive_crc == (packet_crc ^ 0xFFFFFFFFu)) handle_packet();
            else send_response(command, PROTO_BAD_PACKET, payload, 0u);
            state = 0u;
            break;
    }
}
