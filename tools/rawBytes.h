#ifndef HIBERNAL_RAW_BYTES_H
#define HIBERNAL_RAW_BYTES_H

#include <stdint.h>

void hibernalPetBytes(uint8_t* target, int64_t targetCount, const void* source, int64_t sourceCount, int64_t elementBytes);
void hibernalContextBytes(uint8_t* target, int64_t targetCount, const void* source, int64_t sourceCount, int64_t elementBytes);
void hibernalGlobalBytes(uint8_t* target, int64_t targetCount, const void* source, int64_t sourceCount, int64_t elementBytes);

#endif
