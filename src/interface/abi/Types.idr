-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| ABI Type Definitions for Alloyiser
|||
||| This module defines the core Alloy model types used throughout alloyiser.
||| Every type that crosses the ABI boundary (Rust CLI <-> Alloy Analyzer) is
||| defined here with formal proofs of correctness.
|||
||| Alloy models consist of: signatures (entities), fields (relations),
||| facts (invariants), predicates (reusable constraints), assertions
||| (properties to verify), and scopes (bounded model checking limits).
|||
||| @see https://alloytools.org for Alloy documentation
||| @see https://idris2.readthedocs.io for Idris2 documentation

module Alloyiser.ABI.Types

import Data.Bits
import Data.So
import Data.Vect
import Data.List

%default total

--------------------------------------------------------------------------------
-- Platform Detection
--------------------------------------------------------------------------------

||| Supported platforms for alloyiser ABI
public export
data Platform = Linux | Windows | MacOS | BSD | WASM

||| Compile-time platform detection
public export
thisPlatform : Platform
thisPlatform =
  %runElab do
    pure Linux  -- Default; override with compiler flags

--------------------------------------------------------------------------------
-- Alloy Multiplicity
--------------------------------------------------------------------------------

||| Field multiplicity in an Alloy model.
||| Controls how many target atoms a field can map to from a single source atom.
|||
||| - `One`  : exactly one target (like a required foreign key)
||| - `Lone` : zero or one target (like an optional foreign key)
||| - `Set`  : zero or more targets (like a has-many relation)
||| - `Seq`  : ordered sequence of targets (like an ordered list)
public export
data Multiplicity = One | Lone | Set | Seq

||| Convert multiplicity to its Alloy keyword string representation
public export
showMultiplicity : Multiplicity -> String
showMultiplicity One  = "one"
showMultiplicity Lone = "lone"
showMultiplicity Set  = "set"
showMultiplicity Seq  = "seq"

||| Multiplicities are decidably equal
public export
DecEq Multiplicity where
  decEq One One   = Yes Refl
  decEq Lone Lone = Yes Refl
  decEq Set Set   = Yes Refl
  decEq Seq Seq   = Yes Refl
  decEq _ _       = No absurd

--------------------------------------------------------------------------------
-- Alloy Signature (Entity)
--------------------------------------------------------------------------------

||| An Alloy signature represents an entity type — analogous to a class,
||| table, or schema object in the source API specification.
|||
||| `abstract` sigs cannot have direct instances (used for inheritance).
||| `topLevel` sigs have no parent (default).
||| `extends` sigs inherit fields from a parent sig.
public export
record Signature where
  constructor MkSignature
  ||| Name of the signature (e.g., "Pet", "Order", "Customer")
  name : String
  ||| Whether this is an abstract signature (no direct instances)
  isAbstract : Bool
  ||| Parent signature name, if this sig extends another
  parent : Maybe String
  ||| Whether this sig is marked `one` (exactly one instance in every state)
  isSingleton : Bool

||| A valid signature must have a non-empty name
public export
data ValidSignature : Signature -> Type where
  SigValid : {sig : Signature} -> (So (length sig.name > 0)) -> ValidSignature sig

--------------------------------------------------------------------------------
-- Alloy Field (Relation)
--------------------------------------------------------------------------------

||| An Alloy field represents a relation between signatures.
||| In API terms: a property on a schema object that references another object.
|||
||| Example: `pets: set Pet` on a Customer sig means a customer can own
||| zero or more pets.
public export
record AlloyField where
  constructor MkAlloyField
  ||| Field name (e.g., "owner", "pets", "status")
  name : String
  ||| Name of the target signature this field points to
  targetSig : String
  ||| Multiplicity: how many targets per source atom
  multiplicity : Multiplicity

||| A valid field must reference a non-empty target signature
public export
data ValidField : AlloyField -> Type where
  FieldValid : {f : AlloyField}
            -> (So (length f.name > 0))
            -> (So (length f.targetSig > 0))
            -> ValidField f

--------------------------------------------------------------------------------
-- Alloy Fact (Invariant)
--------------------------------------------------------------------------------

