#ifndef CSMC_H
#define CSMC_H

#include <stdint.h>

// All functions return 0 on success.
int smc_open(void);
int smc_key_count(uint32_t *count);
int smc_key_at(uint32_t index, uint32_t *key);
int smc_info(uint32_t key, uint32_t *type, uint32_t *size);
int smc_read(uint32_t key, uint8_t *bytes, uint32_t size);
int smc_write(uint32_t key, const uint8_t *bytes, uint32_t size); // needs root

// Cumulative busy/idle scheduler ticks per logical CPU. Returns the CPU count, or -1.
int cpu_ticks(uint32_t *busy, uint32_t *idle, int max);

#endif
