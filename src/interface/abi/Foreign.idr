-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Foreign Function Interface Declarations for Alloyiser
|||
||| This module declares all C-compatible functions that bridge alloyiser's
||| Rust CLI to the Alloy Analyzer (which runs on the JVM). The FFI layer
||| handles:
|||
||| 1. Model lifecycle: create, populate, and dispose Alloy model handles
||| 2. Model construction: add signatures, fields, facts, assertions
||| 3. Analyzer invocation: run SAT solver, retrieve counterexamples
||| 4. Result extraction: read counterexample atoms and field values
|||
||| All functions are declared here with type signatures. Implementations
||| live in ffi/zig/ and bridge to the JVM via JNI or subprocess.

module Alloyiser.ABI.Foreign

import Alloyiser.ABI.Types
import Alloyiser.ABI.Layout

%default total

--------------------------------------------------------------------------------
-- Model Lifecycle
--------------------------------------------------------------------------------

||| Create a new empty Alloy model.
||| Returns a handle to the model, or null on allocation failure.
export
%foreign "C:alloyiser_model_create, liballoyiser"
prim__modelCreate : String -> PrimIO Bits64

||| Safe wrapper: create a new Alloy model with the given module name
export
modelCreate : (moduleName : String) -> IO (Maybe Handle)
modelCreate name = do
  ptr <- primIO (prim__modelCreate name)
  pure (createHandle ptr)

||| Dispose of a model and free all associated memory.
||| After this call, the handle is invalid — do not reuse.
export
%foreign "C:alloyiser_model_free, liballoyiser"
prim__modelFree : Bits64 -> PrimIO ()

||| Safe wrapper: free a model handle
export
modelFree : Handle -> IO ()
modelFree h = primIO (prim__modelFree (handlePtr h))

--------------------------------------------------------------------------------
-- Signature Operations
--------------------------------------------------------------------------------

||| Add a signature to the model.
||| Parameters: model handle, sig name, is_abstract (0/1), parent name (or "")
||| Returns: 0 on success, error code on failure
export
%foreign "C:alloyiser_add_sig, liballoyiser"
prim__addSig : Bits64 -> String -> Bits32 -> String -> PrimIO Bits32

||| Safe wrapper: add a signature to the model
export
addSignature : Handle -> Signature -> IO (Either Result ())
addSignature h sig = do
  let abstractFlag = if sig.isAbstract then 1 else 0
  let parentStr = case sig.parent of
                    Nothing => ""
                    Just p  => p
  result <- primIO (prim__addSig (handlePtr h) sig.name abstractFlag parentStr)
  pure $ case result of
    0 => Right ()
    2 => Left InvalidParam
    3 => Left OutOfMemory
    _ => Left Error

--------------------------------------------------------------------------------
-- Field Operations
--------------------------------------------------------------------------------

||| Add a field (relation) to a signature.
||| Parameters: model handle, owner sig name, field name, target sig name, multiplicity
||| Multiplicity encoding: 0=one, 1=lone, 2=set, 3=seq
export
%foreign "C:alloyiser_add_field, liballoyiser"
prim__addField : Bits64 -> String -> String -> String -> Bits32 -> PrimIO Bits32

||| Encode a multiplicity as a C integer for FFI
export
multToInt : Multiplicity -> Bits32
multToInt One  = 0
multToInt Lone = 1
multToInt Set  = 2
multToInt Seq  = 3

||| Safe wrapper: add a field to a signature
export
addField : Handle -> (ownerSig : String) -> AlloyField -> IO (Either Result ())
addField h owner f = do
  result <- primIO (prim__addField (handlePtr h) owner f.name f.targetSig (multToInt f.multiplicity))
  pure $ case result of
    0 => Right ()
    2 => Left InvalidParam
    _ => Left Error

--------------------------------------------------------------------------------
-- Fact Operations
--------------------------------------------------------------------------------

