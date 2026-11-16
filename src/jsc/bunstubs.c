// Symbols that Bun's WebKit fork expects the embedder (Bun) to define.
// slivar never trims JSC features, so the state is all zeros (= "Present", not trimmed).
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
__attribute__((aligned(8))) const uint8_t Bun__removableFeatureState[536] = {0};
void Bun__abortForRemovedFeature(uint16_t f) { fprintf(stderr, "jsc: removed feature %u\n", f); abort(); }
uint64_t Bun__throwForRemovedFeature(void* g, uint16_t f) { Bun__abortForRemovedFeature(f); return 0; }
uint64_t Bun__throwForRemovedBuiltin(void* g, uint16_t f, uint32_t b) { Bun__abortForRemovedFeature(f); return 0; }
uint64_t Bun__throwForRemovedFunction(void* g, uint16_t f, void* n) { Bun__abortForRemovedFeature(f); return 0; }
