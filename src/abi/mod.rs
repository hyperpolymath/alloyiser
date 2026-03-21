// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// ABI module for alloyiser.
// Rust-side types mirroring the Idris2 ABI formal definitions.
// The Idris2 proofs guarantee correctness; this module provides runtime types.
//
// These types model the Alloy 6 language constructs:
// - Signatures (sig) — entity types
// - Fields — relations between signatures
// - Facts — constraints that always hold
// - Assertions — properties to check
// - Commands — check/run directives for the analyzer

use std::fmt;

/// Multiplicity annotations for Alloy fields.
/// Determines how many atoms a field can relate to.
///
/// In Alloy: `one` = exactly one, `lone` = zero or one,
/// `set` = any number, `some` = one or more.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Multiplicity {
    /// Exactly one related atom. Alloy keyword: `one`.
    One,
    /// Zero or one related atom. Alloy keyword: `lone`.
    Lone,
    /// Any number of related atoms (including zero). Alloy keyword: `set`.
    Set,
    /// One or more related atoms. Alloy keyword: `some`.
    Some_,
}

impl fmt::Display for Multiplicity {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Multiplicity::One => write!(f, "one"),
            Multiplicity::Lone => write!(f, "lone"),
            Multiplicity::Set => write!(f, "set"),
            Multiplicity::Some_ => write!(f, "some"),
        }
    }
}

/// An Alloy field (relation) belonging to a signature.
///
/// Fields define relationships between signatures. For example:
/// `author: one User` means each Post has exactly one User as author.
#[derive(Debug, Clone, PartialEq)]
pub struct AlloyField {
    /// The field name, e.g. "author".
    pub name: String,
    /// The multiplicity constraint on this field.
    pub multiplicity: Multiplicity,
    /// The target signature type, e.g. "User".
    pub target: String,
}

impl fmt::Display for AlloyField {
    /// Renders the field in Alloy 6 syntax: `name: multiplicity Target`
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}: {} {}", self.name, self.multiplicity, self.target)
    }
}

/// An Alloy signature (sig) — the fundamental entity type.
///
/// Signatures define the types of atoms in an Alloy model.
/// They can be abstract (no direct instances) and can extend other sigs.
#[derive(Debug, Clone, PartialEq)]
pub struct Signature {
    /// The signature name, e.g. "User".
    pub name: String,
    /// Fields (relations) belonging to this signature.
    pub fields: Vec<AlloyField>,
    /// Whether this signature is abstract (cannot have direct instances).
    pub is_abstract: bool,
    /// Optional parent signature this sig extends.
    pub extends: Option<String>,
}

impl Signature {
    /// Create a new concrete signature with the given name and no fields.
    pub fn new(name: impl Into<String>) -> Self {
        Signature {
            name: name.into(),
            fields: Vec::new(),
            is_abstract: false,
            extends: None,
        }
    }

    /// Add a field to this signature.
    pub fn with_field(mut self, field: AlloyField) -> Self {
        self.fields.push(field);
        self
    }

    /// Mark this signature as abstract.
    pub fn set_abstract(mut self) -> Self {
        self.is_abstract = true;
        self
    }

    /// Set the parent signature this sig extends.
    pub fn set_extends(mut self, parent: impl Into<String>) -> Self {
        self.extends = Some(parent.into());
        self
    }
}

impl fmt::Display for Signature {
    /// Renders the signature in Alloy 6 syntax.
    ///
    /// Example output:
    /// ```alloy
    /// sig User {
    ///     email: one Email,
    ///     posts: set Post
    /// }
    /// ```
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        // Opening: optional "abstract", the "sig" keyword, name, optional "extends"
        if self.is_abstract {
            write!(f, "abstract ")?;
        }
        write!(f, "sig {}", self.name)?;
        if let Some(ref parent) = self.extends {
            write!(f, " extends {}", parent)?;
        }

        if self.fields.is_empty() {
            write!(f, " {{}}")
        } else {
            writeln!(f, " {{")?;
            for (i, field) in self.fields.iter().enumerate() {
                if i < self.fields.len() - 1 {
                    writeln!(f, "    {},", field)?;
                } else {
                    writeln!(f, "    {}", field)?;
                }
            }
            write!(f, "}}")
        }
    }
}

