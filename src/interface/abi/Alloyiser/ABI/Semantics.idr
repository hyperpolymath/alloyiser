-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Flagship semantic proof for Alloyiser (Idris2 ABI Layer 2).
|||
||| Alloyiser's headline is "extract formal models from API specs and verify
||| with Alloy". The most load-bearing thing an Alloy model expresses is a field
||| *multiplicity constraint*; the canonical, strongest one is `one`: a field
||| `f : A -> one B` asserts that every live source atom maps to EXACTLY ONE
||| target — the OpenAPI "required, single-valued" property alloyiser must
||| preserve when lowering a spec into an `.als` model.
|||
||| This models an Alloy binary relation as a list of (source, target) tuples,
||| defines the `one`-multiplicity property as "the source's target-count is 1",
||| gives a sound+complete `Dec`, a certifier into the ABI `Result` codes proven
||| sound, and positive + negative controls (a one-source/two-target instance —
||| exactly the Alloy counterexample for a `one` field — is provably rejected).

module Alloyiser.ABI.Semantics

import Alloyiser.ABI.Types
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- Faithful model of an Alloy binary relation
--------------------------------------------------------------------------------

public export
Source : Type
Source = Nat

public export
Target : Type
Target = Nat

public export
record Tuple where
  constructor MkTuple
  src : Source
  tgt : Target

||| An Alloy binary relation instance: a finite set of tuples.
public export
Relation : Type
Relation = List Tuple

||| How many targets source `s` has under relation `r`. Uses boolean `==` (which
||| reduces on concrete atoms) so the controls' `Refl`s check by computation.
public export
countTargets : Source -> Relation -> Nat
countTargets _ []                  = 0
countTargets s (MkTuple a _ :: ts) =
  if s == a then S (countTargets s ts) else countTargets s ts

--------------------------------------------------------------------------------
-- The `one` multiplicity property (exactly one target), stated as a count = 1
--------------------------------------------------------------------------------

||| `OneTargetFor s r`: source `s` maps to EXACTLY ONE target under `r`. There is
||| no constructor for count 0 (missing) or count >= 2 (over-multiple): those bad
||| cases are unrepresentable.
public export
data OneTargetFor : Source -> Relation -> Type where
  MkOne : {0 s : Source} -> {0 r : Relation} -> countTargets s r = 1 -> OneTargetFor s r

||| Every source in `sources` maps to exactly one target — the model-level
||| meaning of declaring the field with multiplicity `One` over those atoms.
public export
data ConformsOne : List Source -> Relation -> Type where
  ConfNil  : {0 r : Relation} -> ConformsOne [] r
  ConfCons : {0 s : Source} -> {0 ss : List Source} -> {0 r : Relation} ->
             OneTargetFor s r -> ConformsOne ss r -> ConformsOne (s :: ss) r

--------------------------------------------------------------------------------
-- Sound + complete decision
--------------------------------------------------------------------------------

public export
decOneTargetFor : (s : Source) -> (r : Relation) -> Dec (OneTargetFor s r)
decOneTargetFor s r = case decEq (countTargets s r) 1 of
  Yes prf => Yes (MkOne prf)
  No  no  => No (\(MkOne p) => no p)

public export
decConformsOne : (sources : List Source) -> (r : Relation) -> Dec (ConformsOne sources r)
decConformsOne []        r = Yes ConfNil
decConformsOne (s :: ss) r = case decOneTargetFor s r of
  No contra => No (\(ConfCons h _) => contra h)
  Yes h     => case decConformsOne ss r of
    No contra => No (\(ConfCons _ rest) => contra rest)
    Yes rest  => Yes (ConfCons h rest)

--------------------------------------------------------------------------------
-- Certifier into the ABI Result codes + soundness
--------------------------------------------------------------------------------

||| Certify a field's `one` multiplicity over its live sources: `Ok` when it
||| holds, `CounterexampleFound` (Alloy's outcome for a violated assertion)
||| otherwise.
public export
certifyOne : (sources : List Source) -> (r : Relation) -> Result
certifyOne sources r = case decConformsOne sources r of
  Yes _ => Ok
  No  _ => CounterexampleFound

||| Soundness: an `Ok` verdict recovers a genuine `ConformsOne` witness.
export
certifyOneSound : (sources : List Source) -> (r : Relation) ->
  certifyOne sources r = Ok -> ConformsOne sources r
certifyOneSound sources r prf with (decConformsOne sources r)
  certifyOneSound sources r prf  | Yes ok = ok
  certifyOneSound sources r Refl | No _ impossible

--------------------------------------------------------------------------------
-- Positive control: a conforming instance satisfies the constraint
--------------------------------------------------------------------------------

||| source 0 -> target 10, source 1 -> target 11: each source has one target.
public export
goodRelation : Relation
goodRelation = [MkTuple 0 10, MkTuple 1 11]

export
goodConformsOne : ConformsOne [0, 1] Semantics.goodRelation
goodConformsOne = ConfCons (MkOne Refl) (ConfCons (MkOne Refl) ConfNil)

--------------------------------------------------------------------------------
-- Negative control: a one-source/two-target instance is rejected (non-vacuity)
--------------------------------------------------------------------------------

||| source 0 maps to BOTH 10 and 20 — the Alloy counterexample for a `one` field.
public export
badRelation : Relation
badRelation = [MkTuple 0 10, MkTuple 0 20]

||| Machine-checked: source 0 does NOT have exactly one target (its count is 2).
export
badNotOneTarget : Not (OneTargetFor 0 Semantics.badRelation)
badNotOneTarget (MkOne Refl) impossible

||| Therefore the whole instance fails the `one` constraint.
export
badNotConformsOne : Not (ConformsOne [0] Semantics.badRelation)
badNotConformsOne (ConfCons h _) = badNotOneTarget h
