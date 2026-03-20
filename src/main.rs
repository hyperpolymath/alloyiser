// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// alloyiser CLI — Formal model checking via Alloy
// Part of the hyperpolymath -iser family. See README.adoc for architecture.

use anyhow::Result;
use clap::{Parser, Subcommand};

mod codegen;
mod manifest;

/// alloyiser — Formal model checking via Alloy
#[derive(Parser)]
#[command(name = "alloyiser", version, about, long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

/// Available subcommands.
#[derive(Subcommand)]
enum Commands {
    /// Initialise a new alloyiser.toml manifest in the current directory.
    Init {
        #[arg(short, long, default_value = ".")]
        path: String,
    },
    /// Validate a alloyiser.toml manifest.
    Validate {
        #[arg(short, long, default_value = "alloyiser.toml")]
        manifest: String,
    },
    /// Generate Alloy wrapper, Zig FFI bridge, and C headers from the manifest.
    Generate {
        #[arg(short, long, default_value = "alloyiser.toml")]
        manifest: String,
        #[arg(short, long, default_value = "generated/alloyiser")]
        output: String,
    },
    /// Build the generated artifacts.
    Build {
        #[arg(short, long, default_value = "alloyiser.toml")]
        manifest: String,
        #[arg(long)]
        release: bool,
    },
    /// Run the alloyiserd workload.
    Run {
        #[arg(short, long, default_value = "alloyiser.toml")]
        manifest: String,
        #[arg(trailing_var_arg = true)]
        args: Vec<String>,
    },
    /// Show information about a manifest.
    Info {
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
            println!("Manifest valid: {}", m.workload.name);
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
