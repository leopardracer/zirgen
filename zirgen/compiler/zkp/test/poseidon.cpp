// Copyright 2024 RISC Zero, Inc.
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

#include "zirgen/compiler/zkp/poseidon.h"
#include "zirgen/compiler/zkp/baby_bear.h"
#include <gtest/gtest.h>

namespace zirgen {

TEST(zkp, poseidon) {
  uint32_t input[16];
  for (uint32_t i = 0; i < 16; i++) {
    input[i] = i;
  }
  Digest out = poseidonHash(input, 16);

  Digest goal = {toMontgomery(165799421),
                 toMontgomery(446443103),
                 toMontgomery(1242624592),
                 toMontgomery(791266679),
                 toMontgomery(1939888497),
                 toMontgomery(1437820613),
                 toMontgomery(893076101),
                 toMontgomery(95764709)};
  ASSERT_EQ(out, goal);
}

} // namespace zirgen
