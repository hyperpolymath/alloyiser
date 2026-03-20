// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Code generation for Alloy from alloyiser manifest.

use anyhow::{Context, Result};
use std::fs;
use std::path::Path;

use crate::manifest::Manifest;

/// Generate all artifacts: Alloy wrapper, Zig FFI, C headers.
pub fn generate_all(manifest: &Manifest, output_dir: &str) -> Result<()> {
    let out = Path::new(output_dir);
    fs::create_dir_all(out).context("Failed to create output directory")?;
    // TODO: implement Alloy-specific code generation
    println!("  [stub] Alloy codegen for '{}' — implementation pending", manifest.workload.name);
    Ok(())
}

/// Build generated artifacts.
pub fn build(manifest: &Manifest, _release: bool) -> Result<()> {
    println!("Building {} workload: {}", "alloyiser", manifest.workload.name);
    // TODO: invoke Alloy compiler
    Ok(())
}

/// Run the workload.
pub fn run(manifest: &Manifest, _args: &[String]) -> Result<()> {
    println!("Running {} workload: {}", "alloyiser", manifest.workload.name);
    // TODO: execute generated binary
    Ok(())
}
