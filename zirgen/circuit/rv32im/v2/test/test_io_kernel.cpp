// Copyright 2025 RISC Zero, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include <stdint.h>
#include <sys/errno.h>

#include "zirgen/circuit/rv32im/v2/platform/constants.h"

using namespace zirgen::rv32im_v2;

inline void die() {
  asm("fence\n");
}

// Implement machine mode ECALLS

inline void terminate(uint32_t val) {
  register uintptr_t a0 asm("a0") = val;
  register uintptr_t a7 asm("a7") = 0;
  asm volatile("ecall\n"
               :                  // no outputs
               : "r"(a0), "r"(a7) // inputs
               :                  // no clobbers
  );
}

inline uint32_t host_read(uint32_t fd, uint32_t buf, uint32_t len) {
  register uintptr_t a0 asm("a0") = fd;
  register uintptr_t a1 asm("a1") = buf;
  register uintptr_t a2 asm("a2") = len;
  register uintptr_t a7 asm("a7") = 1;
  asm volatile("ecall\n"
               : "+r"(a0)                           // outputs
               : "r"(a0), "r"(a1), "r"(a2), "r"(a7) // inputs
               :                                    // no clobbers
  );
  return a0;
}

inline uint32_t host_write(uint32_t fd, uint32_t buf, uint32_t len) {
  register uintptr_t a0 asm("a0") = fd;
  register uintptr_t a1 asm("a1") = buf;
  register uintptr_t a2 asm("a2") = len;
  register uintptr_t a7 asm("a7") = 2;
  asm volatile("ecall\n"
               : "+r"(a0)                           // outputs
               : "r"(a0), "r"(a1), "r"(a2), "r"(a7) // inputs
               :                                    // no clobbers
  );
  return a0;
}

constexpr uint32_t sizes[11] = {0, 1, 2, 3, 4, 5, 7, 13, 19, 40, 101};

void test_multi_read() {
  uint8_t buf[200];
  // Try all 4 alignments
  for (size_t i = 0; i < 4; i++) {
    // Try a variety of size
    for (size_t j = 0; j < 11; j++) {
      host_read(0, (uint32_t)(buf + i), sizes[j]);
      for (size_t k = 0; k < sizes[j]; k++) {
        if (buf[i + k] != k) {
          die();
        }
      }
    }
  }
}

extern "C" void start() {
  test_multi_read();
  terminate(0);
}