/// An Alloy fact — a constraint that always holds in the model.
///
/// Facts are invariants that the Alloy analyzer enforces on all instances.
/// They constrain the space of valid model instances.
#[derive(Debug, Clone, PartialEq)]
pub struct Fact {
    /// Optional name for the fact (for readability).
    pub name: Option<String>,
    /// The Alloy expression body of the fact.
    pub body: String,
}

impl fmt::Display for Fact {
    /// Renders the fact in Alloy 6 syntax.
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match &self.name {
            Some(name) => write!(f, "fact {} {{\n    {}\n}}", name, self.body),
            None => write!(f, "fact {{\n    {}\n}}", self.body),
        }
    }
}

/// An Alloy assertion — a property to verify.
///
/// Assertions state properties that should hold given the model's facts.
/// The Alloy analyzer attempts to find counterexamples.
#[derive(Debug, Clone, PartialEq)]
pub struct Assertion {
    /// The assertion name, e.g. "no_orphan_posts".
    pub name: String,
    /// The Alloy expression to verify.
    pub body: String,
    /// The scope (max atoms per sig) for checking this assertion.
    pub scope: u32,
}

impl fmt::Display for Assertion {
    /// Renders the assertion and its check command in Alloy 6 syntax.
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        writeln!(f, "assert {} {{", self.name)?;
        writeln!(f, "    {}", self.body)?;
        writeln!(f, "}}")?;
        write!(f, "check {} for {}", self.name, self.scope)
    }
}

/// A complete Alloy model comprising sigs, facts, assertions, and commands.
///
/// This is the top-level structure that gets serialised into an `.als` file.
/// The model can be loaded into Alloy Analyzer for verification.
#[derive(Debug, Clone)]
pub struct AlloyModel {
    /// The module name (first line of the .als file).
    pub module_name: String,
    /// All signatures in the model.
    pub signatures: Vec<Signature>,
    /// All facts (constraints) in the model.
    pub facts: Vec<Fact>,
    /// All assertions to check.
    pub assertions: Vec<Assertion>,
    /// Optional opening comment describing the model's purpose.
    pub comment: Option<String>,
}

impl AlloyModel {
    /// Create a new empty model with the given module name.
    pub fn new(module_name: impl Into<String>) -> Self {
        AlloyModel {
            module_name: module_name.into(),
            signatures: Vec::new(),
            facts: Vec::new(),
            assertions: Vec::new(),
            comment: None,
        }
    }

    /// Add a signature to the model.
    pub fn add_signature(&mut self, sig: Signature) {
        self.signatures.push(sig);
    }

    /// Add a fact to the model.
    pub fn add_fact(&mut self, fact: Fact) {
        self.facts.push(fact);
    }

    /// Add an assertion to the model.
    pub fn add_assertion(&mut self, assertion: Assertion) {
        self.assertions.push(assertion);
    }

    /// Render the complete model as an Alloy 6 `.als` file.
    pub fn render(&self) -> String {
        let mut output = String::new();

        // Module declaration
        output.push_str(&format!("module {}\n", self.module_name));

        // Optional comment block
        if let Some(ref comment) = self.comment {
            output.push('\n');
            for line in comment.lines() {
                output.push_str(&format!("// {}\n", line));
            }
        }

        // Signatures
        if !self.signatures.is_empty() {
            output.push('\n');
            for sig in &self.signatures {
                output.push_str(&format!("{}\n\n", sig));
            }
        }

        // Facts
        for fact in &self.facts {
            output.push_str(&format!("{}\n\n", fact));
        }

        // Assertions and their check commands
        for assertion in &self.assertions {
            output.push_str(&format!("{}\n\n", assertion));
        }

        output
    }
}

/// Result of running the Alloy analyzer on a check command.
///
/// The analyzer either finds a counterexample (the assertion is violated)
/// or confirms no counterexample exists within the given scope.
#[derive(Debug, Clone, PartialEq)]
pub enum ModelCheckResult {
    /// No counterexample found within the scope — assertion holds.
    NoCounterexample {
        /// The assertion that was checked.
        assertion_name: String,
        /// The scope used for checking.
        scope: u32,
    },
    /// A counterexample was found — the assertion is violated.
    CounterexampleFound {
        /// The assertion that was violated.
        assertion_name: String,
        /// The counterexample details.
        counterexample: Counterexample,
    },
    /// The analyzer encountered an error (syntax, timeout, etc.).
    AnalysisError {
        /// Description of the error.
        message: String,
    },
}