||| Add a fact (invariant) to the model.
||| Parameters: model handle, fact name, fact body expression
export
%foreign "C:alloyiser_add_fact, liballoyiser"
prim__addFact : Bits64 -> String -> String -> PrimIO Bits32

||| Safe wrapper: add a fact to the model
export
addFact : Handle -> Fact -> IO (Either Result ())
addFact h f = do
  result <- primIO (prim__addFact (handlePtr h) f.name f.body)
  pure $ case result of
    0 => Right ()
    2 => Left InvalidParam
    _ => Left Error

--------------------------------------------------------------------------------
-- Assertion Operations
--------------------------------------------------------------------------------

||| Add an assertion to the model.
||| Parameters: model handle, assertion name, assertion body expression
export
%foreign "C:alloyiser_add_assertion, liballoyiser"
prim__addAssertion : Bits64 -> String -> String -> PrimIO Bits32

||| Safe wrapper: add an assertion (property to verify) to the model
export
addAssertion : Handle -> Assertion -> IO (Either Result ())
addAssertion h a = do
  result <- primIO (prim__addAssertion (handlePtr h) a.name a.body)
  pure $ case result of
    0 => Right ()
    2 => Left InvalidParam
    _ => Left Error

--------------------------------------------------------------------------------
-- Analyzer Invocation
--------------------------------------------------------------------------------

||| Run the Alloy Analyzer on the model, checking all assertions.
||| Parameters: model handle, default scope bound, timeout in milliseconds
||| Returns: 0 = all assertions pass, 7 = counterexample found, others = error
export
%foreign "C:alloyiser_analyze, liballoyiser"
prim__analyze : Bits64 -> Bits32 -> Bits32 -> PrimIO Bits32

||| Safe wrapper: run the analyzer with a scope and timeout
export
analyze : Handle -> Scope -> (timeoutMs : Bits32) -> IO Result
analyze h scope timeout = do
  result <- primIO (prim__analyze (handlePtr h) (cast scope.defaultBound) timeout)
  pure $ case result of
    0 => Ok
    5 => ModelParseError
    6 => SolverTimeout
    7 => CounterexampleFound
    _ => Error

--------------------------------------------------------------------------------
-- Counterexample Retrieval
--------------------------------------------------------------------------------

||| Get the number of counterexamples found in the last analysis run.
export
%foreign "C:alloyiser_counterexample_count, liballoyiser"
prim__counterexampleCount : Bits64 -> PrimIO Bits32

||| Safe wrapper: count counterexamples
export
counterexampleCount : Handle -> IO Nat
counterexampleCount h = do
  n <- primIO (prim__counterexampleCount (handlePtr h))
  pure (cast n)

||| Get the assertion name for a specific counterexample.
||| Parameters: model handle, counterexample index
export
%foreign "C:alloyiser_counterexample_assertion, liballoyiser"
prim__counterexampleAssertion : Bits64 -> Bits32 -> PrimIO Bits64

||| Convert C string pointer to Idris String
export
%foreign "support:idris2_getString, libidris2_support"
prim__getString : Bits64 -> String

||| Free a C string allocated by alloyiser
export
%foreign "C:alloyiser_free_string, liballoyiser"
prim__freeString : Bits64 -> PrimIO ()

||| Safe wrapper: get the assertion name for a counterexample
export
counterexampleAssertion : Handle -> (index : Nat) -> IO (Maybe String)
counterexampleAssertion h idx = do
  ptr <- primIO (prim__counterexampleAssertion (handlePtr h) (cast idx))
  if ptr == 0
    then pure Nothing
    else do
      let str = prim__getString ptr
      primIO (prim__freeString ptr)
      pure (Just str)

||| Get atom count in a specific counterexample.
export
%foreign "C:alloyiser_counterexample_atom_count, liballoyiser"
prim__counterexampleAtomCount : Bits64 -> Bits32 -> PrimIO Bits32

