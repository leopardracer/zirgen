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

#pragma once

#include "zirgen/circuit/recursion/encode.h"
#include "zirgen/circuit/recursion/test/runner.h"

#include <gtest/gtest.h>

namespace zirgen::recursion {

// A function for A/B testing of code.  Basically we run the code both directly
// in the interpreter, and then again after encoding it to microcode for the
// recursion circuit and running it again there.  Afterwords, we use the fact
// that we know the mlir::Value map for both systems to compare all the
// intermediate values across both executions and show the user where the first
// divergence was (if anywhere).
template <size_t N = 2, typename Func>
void doAB(HashType hashType, const std::vector<std::vector<uint32_t>>& proofs, Func userFunc) {
  std::array<ArgumentInfo, N> argTypes;
  argTypes[0] = gbuf(kOutSize);
  for (size_t i = 1; i != N; ++i) {
    argTypes[i] = ioparg();
  }
  assert(1 + proofs.size() == N);
  Module module;
  module.addFunc<N>("test", std::move(argTypes), userFunc);
  module.optimize();
  // module.dump();
  auto func = module.getModule().lookupSymbol<mlir::func::FuncOp>("test");

  bool worked = true;

  // Run the code directly in the interpreter
  Zll::ExternHandler baseExternHandler;
  std::unique_ptr<IHashSuite> hash;
  switch (hashType) {
  case HashType::SHA256:
    hash = shaHashSuite();
    break;
  case HashType::POSEIDON2:
    hash = poseidon2HashSuite();
    break;
  case HashType::MIXED_POSEIDON2_SHA:
    hash = mixedPoseidon2ShaHashSuite();
    break;
  }
  Zll::Interpreter interp(module.getCtx(), std::move(hash));
  interp.setExternHandler(&baseExternHandler);
  auto outBuf = interp.makeBuf(func.getArgument(0), kOutSize, Zll::BufferKind::Global);
  std::vector<std::unique_ptr<ReadIop>> riops;
  size_t iopIndex = 1;
  for (const auto& proof : proofs) {
    auto rng = interp.getHashSuite().makeRng();
    riops.emplace_back(new ReadIop(std::move(rng), proof.data(), proof.size()));
    interp.setIop(func.getArgument(iopIndex++), &*riops.back());
  }
  if (failed(interp.runBlock(func.front())))
    FAIL() << "failed to evaluate block in interpreter";
  auto directOut = outBuf[0];

  // Now encode it as microcode for the recursion circuit and run there
  Runner runner;
  llvm::DenseMap<mlir::Value, uint64_t> toId;
  std::vector<uint32_t> code = encode(hashType, &func.front(), &toId);
  llvm::errs() << "CYCLES = " << (code.size() / kCodeSize) << "\n";

  // 'Reverse' toId so that it is in execution order
  std::map<uint64_t, mlir::Value> toValue;
  for (auto kvp : toId) {
    toValue[kvp.second] = kvp.first;
  }

  // The circuit doesn't know how to distinguish different IOP
  // arguments to read from, so we have to put them in the order that
  // is expected and just concatenate them.
  std::vector<uint32_t> allProofsTogether;
  for (const auto& proof : proofs) {
    allProofsTogether.insert(allProofsTogether.end(), proof.begin(), proof.end());
  }

  // Run it as microcode
  runner.setup(code, allProofsTogether);
  try {
    runner.run();
    llvm::errs() << "IT RAN TO COMPLETION"
                 << "\n";
  } catch (const std::runtime_error& err) {
    llvm::errs() << "CATCHING EXCEPTION: " << err.what() << "\n";
    // Recover on error so we can compare values + find the first divergence
    worked = false;
  }

  // Now, go over all the values in WOM and check them against the earlier run
  for (auto kvp : toValue) {
    uint64_t id = kvp.first;
    mlir::Value value = kvp.second;
    mlir::Type type = value.getType();
    if (llvm::isa<Zll::ValType>(type)) {
      auto valA = interp.getVal(value);
      auto valB = runner.handler->state[id];
      for (size_t i = 0; i < valA.size(); i++) {
        if (valA[i] != valB[i]) {
          llvm::errs() << "MISMATCH on value generated by:\n";
          llvm::errs() << *value.getDefiningOp() << "\n";
          llvm::errs() << "  " << valA[i] << " vs " << valB[i] << "\n";
        }
        ASSERT_EQ(valA[i], valB[i]);
      }
    }
    if (llvm::isa<Zll::DigestType>(type)) {
      Digest digestA = interp.getDigest(value);
      for (size_t i = 0; i < 8; i++) {
        uint32_t wordA = digestA.words[i];
        auto womB = runner.handler->state[id + i];
        uint32_t wordB = womB[0] | (womB[1] << 16);
        if (wordA != wordB) {
          llvm::errs() << "MISMATCH on value generated by:\n";
          llvm::errs() << *value.getDefiningOp() << "\n";
          llvm::errs() << "i = " << i << "\n";
          llvm::errs() << "wordA = " << wordA << "\n";
          llvm::errs() << "womB[0] = " << womB[0] << ", womB[1] = " << womB[1] << "\n";
        }
        ASSERT_EQ(wordA, wordB);
      }
    }
  }

  auto runnerOut = runner.out[0];
  runnerOut.resize(directOut.size());
  runner.done();

  // Make sure we didn't catch an error
  ASSERT_EQ(worked, true);

  // Check final output values match
  ASSERT_EQ(directOut, runnerOut);
}

} // namespace zirgen::recursion

// Hello
