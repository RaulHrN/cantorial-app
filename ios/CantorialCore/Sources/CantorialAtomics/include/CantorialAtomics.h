#ifndef CANTORIAL_ATOMICS_H
#define CANTORIAL_ATOMICS_H

#include <stdint.h>

// Release/acquire access to a 64-bit counter shared between the audio thread and the UI.
// The audio thread writes a ring buffer slot and then publishes the new frame count with a
// release store; readers load the count with acquire and then see the slot contents.

static inline void cantorial_store_release(int64_t *p, int64_t v) {
    __atomic_store_n(p, v, __ATOMIC_RELEASE);
}

static inline int64_t cantorial_load_acquire(const int64_t *p) {
    return __atomic_load_n(p, __ATOMIC_ACQUIRE);
}

#endif
