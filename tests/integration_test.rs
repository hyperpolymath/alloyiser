// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Integration tests for alloyiser Phase 1.
//
// These tests verify the end-to-end pipeline from manifest loading
// through entity extraction to Alloy model generation.

use alloyiser::abi::{AlloyField, AlloyModel, Assertion, Fact, Multiplicity, Signature};
use alloyiser::manifest::{
    AlloyConfig, AssertionEntry, Manifest, ProjectConfig, SpecEntry, SpecFormat,
};
use std::fs;
use tempfile::TempDir;

/// Test that `init_manifest` creates a valid alloyiser.toml file
/// with the expected structure and default values.
#[test]
fn test_init_creates_manifest() {
    let tmp = TempDir::new().unwrap();
    let path = tmp.path().to_str().unwrap();

    alloyiser::manifest::init_manifest(path).unwrap();

    let manifest_path = tmp.path().join("alloyiser.toml");
    assert!(manifest_path.exists(), "alloyiser.toml should be created");

    let content = fs::read_to_string(&manifest_path).unwrap();
    assert!(
        content.contains("[project]"),
        "Should have [project] section"
    );
    assert!(content.contains("name ="), "Should have project name");
    assert!(
        content.contains("[[specs]]"),
        "Should have [[specs]] section"
    );
    assert!(
        content.contains("[[assertions]]"),
        "Should have [[assertions]] section"
    );
    assert!(content.contains("[alloy]"), "Should have [alloy] section");

    // Verify the generated manifest is parseable
    let manifest: Manifest = toml::from_str(&content).unwrap();
    assert_eq!(manifest.project.name, "my-api");
    assert!(!manifest.specs.is_empty());
    assert!(!manifest.assertions.is_empty());
}

/// Test that the generate command produces .als files from the
/// blog-api example spec.
#[test]
fn test_generate_produces_als_files() {
    let tmp = TempDir::new().unwrap();
    let output_dir = tmp.path().to_str().unwrap();

    // Create a minimal OpenAPI spec in the temp directory
    let spec_path = tmp.path().join("openapi.yaml");
    fs::write(
        &spec_path,
        r#"openapi: "3.0.0"
info:
  title: Test API
  version: "1.0"
paths: {}
components:
  schemas:
    User:
      type: object
      properties:
        id:
          type: integer
        email:
          type: string
      required:
        - id
        - email
    Post:
      type: object
      properties:
        id:
          type: integer
        title:
          type: string
        author:
          $ref: '#/components/schemas/User'
      required:
        - id
        - title
        - author
"#,
    )
    .unwrap();

    let manifest = Manifest {
        project: ProjectConfig {
            name: "test-api".into(),
        },
        specs: vec![SpecEntry {
            name: "test".into(),
            source: spec_path.to_str().unwrap().into(),
            format: SpecFormat::Openapi,
        }],
        assertions: vec![AssertionEntry {
            name: "no-orphans".into(),
            check: "all p: Post | some p.author".into(),
            scope: 5,
        }],
        alloy: AlloyConfig {
            solver: "sat4j".into(),
            max_scope: 10,
        },
    };

    alloyiser::codegen::generate_all(&manifest, output_dir).unwrap();

    // Check that .als file was created
    let als_path = tmp.path().join("test_api.als");
    assert!(als_path.exists(), "Should generate test_api.als");

    let als_content = fs::read_to_string(&als_path).unwrap();
    assert!(
        als_content.contains("module test_api"),
        "Should have module declaration"
    );
    assert!(als_content.contains("sig User"), "Should have User sig");
    assert!(als_content.contains("sig Post"), "Should have Post sig");

    // Check that analysis script was created
    let script_path = tmp.path().join("run-analysis.sh");
    assert!(script_path.exists(), "Should generate run-analysis.sh");
}

/// Test that OpenAPI entity extraction correctly identifies schemas,
/// properties, and their types/multiplicity.
#[test]
fn test_openapi_entity_extraction() {
    let tmp = TempDir::new().unwrap();
    let spec_path = tmp.path().join("test.yaml");
    fs::write(
        &spec_path,
        r#"openapi: "3.0.0"
info:
  title: Entity Test
  version: "1.0"
paths: {}
components:
  schemas:
    User:
      type: object
      properties:
        id:
          type: integer
        name:
          type: string
        email:
          type: string
        posts:
          type: array
          items:
            $ref: '#/components/schemas/Post'
      required:
        - id
        - name
        - email
    Post:
      type: object
      properties:
        id:
          type: integer
        title:
          type: string
        content:
          type: string
        author:
          $ref: '#/components/schemas/User'
      required:
        - id
        - title
        - author
"#,
    )
    .unwrap();

    let entities = alloyiser::codegen::parser::parse_openapi(&spec_path).unwrap();
    assert_eq!(entities.len(), 2, "Should extract User and Post");

    // Find User entity
    let user = entities.iter().find(|e| e.name == "User").unwrap();
    assert_eq!(user.properties.len(), 4);

    // Check that required properties are marked
    let id_prop = user.properties.iter().find(|p| p.name == "id").unwrap();
    assert!(id_prop.required, "id should be required");
    assert_eq!(id_prop.type_name, "Int");

    // Check array property
    let posts_prop = user.properties.iter().find(|p| p.name == "posts").unwrap();
    assert!(posts_prop.is_array, "posts should be an array");
    assert_eq!(posts_prop.type_name, "Post");

    // Find Post entity
    let post = entities.iter().find(|e| e.name == "Post").unwrap();
    let author_prop = post.properties.iter().find(|p| p.name == "author").unwrap();
    assert!(author_prop.required, "author should be required");
    assert_eq!(author_prop.type_name, "User");

    // Convert to signatures and verify multiplicities
    let sigs = alloyiser::codegen::parser::entities_to_signatures(&entities);
    let user_sig = sigs.iter().find(|s| s.name == "User").unwrap();
    let posts_field = user_sig.fields.iter().find(|f| f.name == "posts").unwrap();
    assert_eq!(
        posts_field.multiplicity,
        Multiplicity::Set,
        "Array fields should have Set multiplicity"
    );
}