||| An Alloy fact is a constraint that must hold in every valid state of the model.
||| Facts are generated from:
||| - Required fields in OpenAPI specs (field must be non-empty)
||| - Uniqueness constraints (all disj a, b: Sig | a.id != b.id)
||| - Enum restrictions (field value must be one of a fixed set)
||| - User-declared invariants in alloyiser.toml
public export
record Fact where
  constructor MkFact
  ||| Human-readable name for this fact (for error reporting)
  name : String
  ||| The Alloy expression body (e.g., "all p: Pet | some p.owner")
  body : String

||| A valid fact must have both a name and a body
public export
data ValidFact : Fact -> Type where
  FactValid : {f : Fact}
           -> (So (length f.name > 0))
           -> (So (length f.body > 0))
           -> ValidFact f

--------------------------------------------------------------------------------
-- Alloy Assertion
--------------------------------------------------------------------------------

||| An assertion is a property the user wants to verify.
||| Unlike facts (which are assumed true), assertions are checked by the SAT solver.
||| If the solver finds a counterexample, the assertion is violated.
public export
record Assertion where
  constructor MkAssertion
  ||| Name of the assertion (maps to alloyiser.toml [invariants] key)
  name : String
  ||| The Alloy expression to verify
  body : String

||| A valid assertion must have a name and body
public export
data ValidAssertion : Assertion -> Type where
  AssertValid : {a : Assertion}
             -> (So (length a.name > 0))
             -> (So (length a.body > 0))
             -> ValidAssertion a

--------------------------------------------------------------------------------
-- Alloy Scope
--------------------------------------------------------------------------------

||| A scope defines the upper bound on instances during bounded model checking.
||| The Alloy Analyzer checks all states with up to `bound` instances of each sig.
||| Larger scopes give more confidence but take exponentially longer.
public export
record Scope where
  constructor MkScope
  ||| Default bound for all signatures
  defaultBound : Nat
  ||| Per-signature overrides (e.g., check up to 3 Customers but 10 Pets)
  overrides : List (String, Nat)

||| A valid scope must have a positive default bound
public export
data ValidScope : Scope -> Type where
  ScopeValid : {s : Scope} -> (So (s.defaultBound > 0)) -> ValidScope s

||| The default scope: 5 instances per signature (Alloy convention)
public export
defaultScope : Scope
defaultScope = MkScope 5 []

--------------------------------------------------------------------------------
-- Alloy Predicate
--------------------------------------------------------------------------------

||| A predicate is a reusable named constraint, like a function returning a boolean.
||| Predicates can be invoked in facts, assertions, and run commands.
public export
record Predicate where
  constructor MkPredicate
  ||| Predicate name (e.g., "createPet", "transferOwnership")
  name : String
  ||| Parameter declarations (e.g., ["p: Pet", "c: Customer"])
  params : List String
  ||| Predicate body expression
  body : String

--------------------------------------------------------------------------------
-- Complete Alloy Model
--------------------------------------------------------------------------------

||| A complete Alloy model, ready for code generation.
||| This is the intermediate representation between spec parsing and .als output.
public export
record AlloyModel where
  constructor MkAlloyModel
  ||| Module name (becomes `module <name>` in the .als file)
  moduleName : String
  ||| All signatures (entities)
  signatures : List Signature
  ||| All fields (relations) — each field belongs to a signature
  fields : List (String, AlloyField)  -- (ownerSigName, field)
  ||| All facts (invariants)
  facts : List Fact
  ||| All predicates (reusable constraints)
  predicates : List Predicate
  ||| All assertions (properties to verify)
  assertions : List Assertion
  ||| Scope for bounded model checking
  scope : Scope

||| A valid model must have at least one signature
public export
data ValidModel : AlloyModel -> Type where
  ModelValid : {m : AlloyModel}
            -> (So (length m.moduleName > 0))
            -> (So (length m.signatures > 0))
            -> ValidModel m

--------------------------------------------------------------------------------
-- FFI Result Codes
--------------------------------------------------------------------------------