/// A counterexample found by the Alloy analyzer.
///
/// Counterexamples show concrete atom assignments that violate an assertion.
/// Each atom binding maps a signature instance to its field values.
#[derive(Debug, Clone, PartialEq)]
pub struct Counterexample {
    /// Human-readable description of the counterexample.
    pub description: String,
    /// Atom bindings: maps "Sig$0" -> vec of ("field", "TargetSig$N") pairs.
    pub atom_bindings: Vec<AtomBinding>,
}

/// A single atom's field assignments in a counterexample.
#[derive(Debug, Clone, PartialEq)]
pub struct AtomBinding {
    /// The atom identifier, e.g. "User$0".
    pub atom: String,
    /// The signature type this atom belongs to.
    pub sig_type: String,
    /// Field values: (field_name, target_atom).
    pub field_values: Vec<(String, String)>,
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Verify that Multiplicity displays correctly in Alloy syntax.
    #[test]
    fn test_multiplicity_display() {
        assert_eq!(Multiplicity::One.to_string(), "one");
        assert_eq!(Multiplicity::Lone.to_string(), "lone");
        assert_eq!(Multiplicity::Set.to_string(), "set");
        assert_eq!(Multiplicity::Some_.to_string(), "some");
    }

    /// Verify that a signature with fields renders correct Alloy syntax.
    #[test]
    fn test_signature_display() {
        let sig = Signature::new("User")
            .with_field(AlloyField {
                name: "email".into(),
                multiplicity: Multiplicity::One,
                target: "Email".into(),
            })
            .with_field(AlloyField {
                name: "posts".into(),
                multiplicity: Multiplicity::Set,
                target: "Post".into(),
            });

        let rendered = sig.to_string();
        assert!(rendered.contains("sig User {"));
        assert!(rendered.contains("email: one Email"));
        assert!(rendered.contains("posts: set Post"));
    }

    /// Verify that an abstract extending signature renders correctly.
    #[test]
    fn test_abstract_extends_signature() {
        let sig = Signature::new("Admin")
            .set_abstract()
            .set_extends("User");
        let rendered = sig.to_string();
        assert!(rendered.starts_with("abstract sig Admin extends User"));
    }

    /// Verify that facts render with optional names.
    #[test]
    fn test_fact_display() {
        let named = Fact {
            name: Some("no_orphans".into()),
            body: "all p: Post | some p.author".into(),
        };
        assert!(named.to_string().contains("fact no_orphans {"));

        let unnamed = Fact {
            name: None,
            body: "all u: User | some u.email".into(),
        };
        assert!(unnamed.to_string().contains("fact {"));
    }

    /// Verify that assertions render with their check commands.
    #[test]
    fn test_assertion_display() {
        let assertion = Assertion {
            name: "unique_emails".into(),
            body: "all disj u1, u2: User | u1.email != u2.email".into(),
            scope: 4,
        };
        let rendered = assertion.to_string();
        assert!(rendered.contains("assert unique_emails {"));
        assert!(rendered.contains("check unique_emails for 4"));
    }

    /// Verify that a complete model renders a valid .als file structure.
    #[test]
    fn test_alloy_model_render() {
        let mut model = AlloyModel::new("blog_api");
        model.comment = Some("Blog API formal model".into());
        model.add_signature(Signature::new("User").with_field(AlloyField {
            name: "email".into(),
            multiplicity: Multiplicity::One,
            target: "Email".into(),
        }));
        model.add_fact(Fact {
            name: Some("emails_exist".into()),
            body: "all u: User | some u.email".into(),
        });
        model.add_assertion(Assertion {
            name: "no_orphans".into(),
            body: "all p: Post | some p.author".into(),
            scope: 5,
        });

        let rendered = model.render();
        assert!(rendered.starts_with("module blog_api\n"));
        assert!(rendered.contains("// Blog API formal model"));
        assert!(rendered.contains("sig User {"));
        assert!(rendered.contains("fact emails_exist {"));
        assert!(rendered.contains("assert no_orphans {"));
        assert!(rendered.contains("check no_orphans for 5"));
    }
}
