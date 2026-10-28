#include "memory_map.h"
#include "sd_spi.h"

#define SD_CONTROL (SD_BASE + 0x00u)
#define SD_STATUS  (SD_BASE + 0x04u)
#define SD_DATA    (SD_BASE + 0x08u)
#define SD_DIVIDER (SD_BASE + 0x0Cu)

#define STATUS_BUSY     0x1u
#define STATUS_RX_VALID 0x2u
#define SD_TIMEOUT      200000u

static uint8_t card_is_sdhc;
static uint8_t verify_buffer[512];

static void sd_chip_select(int asserted) {
    mmio_write32(SD_CONTROL, asserted ? 0u : 1u);
}

static int spi_transfer(uint8_t tx, uint8_t *rx) {
    uint32_t timeout = SD_TIMEOUT;
    while ((mmio_read32(SD_STATUS) & STATUS_BUSY) != 0u) {
        if (--timeout == 0u) {
            return SD_ERR_TIMEOUT;
        }
    }
    mmio_write32(SD_DATA, tx);
    timeout = SD_TIMEOUT;
    while ((mmio_read32(SD_STATUS) & STATUS_RX_VALID) == 0u) {
        if (--timeout == 0u) {
            return SD_ERR_TIMEOUT;
        }
    }
    *rx = (uint8_t)mmio_read32(SD_DATA);
    return SD_OK;
}

static int sd_wait_ready(void) {
    uint32_t count;
    uint8_t value;
    for (count = 0u; count < 10000u; ++count) {
        if (spi_transfer(0xFFu, &value) != SD_OK) {
            return SD_ERR_TIMEOUT;
        }
        if (value == 0xFFu) {
            return SD_OK;
        }
    }
    return SD_ERR_TIMEOUT;
}

static int sd_command(uint8_t command, uint32_t argument, uint8_t crc, uint8_t *r1) {
    uint8_t value;
    unsigned index;
    if (sd_wait_ready() != SD_OK) {
        return SD_ERR_TIMEOUT;
    }
    spi_transfer((uint8_t)(0x40u | command), &value);
    spi_transfer((uint8_t)(argument >> 24), &value);
    spi_transfer((uint8_t)(argument >> 16), &value);
    spi_transfer((uint8_t)(argument >> 8), &value);
    spi_transfer((uint8_t)argument, &value);
    spi_transfer((uint8_t)(crc | 1u), &value);
    for (index = 0u; index < 10u; ++index) {
        if (spi_transfer(0xFFu, &value) != SD_OK) {
            return SD_ERR_TIMEOUT;
        }
        if ((value & 0x80u) == 0u) {
            *r1 = value;
            return SD_OK;
        }
    }
    return SD_ERR_TIMEOUT;
}

int sd_init(void) {
    uint8_t value;
    uint8_t r1;
    uint8_t ocr[4];
    unsigned index;
    uint32_t attempts;

    card_is_sdhc = 0u;
    mmio_write32(SD_DIVIDER, 7u);
    sd_chip_select(0);
    for (index = 0u; index < 10u; ++index) {
        if (spi_transfer(0xFFu, &value) != SD_OK) {
            return SD_ERR_TIMEOUT;
        }
    }

    sd_chip_select(1);
    if (sd_command(0u, 0u, 0x95u, &r1) != SD_OK || r1 != 0x01u) {
        sd_chip_select(0);
        return SD_ERR_CMD0;
    }

    if (sd_command(8u, 0x1AAu, 0x87u, &r1) != SD_OK) {
        sd_chip_select(0);
        return SD_ERR_CMD8;
    }
    if (r1 == 0x01u) {
        for (index = 0u; index < 4u; ++index) {
            spi_transfer(0xFFu, &ocr[index]);
        }
        if (ocr[2] != 0x01u || ocr[3] != 0xAAu) {
            sd_chip_select(0);
            return SD_ERR_CMD8;
        }
    }

    for (attempts = 0u; attempts < 10000u; ++attempts) {
        if (sd_command(55u, 0u, 0x01u, &r1) != SD_OK) {
            sd_chip_select(0);
            return SD_ERR_ACMD41;
        }
        if (sd_command(41u, 0x40000000u, 0x01u, &r1) != SD_OK) {
            sd_chip_select(0);
            return SD_ERR_ACMD41;
        }
        if (r1 == 0u) {
            break;
        }
    }
    if (r1 != 0u) {
        sd_chip_select(0);
        return SD_ERR_ACMD41;
    }

    if (sd_command(58u, 0u, 0x01u, &r1) != SD_OK || r1 != 0u) {
        sd_chip_select(0);
        return SD_ERR_READ;
    }
    for (index = 0u; index < 4u; ++index) {
        spi_transfer(0xFFu, &ocr[index]);
    }
    card_is_sdhc = (ocr[0] & 0x40u) != 0u;
    sd_chip_select(0);
    spi_transfer(0xFFu, &value);
    // At the 5.4 MHz SoC clock, divider 0 gives a conservative 2.7 MHz
    // post-initialization SPI clock while halving model load time.
    mmio_write32(SD_DIVIDER, 0u);
    return SD_OK;
}