/// Test that assertion syntax is correctly represented in the Alloy model.
#[test]
fn test_assertion_syntax() {
    let assertion = Assertion {
        name: "no_orphan_posts".into(),
        body: "all p: Post | some p.author".into(),
        scope: 5,
    };

    let rendered = assertion.to_string();
    assert!(
        rendered.contains("assert no_orphan_posts {"),
        "Should have assert keyword and name"
    );
    assert!(
        rendered.contains("all p: Post | some p.author"),
        "Should contain the check expression"
    );
    assert!(
        rendered.contains("check no_orphan_posts for 5"),
        "Should have check command with scope"
    );
}

/// Test that the complete Alloy model has the expected structure:
/// module declaration, sigs with fields, facts, assertions, and checks.
#[test]
fn test_alloy_model_structure() {
    let mut model = AlloyModel::new("blog_api");
    model.comment = Some("Blog API formal model".into());

    // Add primitive type sigs
    let mut string_sig = Signature::new("String");
    string_sig.is_abstract = true;
    model.add_signature(string_sig);

    let mut int_sig = Signature::new("Int");
    int_sig.is_abstract = true;
    model.add_signature(int_sig);

    // Add entity sigs
    model.add_signature(
        Signature::new("User")
            .with_field(AlloyField {
                name: "email".into(),
                multiplicity: Multiplicity::One,
                target: "String".into(),
            })
            .with_field(AlloyField {
                name: "posts".into(),
                multiplicity: Multiplicity::Set,
                target: "Post".into(),
            }),
    );

    model.add_signature(
        Signature::new("Post")
            .with_field(AlloyField {
                name: "title".into(),
                multiplicity: Multiplicity::One,
                target: "String".into(),
            })
            .with_field(AlloyField {
                name: "author".into(),
                multiplicity: Multiplicity::One,
                target: "User".into(),
            })
            .with_field(AlloyField {
                name: "comments".into(),
                multiplicity: Multiplicity::Set,
                target: "Comment".into(),
            }),
    );

    model.add_signature(
        Signature::new("Comment")
            .with_field(AlloyField {
                name: "text".into(),
                multiplicity: Multiplicity::One,
                target: "String".into(),
            })
            .with_field(AlloyField {
                name: "author".into(),
                multiplicity: Multiplicity::One,
                target: "User".into(),
            }),
    );

    // Add a fact
    model.add_fact(Fact {
        name: Some("post_author_integrity".into()),
        body: "all p: Post | p.author in User".into(),
    });

    // Add assertions
    model.add_assertion(Assertion {
        name: "no_orphan_posts".into(),
        body: "all p: Post | some p.author".into(),
        scope: 5,
    });
    model.add_assertion(Assertion {
        name: "unique_emails".into(),
        body: "all disj u1, u2: User | u1.email != u2.email".into(),
        scope: 4,
    });

    let rendered = model.render();

    // Verify structure
    assert!(rendered.starts_with("module blog_api\n"));
    assert!(rendered.contains("// Blog API formal model"));

    // Verify primitive sigs are abstract
    assert!(rendered.contains("abstract sig String {}"));
    assert!(rendered.contains("abstract sig Int {}"));

    // Verify entity sigs have fields
    assert!(rendered.contains("sig User {"));
    assert!(rendered.contains("email: one String"));
    assert!(rendered.contains("posts: set Post"));
    assert!(rendered.contains("sig Post {"));
    assert!(rendered.contains("title: one String"));
    assert!(rendered.contains("author: one User"));
    assert!(rendered.contains("sig Comment {"));

    // Verify facts
    assert!(rendered.contains("fact post_author_integrity {"));
    assert!(rendered.contains("all p: Post | p.author in User"));

    // Verify assertions and check commands
    assert!(rendered.contains("assert no_orphan_posts {"));
    assert!(rendered.contains("check no_orphan_posts for 5"));
    assert!(rendered.contains("assert unique_emails {"));
    assert!(rendered.contains("check unique_emails for 4"));
}
