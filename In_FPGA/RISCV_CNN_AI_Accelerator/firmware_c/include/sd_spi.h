#ifndef SD_SPI_H
#define SD_SPI_H

#include <stdint.h>

enum {
    SD_OK = 0,
    SD_ERR_TIMEOUT = -1,
    SD_ERR_CMD0 = -2,
    SD_ERR_CMD8 = -3,
    SD_ERR_ACMD41 = -4,
    SD_ERR_READ = -5,
    SD_ERR_TOKEN = -6,
    SD_ERR_WRITE = -7,
    SD_ERR_VERIFY = -8
};

int sd_init(void);
int sd_read_sector(uint32_t sector, uint8_t data[512]);
int sd_write_sector(uint32_t sector, const uint8_t data[512]);
int sd_write_sector_verified(uint32_t sector, const uint8_t data[512]);

#endif

