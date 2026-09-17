#include <string.h>
#include "buffer.h"

void hibernalCopyOut(void* target, const int32_t* source, int32_t count) {
    memcpy(target, source, (size_t)count * sizeof(int32_t));
}

int32_t hibernalPeek(const void* source, int32_t index) {
    return ((const int32_t*)source)[index];
}

int32_t hibernalPeekByte(const void* source, int32_t index) {
    return ((const uint8_t*)source)[index];
}
