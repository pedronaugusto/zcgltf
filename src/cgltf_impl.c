/*
 * zcgltf — the one translation unit. cgltf is implementation-in-header;
 * this file instantiates parser and writer together, exactly once.
 * cgltf_write.h includes cgltf.h itself, so one include serves both.
 */
#define CGLTF_IMPLEMENTATION
#define CGLTF_WRITE_IMPLEMENTATION
#include "cgltf_write.h"
