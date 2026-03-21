// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// alloyiser CLI — Extract formal models from API specs and verify with Alloy.
//
// alloyiser takes API specifications (OpenAPI, GraphQL, entity-relation),
// extracts entities and relationships, generates Alloy 6 models (.als files),
// and supports verification of invariants via the Alloy Analyzer (SAT solver).
//
// Part of the hyperpolymath -iser family. See README.adoc for architecture.

use anyhow::Result;
use clap::{Parser, Subcommand};

mod abi;
mod codegen;
mod manifest;

/// alloyiser — Formal model checking via Alloy
///
/// Extract entities from API specs, generate Alloy 6 models,
/// and verify invariants before code is written.
#[derive(Parser)]
#[command(name = "alloyiser", version, about, long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

/// Available subcommands for the alloyiser CLI.
#[derive(Subcommand)]
enum Commands {
    /// Initialise a new alloyiser.toml manifest in the current directory.
    ///
    /// Creates a starter manifest with example specs and assertions.
    Init {
        /// Directory to create the manifest in (defaults to current directory).
        #[arg(short, long, default_value = ".")]
        path: String,
    },
    /// Validate an alloyiser.toml manifest.
    ///
    /// Checks that all required fields are present and values are sensible.
    Validate {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "alloyiser.toml")]
        manifest: String,
    },
    /// Generate Alloy .als model files from API specs and assertions.
    ///
    /// Parses each spec in the manifest, extracts entities, and generates
    /// a complete Alloy 6 model with sigs, facts, assertions, and checks.
    Generate {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "alloyiser.toml")]
        manifest: String,
        /// Output directory for generated .als files.
        #[arg(short, long, default_value = "generated/alloyiser")]
        output: String,
    },
    /// Build generated artifacts (Phase 2: invoke Alloy Analyzer).
    Build {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "alloyiser.toml")]
        manifest: String,
        /// Build in release mode (optimised).
        #[arg(long)]
        release: bool,
    },
    /// Run analysis on generated models (Phase 2: automated checking).
    Run {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "alloyiser.toml")]
        manifest: String,
        /// Additional arguments passed to the Alloy Analyzer.
        #[arg(trailing_var_arg = true)]
        args: Vec<String>,
    },
    /// Show information about a manifest: specs, assertions, solver config.
    Info {
        /// Path to the manifest file.
        #[arg(short, long, default_value = "alloyiser.toml")]
        manifest: String,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Commands::Init { path } => {
            println!("Initialising alloyiser manifest in: {}", path);
            manifest::init_manifest(&path)?;
        }
        Commands::Validate { manifest } => {
            let m = manifest::load_manifest(&manifest)?;
            manifest::validate(&m)?;
            println!("Manifest valid: {}", m.project.name);
        }
        Commands::Generate { manifest, output } => {
            let m = manifest::load_manifest(&manifest)?;
            manifest::validate(&m)?;
            codegen::generate_all(&m, &output)?;
            println!("Generated Alloy artifacts in: {}", output);
        }
        Commands::Build { manifest, release } => {
            let m = manifest::load_manifest(&manifest)?;
            codegen::build(&m, release)?;
        }
        Commands::Run { manifest, args } => {
            let m = manifest::load_manifest(&manifest)?;
            codegen::run(&m, &args)?;
        }
        Commands::Info { manifest } => {
            let m = manifest::load_manifest(&manifest)?;
            manifest::print_info(&m);
        }
    }
    Ok(())
}
