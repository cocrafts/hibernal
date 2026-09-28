#include <string.h>
#include "rawBytes.h"

static void copyBytes(uint8_t* target, int64_t targetCount, const void* source, int64_t sourceCount, int64_t elementBytes) {
    int64_t bytes = sourceCount * elementBytes;
    memcpy(target, source, (size_t)(bytes < targetCount ? bytes : targetCount));
}

void hibernalPetBytes(uint8_t* target, int64_t targetCount, const void* source, int64_t sourceCount, int64_t elementBytes) {
    copyBytes(target, targetCount, source, sourceCount, elementBytes);
}

void hibernalContextBytes(uint8_t* target, int64_t targetCount, const void* source, int64_t sourceCount, int64_t elementBytes) {
    copyBytes(target, targetCount, source, sourceCount, elementBytes);
}

void hibernalGlobalBytes(uint8_t* target, int64_t targetCount, const void* source, int64_t sourceCount, int64_t elementBytes) {
    copyBytes(target, targetCount, source, sourceCount, elementBytes);
}
