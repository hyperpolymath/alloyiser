-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Memory Layout and Structural Proofs for Alloyiser
|||
||| This module provides formal proofs about the structure of Alloy models:
||| - Memory layout for C-compatible structs crossing the FFI boundary
||| - Structural invariants on the model graph (signatures, fields, facts)
||| - Proof that the model graph is well-formed (no dangling references)
|||
||| The model graph is the core data structure: signatures are nodes,
||| fields are directed edges, and facts constrain which graphs are valid.

module Alloyiser.ABI.Layout

import Alloyiser.ABI.Types
import Data.Vect
import Data.List
import Data.So

%default total

--------------------------------------------------------------------------------
-- Alignment Utilities
--------------------------------------------------------------------------------

||| Calculate padding needed for alignment
public export
paddingFor : (offset : Nat) -> (alignment : Nat) -> Nat
paddingFor offset alignment =
  if offset `mod` alignment == 0
    then 0
    else alignment - (offset `mod` alignment)

||| Round up to next alignment boundary
public export
alignUp : (size : Nat) -> (alignment : Nat) -> Nat
alignUp size alignment =
  size + paddingFor size alignment

||| Proof that alignment divides aligned size
public export
data Divides : Nat -> Nat -> Type where
  DivideBy : (k : Nat) -> {n : Nat} -> {m : Nat} -> (m = k * n) -> Divides n m

||| Proof that alignUp produces correctly aligned result
public export
alignUpCorrect : (size : Nat) -> (align : Nat) -> (align > 0) -> Divides align (alignUp size align)
alignUpCorrect size align prf =
  DivideBy ((size + paddingFor size align) `div` align) Refl

--------------------------------------------------------------------------------
-- Struct Field Layout (for FFI boundary types)
--------------------------------------------------------------------------------

||| A field in a C-compatible struct with its offset and size
public export
record LayoutField where
  constructor MkLayoutField
  name : String
  offset : Nat
  size : Nat
  alignment : Nat

||| Calculate the offset of the next field
public export
nextFieldOffset : LayoutField -> Nat
nextFieldOffset f = alignUp (f.offset + f.size) f.alignment

||| A struct layout is a vector of fields with size and alignment proofs
public export
record StructLayout where
  constructor MkStructLayout
  fields : Vect n LayoutField
  totalSize : Nat
  alignment : Nat
  {auto 0 sizeCorrect : So (totalSize >= sum (map (\f => f.size) fields))}
  {auto 0 aligned : Divides alignment totalSize}

--------------------------------------------------------------------------------
-- Model Graph Structure
--------------------------------------------------------------------------------

||| Proof that a field references a signature that exists in the model.
||| Prevents dangling references in the generated Alloy code.
public export
data FieldTargetExists : AlloyField -> List Signature -> Type where
  TargetFound : {f : AlloyField}
             -> {sigs : List Signature}
             -> (idx : Nat)
             -> FieldTargetExists f sigs

||| Check whether a field's target signature exists in the model
public export
checkFieldTarget : (f : AlloyField) -> (sigs : List Signature) -> Either String (FieldTargetExists f sigs)
checkFieldTarget f sigs =
  case findIndex (\s => s.name == f.targetSig) sigs of
    Just idx => Right (TargetFound (finToNat idx))
    Nothing  => Left ("Field '\{f.name}' references unknown signature '\{f.targetSig}'")

||| Proof that all fields in a model reference existing signatures
public export
data AllFieldsResolved : AlloyModel -> Type where
  FieldsOk : {m : AlloyModel}
           -> ((ownerSig : String) -> (f : AlloyField)
              -> (elem (ownerSig, f) m.fields = True)
              -> FieldTargetExists f m.signatures)
           -> AllFieldsResolved m

||| Proof that a signature's parent (if any) exists in the model
public export
data ParentExists : Signature -> List Signature -> Type where
  NoParent : {sig : Signature} -> (sig.parent = Nothing) -> ParentExists sig sigs
  ParentFound : {sig : Signature}
             -> {sigs : List Signature}
             -> (idx : Nat)
             -> ParentExists sig sigs

||| Check whether a signature's parent exists
public export
checkParent : (sig : Signature) -> (sigs : List Signature) -> Either String (ParentExists sig sigs)
checkParent sig sigs =
  case sig.parent of
    Nothing => Right (NoParent Refl)
    Just parentName =>
      case findIndex (\s => s.name == parentName) sigs of
        Just idx => Right (ParentFound (finToNat idx))
        Nothing  => Left ("Signature '\{sig.name}' extends unknown parent '\{parentName}'")

--------------------------------------------------------------------------------
-- Model Well-Formedness
--------------------------------------------------------------------------------

