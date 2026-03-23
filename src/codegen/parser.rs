// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Parser module: extracts entities and relationships from API specifications.
//
// Currently supports OpenAPI 3.x (YAML/JSON) parsing to extract:
// - Schemas → Alloy signatures
// - Schema properties → Alloy fields with multiplicity
// - Required properties → `one` multiplicity, optional → `lone`
// - Array properties → `set` multiplicity
//
// GraphQL and entity-relation parsers are planned for Phase 2.

use anyhow::{Context, Result};
use std::collections::BTreeMap;
use std::path::Path;

use crate::abi::{AlloyField, Multiplicity, Signature};

/// A parsed entity extracted from an API specification.
///
/// This intermediate representation bridges the gap between
/// the raw API spec format and the Alloy type system.
#[derive(Debug, Clone)]
pub struct ParsedEntity {
    /// The entity name (becomes the Alloy sig name).
    pub name: String,
    /// Properties/fields of this entity.
    pub properties: Vec<ParsedProperty>,
}

/// A parsed property of an entity.
///
/// Captures the name, type, and cardinality information needed
/// to generate the corresponding Alloy field.
#[derive(Debug, Clone)]
pub struct ParsedProperty {
    /// The property name (becomes the Alloy field name).
    pub name: String,
    /// The target type name (becomes the Alloy field target sig).
    pub type_name: String,
    /// Whether this property is required (affects multiplicity).
    pub required: bool,
    /// Whether this property is an array/collection (affects multiplicity).
    pub is_array: bool,
}

/// Represents a simplified OpenAPI document structure.
///
/// We parse only the subset of OpenAPI needed for entity extraction:
/// the `components.schemas` section where data models are defined.
/// Full OpenAPI parsing (paths, operations) is Phase 2 scope.
#[derive(Debug, Clone)]
struct OpenApiSchema {
    /// Schema name → (properties, required_fields).
    schemas: BTreeMap<String, SchemaDefinition>,
}

/// A single schema definition from OpenAPI `components.schemas`.
#[derive(Debug, Clone)]
struct SchemaDefinition {
    /// Property name → property type info.
    properties: BTreeMap<String, PropertyType>,
    /// Set of required property names.
    required: Vec<String>,
}

/// The type information for a single schema property.
#[derive(Debug, Clone)]
enum PropertyType {
    /// A primitive type: string, integer, boolean, number.
    Primitive(String),
    /// A reference to another schema: `$ref: '#/components/schemas/User'`.
    Reference(String),
    /// An array of items (the inner type is the item type).
    Array(Box<PropertyType>),
}

/// Parse an OpenAPI YAML file and extract entities as `ParsedEntity` values.
///
/// This function reads the YAML, walks the `components.schemas` section,
/// and converts each schema into a `ParsedEntity` with its properties.
///
/// # Arguments
/// * `spec_path` — Path to the OpenAPI YAML file.
///
/// # Returns
/// A vector of parsed entities, one per schema definition.
///
/// # Errors
/// Returns an error if the file cannot be read or the YAML structure
/// does not match expected OpenAPI conventions.
pub fn parse_openapi(spec_path: &Path) -> Result<Vec<ParsedEntity>> {
    let content = std::fs::read_to_string(spec_path)
        .with_context(|| format!("Failed to read OpenAPI spec: {}", spec_path.display()))?;

    let schema = parse_openapi_yaml(&content)
        .with_context(|| format!("Failed to parse OpenAPI spec: {}", spec_path.display()))?;

    let entities = schema
        .schemas
        .into_iter()
        .map(|(name, def)| {
            let properties = def
                .properties
                .into_iter()
                .map(|(prop_name, prop_type)| {
                    let required = def.required.contains(&prop_name);
                    let (type_name, is_array) = resolve_property_type(&prop_type);
                    ParsedProperty {
                        name: prop_name,
                        type_name,
                        required,
                        is_array,
                    }
                })
                .collect();
            ParsedEntity { name, properties }
        })
        .collect();

    Ok(entities)
}

/// Parse OpenAPI YAML content into our simplified schema representation.
///
/// This is a lightweight parser that extracts only the structural information
/// we need. It handles the common OpenAPI patterns:
/// - `type: object` with `properties` and `required`
/// - `type: string/integer/boolean/number` for primitives
/// - `$ref: '#/components/schemas/Foo'` for references
/// - `type: array` with `items` for collections
fn parse_openapi_yaml(content: &str) -> Result<OpenApiSchema> {
    let mut schemas = BTreeMap::new();

    // State machine for YAML parsing.
    // We track indentation levels to identify sections.
    let lines: Vec<&str> = content.lines().collect();
    let mut i = 0;

    // Find the `components:` section
    while i < lines.len() {
        let line = lines[i].trim();
        if line == "components:" {
            i += 1;
            break;
        }
        i += 1;
    }

    // Find the `schemas:` subsection
    while i < lines.len() {
        let line = lines[i].trim();
        if line == "schemas:" {
            i += 1;
            break;
        }
        i += 1;
    }

    // Parse each schema definition
    let schema_indent = detect_indent(&lines, i);
    while i < lines.len() {
        let line = lines[i];
        let current_indent = count_leading_spaces(line);

        // If we've dedented past the schemas section, stop
        if current_indent < schema_indent && !line.trim().is_empty() {
            break;
        }

        // Schema name line: "    User:" at schema_indent level
        if current_indent == schema_indent && line.trim().ends_with(':') && !line.trim().is_empty()
        {
            let schema_name = line.trim().trim_end_matches(':').to_string();
            i += 1;

            let (def, next_i) = parse_schema_definition(&lines, i, schema_indent);
            schemas.insert(schema_name, def);
            i = next_i;
        } else {
            i += 1;
        }
    }

    Ok(OpenApiSchema { schemas })
}