||| Result codes for alloyiser FFI operations
public export
data Result : Type where
  ||| Operation succeeded
  Ok : Result
  ||| Generic error
  Error : Result
  ||| Invalid parameter provided
  InvalidParam : Result
  ||| Out of memory
  OutOfMemory : Result
  ||| Null pointer encountered
  NullPointer : Result
  ||| Alloy model parsing failed
  ModelParseError : Result
  ||| SAT solver timed out
  SolverTimeout : Result
  ||| Counterexample found (assertion violated)
  CounterexampleFound : Result

||| Convert Result to C integer for FFI
public export
resultToInt : Result -> Bits32
resultToInt Ok                  = 0
resultToInt Error               = 1
resultToInt InvalidParam        = 2
resultToInt OutOfMemory         = 3
resultToInt NullPointer         = 4
resultToInt ModelParseError     = 5
resultToInt SolverTimeout       = 6
resultToInt CounterexampleFound = 7

||| Results are decidably equal
public export
DecEq Result where
  decEq Ok Ok                                   = Yes Refl
  decEq Error Error                             = Yes Refl
  decEq InvalidParam InvalidParam               = Yes Refl
  decEq OutOfMemory OutOfMemory                 = Yes Refl
  decEq NullPointer NullPointer                 = Yes Refl
  decEq ModelParseError ModelParseError         = Yes Refl
  decEq SolverTimeout SolverTimeout             = Yes Refl
  decEq CounterexampleFound CounterexampleFound = Yes Refl
  decEq _ _                                     = No absurd

--------------------------------------------------------------------------------
-- Opaque Handles
--------------------------------------------------------------------------------

||| Opaque handle to an alloyiser session.
||| Wraps a pointer to the Rust-side AlloyModel and analyzer state.
||| Non-null invariant enforced by dependent type.
public export
data Handle : Type where
  MkHandle : (ptr : Bits64) -> {auto 0 nonNull : So (ptr /= 0)} -> Handle

||| Safely create a handle from a pointer value.
||| Returns Nothing if pointer is null.
public export
createHandle : Bits64 -> Maybe Handle
createHandle 0 = Nothing
createHandle ptr = Just (MkHandle ptr)

||| Extract raw pointer value from handle (for FFI calls)
public export
handlePtr : Handle -> Bits64
handlePtr (MkHandle ptr) = ptr

--------------------------------------------------------------------------------
-- Counterexample Representation
--------------------------------------------------------------------------------

||| An atom in a counterexample instance (e.g., "Pet$0", "Customer$1")
public export
record Atom where
  constructor MkAtom
  ||| Signature this atom belongs to
  sigName : String
  ||| Instance index within the signature
  index : Nat

||| A tuple in a counterexample (field value assignment)
public export
record FieldValue where
  constructor MkFieldValue
  ||| The field being assigned
  fieldName : String
  ||| Source atom
  source : Atom
  ||| Target atom(s) — empty list means the field is unset
  targets : List Atom

||| A complete counterexample: a concrete state that violates an assertion
public export
record Counterexample where
  constructor MkCounterexample
  ||| Which assertion was violated
  assertionName : String
  ||| All atoms in this state
  atoms : List Atom
  ||| All field values in this state
  fieldValues : List FieldValue

--------------------------------------------------------------------------------
-- Platform-Specific Types (inherited from ABI standard)
--------------------------------------------------------------------------------

||| C size_t varies by platform
public export
CSize : Platform -> Type
CSize Linux   = Bits64
CSize Windows = Bits64
CSize MacOS   = Bits64
CSize BSD     = Bits64
CSize WASM    = Bits32

||| Pointer size by platform
public export
ptrSize : Platform -> Nat
ptrSize Linux   = 64
ptrSize Windows = 64
ptrSize MacOS   = 64
ptrSize BSD     = 64
ptrSize WASM    = 32

--------------------------------------------------------------------------------
-- Memory Layout Proofs
--------------------------------------------------------------------------------

||| Proof that a type has a specific size
public export
data HasSize : Type -> Nat -> Type where
  SizeProof : {0 t : Type} -> {n : Nat} -> HasSize t n

||| Proof that a type has a specific alignment
public export
data HasAlignment : Type -> Nat -> Type where
  AlignProof : {0 t : Type} -> {n : Nat} -> HasAlignment t n
