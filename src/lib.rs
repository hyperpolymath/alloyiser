#![forbid(unsafe_code)]
#![allow(
    dead_code,
    clippy::too_many_arguments,
    clippy::manual_strip,
    clippy::if_same_then_else,
    clippy::vec_init_then_push,
    clippy::upper_case_acronyms,
    clippy::format_in_format_args,
    clippy::enum_variant_names,
    clippy::module_inception,
    clippy::doc_lazy_continuation,
    clippy::manual_clamp,
    clippy::type_complexity,
    clippy::needless_range_loop
)]
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

pub use abi::{
    AlloyField, AlloyModel, Assertion, Counterexample, Fact, ModelCheckResult, Multiplicity,
    Signature,
};
pub use manifest::{Manifest, load_manifest, validate};

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