/// Parse a single schema definition (properties and required fields).
///
/// Reads lines starting from `start` until indentation returns to or
/// below `parent_indent`. Extracts `properties:` and `required:` sections.
fn parse_schema_definition(
    lines: &[&str],
    start: usize,
    parent_indent: usize,
) -> (SchemaDefinition, usize) {
    let mut properties = BTreeMap::new();
    let mut required = Vec::new();
    let mut i = start;
    let section_indent = parent_indent + 2;

    while i < lines.len() {
        let line = lines[i];
        let indent = count_leading_spaces(line);
        let trimmed = line.trim();

        // If we've returned to parent indent level, this schema is done
        if indent <= parent_indent && !trimmed.is_empty() {
            break;
        }

        if trimmed == "properties:" && indent >= section_indent {
            i += 1;
            let prop_indent = section_indent + 2;
            while i < lines.len() {
                let pline = lines[i];
                let pindent = count_leading_spaces(pline);
                let ptrimmed = pline.trim();

                if pindent < prop_indent && !ptrimmed.is_empty() {
                    break;
                }

                // Property name line
                if pindent == prop_indent && ptrimmed.ends_with(':') {
                    let prop_name = ptrimmed.trim_end_matches(':').to_string();
                    i += 1;
                    let (prop_type, next_i) = parse_property_type(lines, i, prop_indent);
                    properties.insert(prop_name, prop_type);
                    i = next_i;
                } else {
                    i += 1;
                }
            }
        } else if trimmed == "required:" && indent >= section_indent {
            i += 1;
            while i < lines.len() {
                let rline = lines[i];
                let rindent = count_leading_spaces(rline);
                let rtrimmed = rline.trim();

                if rindent <= indent && !rtrimmed.is_empty() {
                    break;
                }

                if rtrimmed.starts_with("- ") {
                    let field_name = rtrimmed
                        .trim_start_matches("- ")
                        .trim_matches('"')
                        .trim_matches('\'')
                        .to_string();
                    required.push(field_name);
                }
                i += 1;
            }
        } else {
            i += 1;
        }
    }

    (
        SchemaDefinition {
            properties,
            required,
        },
        i,
    )
}

/// Parse the type of a single property from its YAML lines.
///
/// Handles:
/// - `type: string` → Primitive("String")
/// - `$ref: '#/components/schemas/User'` → Reference("User")
/// - `type: array` + `items:` → Array(inner_type)
fn parse_property_type(
    lines: &[&str],
    start: usize,
    parent_indent: usize,
) -> (PropertyType, usize) {
    let mut i = start;
    let detail_indent = parent_indent + 2;
    let mut prop_type: Option<String> = None;
    let mut ref_target: Option<String> = None;
    let mut items_type: Option<PropertyType> = None;

    while i < lines.len() {
        let line = lines[i];
        let indent = count_leading_spaces(line);
        let trimmed = line.trim();

        if indent < detail_indent && !trimmed.is_empty() {
            break;
        }

        if let Some(rest) = trimmed.strip_prefix("type:") {
            prop_type = Some(rest.trim().trim_matches('"').trim_matches('\'').to_string());
            i += 1;
        } else if let Some(rest) = trimmed.strip_prefix("$ref:") {
            let ref_str = rest.trim().trim_matches('\'').trim_matches('"');
            // Extract schema name from '#/components/schemas/User'
            if let Some(name) = ref_str.rsplit('/').next() {
                ref_target = Some(name.to_string());
            }
            i += 1;
        } else if trimmed == "items:" {
            i += 1;
            let (inner, next_i) = parse_property_type(lines, i, detail_indent);
            items_type = Some(inner);
            i = next_i;
        } else {
            i += 1;
        }
    }

    // Determine the property type from what we found
    let result = if let Some(ref_name) = ref_target {
        PropertyType::Reference(ref_name)
    } else if let Some(ref t) = prop_type {
        if t == "array" {
            let inner = items_type.unwrap_or(PropertyType::Primitive("String".to_string()));
            PropertyType::Array(Box::new(inner))
        } else {
            PropertyType::Primitive(yaml_type_to_alloy(t))
        }
    } else {
        PropertyType::Primitive("String".to_string())
    };

    (result, i)
}

