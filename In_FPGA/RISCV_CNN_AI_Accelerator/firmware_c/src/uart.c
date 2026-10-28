#include "memory_map.h"
#include "uart.h"

#define UART_RX_DATA (UART_BASE + 0x00u)
#define UART_TX_DATA (UART_BASE + 0x04u)
#define UART_STATUS  (UART_BASE + 0x08u)
#define UART_CONTROL (UART_BASE + 0x0Cu)

#define UART_RX_VALID 0x1u
#define UART_TX_READY 0x2u

void uart_init(void) {
    mmio_write32(UART_CONTROL, 0x3u);
}

void uart_putc(char value) {
    while ((mmio_read32(UART_STATUS) & UART_TX_READY) == 0u) {
    }
    mmio_write32(UART_TX_DATA, (uint32_t)(uint8_t)value);
}

void uart_puts(const char *text) {
    while (*text != '\0') {
        uart_putc(*text++);
    }
}

void uart_put_hex32(uint32_t value) {
    static const char hex[] = "0123456789ABCDEF";
    unsigned shift;
    uart_puts("0x");
    for (shift = 32u; shift != 0u; shift -= 4u) {
        uart_putc(hex[(value >> (shift - 4u)) & 0xFu]);
    }
}

int uart_getc_nonblocking(void) {
    if ((mmio_read32(UART_STATUS) & UART_RX_VALID) == 0u) {
        return -1;
    }
    return (int)(mmio_read32(UART_RX_DATA) & 0xFFu);
}

char uart_getc(void) {
    int value;
    do {
        value = uart_getc_nonblocking();
    } while (value < 0);
    return (char)value;
}

