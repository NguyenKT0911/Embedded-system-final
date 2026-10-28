#ifndef MEMORY_MAP_H
#define MEMORY_MAP_H

#include <stdint.h>

#define RESULT_BASE 0x10000000u
#define UART_BASE   0x20000000u
#define SD_BASE     0x30000000u
#define ACCEL_BASE  0x40000000u
#define UI_BASE     0x50000000u
#define DMEM_BASE   0x80000000u
#define DMEM_BYTES  (8u * 1024u)

static inline void mmio_write32(uint32_t address, uint32_t value) {
    *(volatile uint32_t *)(uintptr_t)address = value;
}

static inline uint32_t mmio_read32(uint32_t address) {
    return *(volatile uint32_t *)(uintptr_t)address;
}

#endif

