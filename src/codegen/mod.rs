// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Code generation for Alloy models from API specifications.
//
// This module orchestrates the full pipeline:
// 1. Parse API specs (OpenAPI, GraphQL, entity-relation) into entities
// 2. Convert entities to Alloy signatures with typed fields
// 3. Generate complete .als files with sigs, facts, assertions, checks
// 4. Optionally generate analysis scripts for CI/CD integration
//
// Submodules:
// - `parser` — API spec parsing and entity extraction
// - `alloy_gen` — Alloy 6 model generation (.als files)
// - `analyzer` — Analysis command generation and output parsing

pub mod alloy_gen;
pub mod analyzer;
pub mod parser;

use anyhow::{Context, Result};
use std::fs;
use std::path::Path;

use crate::manifest::{Manifest, SpecFormat};

/// Generate all Alloy artifacts from the manifest.
///
/// For each spec in the manifest:
/// 1. Parse the spec file to extract entities
/// 2. Convert entities to Alloy signatures
/// 3. Infer structural facts from the signatures
/// 4. Generate an Alloy model with all sigs, facts, and assertions
/// 5. Write the .als file to the output directory
/// 6. Generate an analysis shell script
///
/// # Arguments
/// * `manifest` — The loaded and validated alloyiser manifest.
/// * `output_dir` — Directory to write generated .als files into.
///
/// # Errors
/// Returns an error if any spec file cannot be read or parsed,
/// or if the output directory cannot be created or written to.
pub fn generate_all(manifest: &Manifest, output_dir: &str) -> Result<()> {
    let out = Path::new(output_dir);
    fs::create_dir_all(out).context("Failed to create output directory")?;

    let mut all_signatures = Vec::new();

    // Parse each spec file and collect signatures
    for spec in &manifest.specs {
        let spec_path = Path::new(&spec.source);
        match spec.format {
            SpecFormat::Openapi => {
                println!("  Parsing OpenAPI spec: {}", spec.source);
                let entities = parser::parse_openapi(spec_path)
                    .with_context(|| format!("Failed to parse spec '{}'", spec.name))?;
                let sigs = parser::entities_to_signatures(&entities);
                println!("    Extracted {} entities", sigs.len());
                all_signatures.extend(sigs);
            }
            SpecFormat::Graphql => {
                println!("  GraphQL parsing: {} (not yet implemented — Phase 2)", spec.source);
                // Phase 2: GraphQL schema parsing
            }
            SpecFormat::EntityRelation => {
                println!("  Entity-relation parsing: {} (not yet implemented — Phase 2)", spec.source);
                // Phase 2: Entity-relation format parsing
            }
        }
    }

    // Infer structural facts from entity relationships
    let structural_facts = alloy_gen::infer_structural_facts(&all_signatures);
    println!("  Inferred {} structural facts", structural_facts.len());

    // Generate the Alloy model
    let mut model = alloy_gen::generate_alloy_model(
        &manifest.project.name,
        &all_signatures,
        manifest,
    );

    // Add inferred structural facts to the model
    for fact in structural_facts {
        model.add_fact(fact);
    }

    // Render and write the .als file
    let als_filename = format!("{}.als", manifest.project.name.replace('-', "_"));
    let als_path = out.join(&als_filename);
    let als_content = alloy_gen::render_als_file(&model, 5);
    fs::write(&als_path, &als_content)
        .with_context(|| format!("Failed to write .als file: {}", als_path.display()))?;
    println!("  Generated: {}", als_path.display());

    // Generate analysis script
    let assertion_names: Vec<String> = manifest
        .assertions
        .iter()
        .map(|a| a.name.replace('-', "_"))
        .collect();
    let script = analyzer::generate_analysis_script(
        &analyzer::AnalyzerConfig {
            solver: manifest.alloy.solver.clone(),
            ..Default::default()
        },
        &als_path,
        &assertion_names,
    );
    let script_path = out.join("run-analysis.sh");
    fs::write(&script_path, &script)
        .with_context(|| format!("Failed to write analysis script: {}", script_path.display()))?;
    println!("  Generated: {}", script_path.display());

    Ok(())
}

/// Build generated artifacts (placeholder for Phase 2).
///
/// In Phase 2, this will invoke the Alloy Analyzer to compile
/// and check the generated models. For now it validates the manifest.
pub fn build(manifest: &Manifest, _release: bool) -> Result<()> {
    println!("Building alloyiser project: {}", manifest.project.name);
    println!("  {} spec(s), {} assertion(s)", manifest.specs.len(), manifest.assertions.len());
    println!("  Solver: {}, max scope: {}", manifest.alloy.solver, manifest.alloy.max_scope);
    println!("  (Automated Alloy compilation is Phase 2 — use 'generate' to create .als files)");
    Ok(())
}

/// Run the Alloy Analyzer on generated models (placeholder for Phase 2).
///
/// In Phase 2, this will invoke the Alloy JAR in batch mode and
/// parse the results. For now it prints instructions for manual analysis.
pub fn run(manifest: &Manifest, _args: &[String]) -> Result<()> {
    println!("alloyiser: project '{}'", manifest.project.name);
    println!();
    println!("To analyse the generated model:");
    println!("  1. Run: alloyiser generate");
    println!("  2. Open the .als file in Alloy Analyzer");
    println!("  3. Execute > Check All Assertions");
    println!();
    println!("Or use the generated run-analysis.sh script (requires java + alloy.jar)");
    Ok(())
}
