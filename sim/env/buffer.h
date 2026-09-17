#ifndef HIBERNAL_BUFFER_H
#define HIBERNAL_BUFFER_H

#include <stdint.h>

void hibernalCopyOut(void* target, const int32_t* source, int32_t count);
int32_t hibernalPeek(const void* source, int32_t index);
int32_t hibernalPeekByte(const void* source, int32_t index);

#endif
