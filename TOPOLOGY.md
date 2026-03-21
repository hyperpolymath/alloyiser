<!-- SPDX-License-Identifier: PMPL-1.0-or-later -->
<!-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk> -->
# TOPOLOGY.md — alloyiser repository structure

```
alloyiser/
├── 0-AI-MANIFEST.a2ml              # AI agent entry point (read first)
├── Cargo.toml                      # Rust crate manifest
├── Justfile                        # Task runner (build, test, lint, assail)
├── Containerfile                   # OCI container build (Chainguard base)
├── contractile.just                # Contractile CLI integration recipes
├── flake.nix                       # Nix flake for reproducible builds
├── guix.scm                        # GNU Guix package definition
├── LICENSE                         # PMPL-1.0-or-later full text
├── README.adoc                     # Architecture overview and usage guide
├── ROADMAP.adoc                    # Phased implementation plan
├── TOPOLOGY.md                     # THIS FILE — repository map
├── CHANGELOG.md                    # Version history
├── CONTRIBUTING.adoc               # Contribution guidelines
├── SECURITY.md                     # Security policy
│
├── src/                            # Rust source code
│   ├── main.rs                     # CLI entry: init, validate, generate, build, run, info
│   ├── lib.rs                      # Library API: load_manifest, validate, generate
│   ├── manifest/
│   │   └── mod.rs                  # TOML manifest parser (alloyiser.toml)
│   ├── codegen/
│   │   └── mod.rs                  # Alloy .als file generation (stub)
│   ├── core/                       # [planned] Spec parser and entity extraction
│   ├── bridges/                    # [planned] Relation extraction (spec -> Alloy constructs)
│   ├── definitions/                # [planned] Alloy construct type definitions
│   ├── contracts/                  # [planned] Invariant contracts and constraint DSL
│   ├── errors/                     # [planned] Error types and diagnostics
│   ├── aspects/
│   │   ├── integrity/              # Data integrity cross-cuts
│   │   ├── observability/          # Logging and tracing
│   │   └── security/              # Security aspects
│   ├── abi/                        # Rust-side ABI module
│   └── interface/
│       ├── abi/                    # Idris2 ABI definitions
│       │   ├── Types.idr           # Alloy model types: Signature, Field, Fact, Assertion, Scope
│       │   ├── Layout.idr          # Model graph layout and structural proofs
│       │   └── Foreign.idr         # FFI to Alloy Analyzer (JVM bridge)
│       ├── ffi/                    # [planned] Zig FFI implementation
│       └── generated/              # [planned] Auto-generated C headers
│
├── container/                      # Stapeln container ecosystem
│   ├── Containerfile               # Container-specific build
│   ├── compose.toml                # Container composition
│   ├── compose.example.toml        # Example composition
│   ├── ct-build.sh                 # Container build script
│   ├── deploy.k9.ncl               # K9 deployment contract (Nickel)
│   ├── entrypoint.sh               # Container entry point
│   ├── manifest.toml               # Container manifest
│   └── vordr.toml                  # Vordr monitoring config
│
├── docs/                           # Documentation
│   ├── architecture/               # Architecture diagrams and threat model
│   ├── attribution/                # Citations, owners, maintainers
│   ├── decisions/                  # Architecture Decision Records
│   ├── developer/                  # Developer guides
│   ├── governance/                 # Project governance
│   ├── legal/                      # Legal exhibits
│   ├── practice/                   # Practical how-tos
│   ├── reports/                    # Generated reports
│   ├── standards/                  # Coding and process standards
│   ├── templates/                  # Document templates
│   ├── theory/                     # Domain theory (Alloy, relational logic, SAT)
│   ├── whitepapers/                # Research papers
│   └── wikis/                      # Wiki-style docs
│
├── examples/                       # Usage examples
│
├── features/                       # Feature modules
│   ├── boj-server/                 # BoJ cartridge integration
│   ├── panic-attacker/             # Panic-attacker integration
│   └── ssg/                        # Static site generation
│
├── tests/                          # Integration and end-to-end tests
│
├── verification/                   # Formal verification artefacts
│   ├── benchmarks/                 # Performance benchmarks
│   ├── coverage/                   # Test coverage reports
│   ├── fuzzing/                    # Fuzz testing configs
│   ├── proofs/                     # Formal proofs
│   ├── safety_case/                # Safety case documentation
│   ├── simulations/                # Model simulations
│   ├── tests/                      # Verification tests
│   └── traceability/               # Requirements traceability
│
├── .machine_readable/              # ALL machine-readable metadata
│   ├── 6a2/                        # A2ML state files
│   │   ├── STATE.a2ml              # Current project state
│   │   ├── META.a2ml               # Architecture decisions
│   │   ├── ECOSYSTEM.a2ml          # Ecosystem position
│   │   ├── AGENTIC.a2ml            # AI agent constraints
│   │   ├── NEUROSYM.a2ml           # Hypatia scanning config
│   │   └── PLAYBOOK.a2ml           # Operational runbook
│   ├── ai/                         # AI configuration
│   ├── anchors/                    # Semantic boundary anchors
│   ├── bot_directives/             # Bot-specific instructions
│   ├── contractiles/               # Policy enforcement contracts
│   ├── integrations/               # Integration configs
│   ├── policies/                   # Maintenance policies
│   ├── configs/                    # Tool configurations
│   ├── compliance/                 # Compliance artefacts
│   └── scripts/                    # Automation scripts
│
├── .github/                        # GitHub-specific
│   └── workflows/                  # 17 CI/CD workflows (RSR standard)
│
├── .hypatia/                       # Hypatia neurosymbolic scanner config
├── .well-known/                    # Well-known URIs
├── .devcontainer/                  # Dev container config
├── .claude/                        # Claude AI project instructions
│   └── CLAUDE.md
├── .gitlab-ci.yml                  # GitLab CI mirror
├── .editorconfig                   # Editor settings
├── .envrc                          # direnv environment
├── .gitattributes                  # Git attributes
├── .gitignore                      # Git ignore rules
├── .guix-channel                   # Guix channel config
└── .tool-versions                  # asdf tool versions
```

## Data Flow

```
User writes alloyiser.toml
       │
       ▼
src/manifest/mod.rs     parses TOML into Manifest struct
       │
       ▼
src/core/               [planned] parses OpenAPI/GraphQL/gRPC spec files
       │
       ▼
src/bridges/            [planned] maps spec entities to Alloy constructs
       │
       ▼
src/interface/abi/      Idris2 proofs: extraction preserves semantics
       │
       ▼
src/codegen/mod.rs      generates .als files (Alloy 6 models)
       │
       ▼
Alloy Analyzer          SAT solving finds counterexamples
       │
       ▼
Counterexample Report   human-readable + JSON output
```