/// Convert a YAML/OpenAPI type name to an Alloy-friendly signature name.
///
/// Primitives get capitalised signature names that will be defined as
/// abstract sigs in the generated model.
fn yaml_type_to_alloy(yaml_type: &str) -> String {
    match yaml_type {
        "string" => "String".to_string(),
        "integer" => "Int".to_string(),
        "number" => "Int".to_string(),
        "boolean" => "Bool".to_string(),
        other => {
            // Capitalise first letter for unknown types
            let mut chars = other.chars();
            match chars.next() {
                None => String::new(),
                Some(c) => c.to_uppercase().collect::<String>() + chars.as_str(),
            }
        }
    }
}

/// Resolve a PropertyType into a (type_name, is_array) pair.
fn resolve_property_type(prop_type: &PropertyType) -> (String, bool) {
    match prop_type {
        PropertyType::Primitive(name) => (name.clone(), false),
        PropertyType::Reference(name) => (name.clone(), false),
        PropertyType::Array(inner) => {
            let (name, _) = resolve_property_type(inner);
            (name, true)
        }
    }
}

/// Convert parsed entities into Alloy signatures with fields.
///
/// Maps each `ParsedEntity` to an Alloy `Signature`, converting
/// properties to fields with appropriate multiplicities:
/// - Required scalar → `one`
/// - Optional scalar → `lone`
/// - Array (required or optional) → `set`
///
/// # Arguments
/// * `entities` — The parsed entities from an API spec.
///
/// # Returns
/// A vector of Alloy signatures with their fields populated.
pub fn entities_to_signatures(entities: &[ParsedEntity]) -> Vec<Signature> {
    entities
        .iter()
        .map(|entity| {
            let mut sig = Signature::new(&entity.name);
            for prop in &entity.properties {
                let multiplicity = if prop.is_array {
                    Multiplicity::Set
                } else if prop.required {
                    Multiplicity::One
                } else {
                    Multiplicity::Lone
                };
                sig.fields.push(AlloyField {
                    name: prop.name.clone(),
                    multiplicity,
                    target: prop.type_name.clone(),
                });
            }
            sig
        })
        .collect()
}

/// Detect the indentation level of the next non-empty line at or after `start`.
fn detect_indent(lines: &[&str], start: usize) -> usize {
    for i in start..lines.len() {
        let line = lines[i];
        if !line.trim().is_empty() {
            return count_leading_spaces(line);
        }
    }
    0
}

/// Count the number of leading space characters in a line.
fn count_leading_spaces(line: &str) -> usize {
    line.len() - line.trim_start().len()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Verify that a simple OpenAPI YAML with two schemas parses correctly.
    #[test]
    fn test_parse_openapi_yaml_basic() {
        let yaml = r#"openapi: "3.0.0"
info:
  title: Blog API
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
        name:
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
        comments:
          type: array
          items:
            $ref: '#/components/schemas/Comment'
      required:
        - id
        - title
        - author
"#;
        let schema = parse_openapi_yaml(yaml).unwrap();
        assert_eq!(schema.schemas.len(), 2);

        let user = &schema.schemas["User"];
        assert_eq!(user.properties.len(), 3);
        assert!(user.required.contains(&"id".to_string()));
        assert!(user.required.contains(&"email".to_string()));

        let post = &schema.schemas["Post"];
        assert_eq!(post.properties.len(), 4);
        assert!(post.required.contains(&"author".to_string()));
    }

    /// Verify that parsed entities convert to signatures with correct multiplicities.
    #[test]
    fn test_entities_to_signatures() {
        let entities = vec![ParsedEntity {
            name: "User".to_string(),
            properties: vec![
                ParsedProperty {
                    name: "id".into(),
                    type_name: "Int".into(),
                    required: true,
                    is_array: false,
                },
                ParsedProperty {
                    name: "email".into(),
                    type_name: "String".into(),
                    required: true,
                    is_array: false,
                },
                ParsedProperty {
                    name: "nickname".into(),
                    type_name: "String".into(),
                    required: false,
                    is_array: false,
                },
                ParsedProperty {
                    name: "posts".into(),
                    type_name: "Post".into(),
                    required: false,
                    is_array: true,
                },
            ],
        }];

        let sigs = entities_to_signatures(&entities);
        assert_eq!(sigs.len(), 1);
        assert_eq!(sigs[0].name, "User");
        assert_eq!(sigs[0].fields.len(), 4);
        assert_eq!(sigs[0].fields[0].multiplicity, Multiplicity::One); // id: required
        assert_eq!(sigs[0].fields[1].multiplicity, Multiplicity::One); // email: required
        assert_eq!(sigs[0].fields[2].multiplicity, Multiplicity::Lone); // nickname: optional
        assert_eq!(sigs[0].fields[3].multiplicity, Multiplicity::Set); // posts: array
    }

    /// Verify that YAML types map to Alloy-friendly type names.
    #[test]
    fn test_yaml_type_to_alloy() {
        assert_eq!(yaml_type_to_alloy("string"), "String");
        assert_eq!(yaml_type_to_alloy("integer"), "Int");
        assert_eq!(yaml_type_to_alloy("number"), "Int");
        assert_eq!(yaml_type_to_alloy("boolean"), "Bool");
        assert_eq!(yaml_type_to_alloy("custom"), "Custom");
    }
}
