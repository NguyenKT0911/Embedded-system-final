#include <stddef.h>
#include <stdint.h>

void *memset(void *destination, int value, size_t count) {
    uint8_t *out = (uint8_t *)destination;
    while (count-- != 0u) {
        *out++ = (uint8_t)value;
    }
    return destination;
}

void *memcpy(void *destination, const void *source, size_t count) {
    uint8_t *out = (uint8_t *)destination;
    const uint8_t *in = (const uint8_t *)source;
    while (count-- != 0u) {
        *out++ = *in++;
    }
    return destination;
}

uint32_t __udivsi3(uint32_t numerator, uint32_t denominator) {
    uint32_t quotient = 0u;
    uint32_t remainder = 0u;
    unsigned bit;
    if (denominator == 0u) {
        return 0xFFFFFFFFu;
    }
    for (bit = 32u; bit != 0u; --bit) {
        remainder = (remainder << 1) | ((numerator >> (bit - 1u)) & 1u);
        if (remainder >= denominator) {
            remainder -= denominator;
            quotient |= 1u << (bit - 1u);
        }
    }
    return quotient;
}

uint32_t __umodsi3(uint32_t numerator, uint32_t denominator) {
    uint32_t remainder = 0u;
    unsigned bit;
    if (denominator == 0u) {
        return numerator;
    }
    for (bit = 32u; bit != 0u; --bit) {
        remainder = (remainder << 1) | ((numerator >> (bit - 1u)) & 1u);
        if (remainder >= denominator) {
            remainder -= denominator;
        }
    }
    return remainder;
}

int32_t __divsi3(int32_t numerator, int32_t denominator) {
    uint32_t un;
    uint32_t ud;
    uint32_t quotient;
    uint32_t negative;
    if (denominator == 0) {
        return numerator < 0 ? (int32_t)0x80000000u : 0x7FFFFFFF;
    }
    negative = ((uint32_t)numerator ^ (uint32_t)denominator) >> 31;
    un = numerator < 0 ? (uint32_t)(-numerator) : (uint32_t)numerator;
    ud = denominator < 0 ? (uint32_t)(-denominator) : (uint32_t)denominator;
    quotient = __udivsi3(un, ud);
    return negative != 0u ? -(int32_t)quotient : (int32_t)quotient;
}

int32_t __modsi3(int32_t numerator, int32_t denominator) {
    uint32_t un;
    uint32_t ud;
    uint32_t remainder;
    if (denominator == 0) {
        return numerator;
    }
    un = numerator < 0 ? (uint32_t)(-numerator) : (uint32_t)numerator;
    ud = denominator < 0 ? (uint32_t)(-denominator) : (uint32_t)denominator;
    remainder = __umodsi3(un, ud);
    return numerator < 0 ? -(int32_t)remainder : (int32_t)remainder;
}

