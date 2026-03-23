// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Manifest parser for alloyiser.toml.
//
// The manifest defines which API specs to analyse, what assertions to check,
// and how to configure the Alloy solver. It supports OpenAPI, GraphQL, and
// entity-relation formats as input specifications.

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::path::Path;

/// Top-level alloyiser manifest.
///
/// Corresponds to the `alloyiser.toml` file that users create to describe
/// their API specifications and the invariants they want to verify.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Manifest {
    /// Project-level metadata.
    pub project: ProjectConfig,
    /// API specifications to extract entities from.
    #[serde(default)]
    pub specs: Vec<SpecEntry>,
    /// Assertions (invariants) to verify against the extracted model.
    #[serde(default)]
    pub assertions: Vec<AssertionEntry>,
    /// Alloy solver configuration.
    #[serde(default)]
    pub alloy: AlloyConfig,
}

/// Project metadata section.
///
/// Identifies the project being verified. The name is used as the
/// Alloy module name in generated `.als` files.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectConfig {
    /// The project name, used as the Alloy module identifier.
    pub name: String,
}

/// An API specification entry pointing to a file and its format.
///
/// Each spec entry tells alloyiser where to find the API definition
/// and what format it uses, so the correct parser can be invoked.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpecEntry {
    /// Human-readable name for this spec, e.g. "user-api".
    pub name: String,
    /// Path to the spec file relative to the manifest, e.g. "openapi.yaml".
    pub source: String,
    /// The spec format: "openapi", "graphql", or "entity-relation".
    pub format: SpecFormat,
}

/// Supported API specification formats.
///
/// Each format has its own parser in the codegen module that extracts
/// entities (signatures) and relationships (fields) from the spec.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "kebab-case")]
pub enum SpecFormat {
    /// OpenAPI 3.x (YAML or JSON) — extracts from schemas and paths.
    Openapi,
    /// GraphQL schema — extracts from types and fields.
    Graphql,
    /// Entity-relation description — a simpler custom format.
    EntityRelation,
}

/// An assertion entry: a named invariant with an Alloy check expression.
///
/// Assertions are the core value proposition of alloyiser — they express
/// properties that the API model must satisfy, and the Alloy analyzer
/// attempts to find counterexamples.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AssertionEntry {
    /// Human-readable name for the assertion, e.g. "no-orphan-posts".
    pub name: String,
    /// The Alloy expression to check, e.g. "all p: Post | some p.author".
    pub check: String,
    /// The Alloy scope (max atoms per signature) for this check.
    /// Larger scopes find more bugs but take exponentially longer.
    #[serde(default = "default_scope")]
    pub scope: u32,
}

/// Alloy solver configuration.
///
/// Controls which SAT solver backend to use and the maximum scope
/// for analysis commands.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AlloyConfig {
    /// The SAT solver to use: "sat4j" (default), "minisat", or "glucose".
    #[serde(default = "default_solver")]
    pub solver: String,
    /// The maximum scope allowed for any check command.
    #[serde(rename = "max-scope", default = "default_max_scope")]
    pub max_scope: u32,
}

impl Default for AlloyConfig {
    fn default() -> Self {
        AlloyConfig {
            solver: default_solver(),
            max_scope: default_max_scope(),
        }
    }
}

/// Default scope for assertions: 5 atoms per signature.
fn default_scope() -> u32 {
    5
}

/// Default SAT solver: SAT4J (pure Java, always available).
fn default_solver() -> String {
    "sat4j".to_string()
}

/// Default maximum scope: 10 atoms per signature.
fn default_max_scope() -> u32 {
    10
}

/// Load and deserialise an alloyiser manifest from a TOML file.
///
/// # Arguments
/// * `path` — Path to the `alloyiser.toml` file.
///
/// # Errors
/// Returns an error if the file cannot be read or is not valid TOML
/// matching the expected manifest schema.
pub fn load_manifest(path: &str) -> Result<Manifest> {
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("Failed to read manifest: {}", path))?;
    toml::from_str(&content).with_context(|| format!("Failed to parse manifest: {}", path))
}

/// Validate that a manifest has all required fields and sensible values.
///
/// Checks:
/// - Project name is non-empty
/// - Each spec has a name, source, and format
/// - Each assertion has a name and check expression
/// - Assertion scopes do not exceed the max-scope
///
/// # Errors
/// Returns an error describing the first validation failure found.
pub fn validate(manifest: &Manifest) -> Result<()> {
    if manifest.project.name.is_empty() {
        anyhow::bail!("project.name is required");
    }
    for (i, spec) in manifest.specs.iter().enumerate() {
        if spec.name.is_empty() {
            anyhow::bail!("specs[{}].name is required", i);
        }
        if spec.source.is_empty() {
            anyhow::bail!("specs[{}].source is required", i);
        }
    }
    for (i, assertion) in manifest.assertions.iter().enumerate() {
        if assertion.name.is_empty() {
            anyhow::bail!("assertions[{}].name is required", i);
        }
        if assertion.check.is_empty() {
            anyhow::bail!("assertions[{}].check is required", i);
        }
        if assertion.scope > manifest.alloy.max_scope {
            anyhow::bail!(
                "assertions[{}].scope ({}) exceeds alloy.max-scope ({})",
                i,
                assertion.scope,
                manifest.alloy.max_scope
            );
        }
    }
    Ok(())
}