||| Safe wrapper: count atoms in a counterexample
export
counterexampleAtomCount : Handle -> (index : Nat) -> IO Nat
counterexampleAtomCount h idx = do
  n <- primIO (prim__counterexampleAtomCount (handlePtr h) (cast idx))
  pure (cast n)

||| Get a human-readable description of a counterexample.
||| Returns a formatted string showing all atoms and their field assignments.
export
%foreign "C:alloyiser_counterexample_describe, liballoyiser"
prim__counterexampleDescribe : Bits64 -> Bits32 -> PrimIO Bits64

||| Safe wrapper: describe a counterexample in human-readable form
export
describeCounterexample : Handle -> (index : Nat) -> IO (Maybe String)
describeCounterexample h idx = do
  ptr <- primIO (prim__counterexampleDescribe (handlePtr h) (cast idx))
  if ptr == 0
    then pure Nothing
    else do
      let str = prim__getString ptr
      primIO (prim__freeString ptr)
      pure (Just str)

--------------------------------------------------------------------------------
-- Model Serialisation
--------------------------------------------------------------------------------

||| Serialise the model to an Alloy .als source string.
||| This is the primary output: a valid Alloy 6 model file.
export
%foreign "C:alloyiser_model_to_als, liballoyiser"
prim__modelToAls : Bits64 -> PrimIO Bits64

||| Safe wrapper: convert model to .als source code
export
modelToAls : Handle -> IO (Maybe String)
modelToAls h = do
  ptr <- primIO (prim__modelToAls (handlePtr h))
  if ptr == 0
    then pure Nothing
    else do
      let str = prim__getString ptr
      primIO (prim__freeString ptr)
      pure (Just str)

||| Serialise the model to JSON (for machine consumption).
export
%foreign "C:alloyiser_model_to_json, liballoyiser"
prim__modelToJson : Bits64 -> PrimIO Bits64

||| Safe wrapper: convert model to JSON
export
modelToJson : Handle -> IO (Maybe String)
modelToJson h = do
  ptr <- primIO (prim__modelToJson (handlePtr h))
  if ptr == 0
    then pure Nothing
    else do
      let str = prim__getString ptr
      primIO (prim__freeString ptr)
      pure (Just str)

--------------------------------------------------------------------------------
-- Version and Build Information
--------------------------------------------------------------------------------

||| Get alloyiser library version string
export
%foreign "C:alloyiser_version, liballoyiser"
prim__version : PrimIO Bits64

||| Safe wrapper: get version
export
version : IO String
version = do
  ptr <- primIO prim__version
  pure (prim__getString ptr)

||| Get alloyiser build information (commit, date, features)
export
%foreign "C:alloyiser_build_info, liballoyiser"
prim__buildInfo : PrimIO Bits64

||| Safe wrapper: get build info
export
buildInfo : IO String
buildInfo = do
  ptr <- primIO prim__buildInfo
  pure (prim__getString ptr)

--------------------------------------------------------------------------------
-- Error Handling
--------------------------------------------------------------------------------

||| Get the last error message from the library
export
%foreign "C:alloyiser_last_error, liballoyiser"
prim__lastError : PrimIO Bits64

||| Safe wrapper: retrieve last error
export
lastError : IO (Maybe String)
lastError = do
  ptr <- primIO prim__lastError
  if ptr == 0
    then pure Nothing
    else pure (Just (prim__getString ptr))

||| Human-readable description for each result code
export
errorDescription : Result -> String
errorDescription Ok                  = "Success"
errorDescription Error               = "Generic error"
errorDescription InvalidParam        = "Invalid parameter"
errorDescription OutOfMemory         = "Out of memory"
errorDescription NullPointer         = "Null pointer"
errorDescription ModelParseError     = "Alloy model parsing failed"
errorDescription SolverTimeout       = "SAT solver timed out"
errorDescription CounterexampleFound = "Counterexample found — assertion violated"
