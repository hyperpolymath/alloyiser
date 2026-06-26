-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Machine-checked proofs over the alloyiser ABI.
|||
||| These are not runtime tests — they are propositional statements the Idris2
||| type checker must discharge at compile time. If any concrete ABI layout
||| were misaligned, the result-code encoding wrong, or a decision procedure
||| mis-defined, this module would fail to typecheck and the proof build would
||| go red.
|||
||| The C-ABI compliance witnesses are built directly from per-field
||| divisibility proofs (`DivideBy k Refl`, where `offset = k * alignment`).
||| Multiplication reduces during type checking, so these are fully verified
||| by the compiler; we avoid routing them through `Nat` division, which is a
||| primitive that does not reduce at the type level.

module Alloyiser.ABI.Proofs

import Alloyiser.ABI.Types
import Alloyiser.ABI.Layout
import Data.So
import Data.Vect

%default total

--------------------------------------------------------------------------------
-- The concrete FFI struct layouts are provably C-ABI compliant.
--------------------------------------------------------------------------------

||| Every field offset in the model-handle layout divides its alignment:
||| 0|8, 8|4, 12|4, 16|4, 20|4, 24|4, 28|4.
export
modelHandleCompliant : CABICompliant Layout.modelHandleLayout
modelHandleCompliant =
  CABIOk modelHandleLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 3 Refl)
    (ConsField _ _ (DivideBy 4 Refl)
    (ConsField _ _ (DivideBy 5 Refl)
    (ConsField _ _ (DivideBy 6 Refl)
    (ConsField _ _ (DivideBy 7 Refl)
     NoFields)))))))

||| Every field offset in the counterexample layout divides its alignment:
||| 0|8, 8|4, 12|4, 16|8, 24|8.
export
counterexampleCompliant : CABICompliant Layout.counterexampleLayout
counterexampleCompliant =
  CABIOk counterexampleLayout
    (ConsField _ _ (DivideBy 0 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 3 Refl)
    (ConsField _ _ (DivideBy 2 Refl)
    (ConsField _ _ (DivideBy 3 Refl)
     NoFields)))))

--------------------------------------------------------------------------------
-- Result-code round-trip: the encoding the Zig FFI depends on.
--------------------------------------------------------------------------------

export
okIsZero : resultToInt Ok = 0
okIsZero = Refl

export
counterexampleFoundIsSeven : resultToInt CounterexampleFound = 7
counterexampleFoundIsSeven = Refl

--------------------------------------------------------------------------------
-- Multiplicity encoding pinned against its FFI integer mapping.
--------------------------------------------------------------------------------

||| The default scope's bound is the Alloy convention of 5 instances per sig.
export
defaultScopeBoundIsFive : (Types.defaultScope).defaultBound = 5
defaultScopeBoundIsFive = Refl
