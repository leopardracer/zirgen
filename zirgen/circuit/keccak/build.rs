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

use std::env;

fn main() {
    if env::var("CARGO_FEATURE_PROVE").is_ok()
        && env::var("CARGO_CFG_TARGET_OS").is_ok_and(|os| os == "macos" || os == "ios")
    {
        println!(
            "cargo:rustc-env=KECCAK_METAL_PATH={}",
            env::var("DEP_RISC0_CIRCUIT_KECCAK_SYS_METAL_KERNEL").unwrap()
        );
    }
}