/// Create a new alloyiser.toml manifest in the given directory.
///
/// Generates a starter manifest with example project config, a placeholder
/// spec entry, and two example assertions (no-orphan-posts, unique-emails).
///
/// # Errors
/// Returns an error if alloyiser.toml already exists at the target path
/// or if the file cannot be written.
pub fn init_manifest(path: &str) -> Result<()> {
    let manifest_path = Path::new(path).join("alloyiser.toml");
    if manifest_path.exists() {
        anyhow::bail!("alloyiser.toml already exists");
    }
    let template = r#"# alloyiser manifest — formal model verification for API specs
# SPDX-License-Identifier: PMPL-1.0-or-later

[project]
name = "my-api"

[[specs]]
name = "main-api"
source = "openapi.yaml"
format = "openapi"              # openapi | graphql | entity-relation

[[assertions]]
name = "no-orphan-posts"
check = "all p: Post | some p.author"
scope = 5                       # Alloy scope (max atoms per sig)

[[assertions]]
name = "unique-emails"
check = "all disj u1, u2: User | u1.email != u2.email"
scope = 4

[alloy]
solver = "sat4j"                # sat4j | minisat | glucose
max-scope = 10
"#;
    std::fs::write(&manifest_path, template)?;
    println!("Created {}", manifest_path.display());
    Ok(())
}

/// Print a summary of the manifest contents to stdout.
///
/// Displays the project name, number of specs and assertions,
/// and lists each spec and assertion by name.
pub fn print_info(manifest: &Manifest) {
    println!("=== alloyiser: {} ===", manifest.project.name);
    println!("Specs:      {}", manifest.specs.len());
    println!("Assertions: {}", manifest.assertions.len());
    println!("Solver:     {}", manifest.alloy.solver);
    println!("Max scope:  {}", manifest.alloy.max_scope);
    println!();
    for spec in &manifest.specs {
        println!(
            "  spec '{}': {} ({})",
            spec.name,
            spec.source,
            format!("{:?}", spec.format).to_lowercase()
        );
    }
    for assertion in &manifest.assertions {
        println!(
            "  assert '{}': {} [scope={}]",
            assertion.name, assertion.check, assertion.scope
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Verify that a valid manifest TOML string parses without errors.
    #[test]
    fn test_parse_valid_manifest() {
        let toml_str = r#"
[project]
name = "test-api"

[[specs]]
name = "user-api"
source = "openapi.yaml"
format = "openapi"

[[assertions]]
name = "no-orphans"
check = "all p: Post | some p.author"
scope = 5

[alloy]
solver = "sat4j"
max-scope = 10
"#;
        let manifest: Manifest = toml::from_str(toml_str).unwrap();
        assert_eq!(manifest.project.name, "test-api");
        assert_eq!(manifest.specs.len(), 1);
        assert_eq!(manifest.specs[0].format, SpecFormat::Openapi);
        assert_eq!(manifest.assertions.len(), 1);
        assert_eq!(manifest.assertions[0].scope, 5);
        assert_eq!(manifest.alloy.solver, "sat4j");
    }

    /// Verify that defaults are applied when optional fields are omitted.
    #[test]
    fn test_defaults_applied() {
        let toml_str = r#"
[project]
name = "minimal"
"#;
        let manifest: Manifest = toml::from_str(toml_str).unwrap();
        assert!(manifest.specs.is_empty());
        assert!(manifest.assertions.is_empty());
        assert_eq!(manifest.alloy.solver, "sat4j");
        assert_eq!(manifest.alloy.max_scope, 10);
    }

    /// Verify that validation catches an empty project name.
    #[test]
    fn test_validate_empty_name() {
        let manifest = Manifest {
            project: ProjectConfig {
                name: String::new(),
            },
            specs: vec![],
            assertions: vec![],
            alloy: AlloyConfig::default(),
        };
        assert!(validate(&manifest).is_err());
    }

    /// Verify that validation catches scope exceeding max-scope.
    #[test]
    fn test_validate_scope_exceeds_max() {
        let manifest = Manifest {
            project: ProjectConfig {
                name: "test".into(),
            },
            specs: vec![],
            assertions: vec![AssertionEntry {
                name: "big-scope".into(),
                check: "some User".into(),
                scope: 20,
            }],
            alloy: AlloyConfig {
                solver: "sat4j".into(),
                max_scope: 10,
            },
        };
        assert!(validate(&manifest).is_err());
    }
}