int sd_read_sector(uint32_t sector, uint8_t data[512]) {
    uint32_t address = card_is_sdhc ? sector : (sector << 9);
    uint32_t timeout;
    uint8_t r1;
    uint8_t value;
    unsigned index;

    sd_chip_select(1);
    if (sd_command(17u, address, 0x01u, &r1) != SD_OK || r1 != 0u) {
        sd_chip_select(0);
        return SD_ERR_READ;
    }
    timeout = 100000u;
    do {
        if (spi_transfer(0xFFu, &value) != SD_OK) {
            sd_chip_select(0);
            return SD_ERR_TIMEOUT;
        }
        if (value == 0xFEu) {
            break;
        }
    } while (--timeout != 0u);
    if (value != 0xFEu) {
        sd_chip_select(0);
        return SD_ERR_TOKEN;
    }
    for (index = 0u; index < 512u; ++index) {
        if (spi_transfer(0xFFu, &data[index]) != SD_OK) {
            sd_chip_select(0);
            return SD_ERR_TIMEOUT;
        }
    }
    spi_transfer(0xFFu, &value);
    spi_transfer(0xFFu, &value);
    sd_chip_select(0);
    spi_transfer(0xFFu, &value);
    return SD_OK;
}

int sd_write_sector(uint32_t sector, const uint8_t data[512]) {
    uint32_t address = card_is_sdhc ? sector : (sector << 9);
    uint8_t r1;
    uint8_t value;
    unsigned index;

    sd_chip_select(1);
    if (sd_command(24u, address, 0x01u, &r1) != SD_OK || r1 != 0u) {
        sd_chip_select(0);
        return SD_ERR_WRITE;
    }
    if (spi_transfer(0xFFu, &value) != SD_OK
        || spi_transfer(0xFEu, &value) != SD_OK) {
        sd_chip_select(0);
        return SD_ERR_TIMEOUT;
    }
    for (index = 0u; index < 512u; ++index) {
        if (spi_transfer(data[index], &value) != SD_OK) {
            sd_chip_select(0);
            return SD_ERR_TIMEOUT;
        }
    }
    if (spi_transfer(0xFFu, &value) != SD_OK
        || spi_transfer(0xFFu, &value) != SD_OK
        || spi_transfer(0xFFu, &value) != SD_OK) {
        sd_chip_select(0);
        return SD_ERR_TIMEOUT;
    }
    if ((value & 0x1Fu) != 0x05u) {
        sd_chip_select(0);
        return SD_ERR_WRITE;
    }
    if (sd_wait_ready() != SD_OK) {
        sd_chip_select(0);
        return SD_ERR_TIMEOUT;
    }
    sd_chip_select(0);
    spi_transfer(0xFFu, &value);
    return SD_OK;
}

int sd_write_sector_verified(uint32_t sector, const uint8_t data[512]) {
    unsigned index;
    int status = sd_write_sector(sector, data);
    if (status != SD_OK) return status;
    status = sd_read_sector(sector, verify_buffer);
    if (status != SD_OK) return status;
    for (index = 0u; index < 512u; ++index) {
        if (verify_buffer[index] != data[index]) return SD_ERR_VERIFY;
    }
    return SD_OK;
}
