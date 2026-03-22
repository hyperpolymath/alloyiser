#![forbid(unsafe_code)]
// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// alloyiser library API.
//
// Public interface for programmatic use of alloyiser. Exposes the manifest
// parser, codegen pipeline, ABI types, and analysis utilities so that
// other -iser tools or CI/CD integrations can drive alloyiser programmatically.

pub mod abi;
pub mod codegen;
pub mod manifest;

pub use abi::{AlloyField, AlloyModel, Assertion, Counterexample, Fact, ModelCheckResult, Multiplicity, Signature};
pub use manifest::{load_manifest, validate, Manifest};

/// Convenience: load, validate, and generate all Alloy artifacts.
///
/// This is the simplest way to use alloyiser as a library:
/// provide a manifest path and an output directory, and it handles
/// the entire pipeline (parse specs, extract entities, generate .als).
///
/// # Arguments
/// * `manifest_path` — Path to the `alloyiser.toml` file.
/// * `output_dir` — Directory to write generated `.als` files into.
///
/// # Errors
/// Returns an error if the manifest cannot be loaded/validated or
/// if code generation fails.
pub fn generate(manifest_path: &str, output_dir: &str) -> anyhow::Result<()> {
    let m = load_manifest(manifest_path)?;
    validate(&m)?;
    codegen::generate_all(&m, output_dir)?;
    Ok(())
}