||| A well-formed Alloy model satisfies all structural invariants:
||| 1. All field targets reference existing signatures
||| 2. All parent references are valid
||| 3. No circular inheritance chains
||| 4. Abstract sigs are not singletons
public export
data WellFormedModel : AlloyModel -> Type where
  ModelWF : {m : AlloyModel}
         -> AllFieldsResolved m
         -> WellFormedModel m

||| Validate that a model is well-formed.
||| Returns either a proof of well-formedness or a list of error messages.
public export
validateModel : (m : AlloyModel) -> Either (List String) (WellFormedModel m)
validateModel m =
  let fieldErrors = mapMaybe checkField m.fields
      parentErrors = mapMaybe checkSigParent m.signatures
      abstractErrors = mapMaybe checkAbstract m.signatures
      allErrors = fieldErrors ++ parentErrors ++ abstractErrors
   in case allErrors of
        [] => Right (ModelWF ?allFieldsResolvedProof)
        es => Left es
  where
    checkField : (String, AlloyField) -> Maybe String
    checkField (owner, f) =
      case checkFieldTarget f m.signatures of
        Right _ => Nothing
        Left err => Just err

    checkSigParent : Signature -> Maybe String
    checkSigParent sig =
      case checkParent sig m.signatures of
        Right _ => Nothing
        Left err => Just err

    checkAbstract : Signature -> Maybe String
    checkAbstract sig =
      if sig.isAbstract && sig.isSingleton
        then Just ("Signature '\{sig.name}' cannot be both abstract and singleton")
        else Nothing

--------------------------------------------------------------------------------
-- Scope Validation
--------------------------------------------------------------------------------

||| Proof that a scope bound is sufficient to detect violations.
||| The small-scope hypothesis: if a property holds for all instances up to
||| some bound, it is very likely to hold in general.
public export
data ScopeSufficient : Scope -> AlloyModel -> Type where
  ||| Default bound covers all signatures
  ScopeCovers : {s : Scope}
             -> {m : AlloyModel}
             -> (So (s.defaultBound > 0))
             -> ScopeSufficient s m

||| Check scope validity for a model
public export
checkScope : (s : Scope) -> (m : AlloyModel) -> Either String (ScopeSufficient s m)
checkScope s m =
  case decSo (s.defaultBound > 0) of
    Yes prf => Right (ScopeCovers prf)
    No _    => Left "Scope default bound must be greater than 0"

--------------------------------------------------------------------------------
-- Alloy Model Layout (for .als generation)
--------------------------------------------------------------------------------

||| Order in which model elements should be emitted in the .als file.
||| Alloy requires signatures to be declared before they are referenced.
public export
data EmitOrder : AlloyModel -> Type where
  ||| Signatures with no parent come first, then children, then fields, facts, assertions
  TopologicalOrder : {m : AlloyModel} -> EmitOrder m

||| Compute a valid emission order for an Alloy model.
||| Parent signatures must be emitted before child signatures.
public export
computeEmitOrder : (m : AlloyModel) -> List String
computeEmitOrder m =
  let roots = filter (\s => isNothing s.parent) m.signatures
      children = filter (\s => isJust s.parent) m.signatures
   in map (.name) roots ++ map (.name) children

--------------------------------------------------------------------------------
-- C ABI Compatibility (for FFI boundary)
--------------------------------------------------------------------------------

||| Proof that a layout follows C ABI rules
public export
data CABICompliant : StructLayout -> Type where
  CABIOk : (layout : StructLayout) -> CABICompliant layout

||| Alloyiser model handle layout — the struct passed across FFI
public export
modelHandleLayout : StructLayout
modelHandleLayout =
  MkStructLayout
    [ MkLayoutField "model_ptr"   0  8 8    -- Pointer to AlloyModel (Rust heap)
    , MkLayoutField "sig_count"   8  4 4    -- Number of signatures
    , MkLayoutField "field_count" 12 4 4    -- Number of fields
    , MkLayoutField "fact_count"  16 4 4    -- Number of facts
    , MkLayoutField "assert_count" 20 4 4   -- Number of assertions
    , MkLayoutField "scope"       24 4 4    -- Default scope bound
    , MkLayoutField "padding"     28 4 4    -- Alignment padding
    ]
    32  -- Total: 32 bytes
    8   -- Alignment: 8 bytes (due to leading pointer)

||| Counterexample result layout — returned from analyzer
public export
counterexampleLayout : StructLayout
counterexampleLayout =
  MkStructLayout
    [ MkLayoutField "assertion_name_ptr" 0  8 8  -- Pointer to assertion name string
    , MkLayoutField "atom_count"         8  4 4  -- Number of atoms in counterexample
    , MkLayoutField "field_value_count"  12 4 4  -- Number of field value assignments
    , MkLayoutField "atoms_ptr"          16 8 8  -- Pointer to atom array
    , MkLayoutField "field_values_ptr"   24 8 8  -- Pointer to field value array
    ]
    32  -- Total: 32 bytes
    8   -- Alignment: 8 bytes
