-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Deeper invariant proof for Alloyiser (Idris2 ABI Layer 3).
|||
||| Layer 2 (`Alloyiser.ABI.Semantics`) proves the `one` multiplicity property
||| for a single field: each live source maps to EXACTLY ONE target
||| (`countTargets s r = 1`). This module proves a genuinely DIFFERENT and
||| DEEPER fact: an *entailment between two of Alloy's multiplicity keywords*.
|||
||| Alloy orders its field multiplicities by permissiveness. `one` (exactly one)
||| is strictly STRONGER than `lone` (at most one): every `one` field is also a
||| valid `lone` field, but not conversely (a `lone` field may map to zero
||| targets). alloyiser must respect this lattice when it weakens or rewrites a
||| spec's constraints — relaxing `one` to `lone` is always sound, so any model
||| that the analyzer certifies for `one` is automatically certified for `lone`.
|||
||| We model `lone` as the propositional bound `LTE (countTargets s r) 1` (using
||| Data.Nat's order, which is the right tool for symbolic counts), reuse the
||| SAME relation/count model from Semantics, and prove:
|||   * `oneImpliesLone`   : OneTargetFor s r -> LoneTargetFor s r   (subsumption)
|||   * `conformsOneImpliesLone` : the field-level lift over a source list
|||   * a sound+complete `Dec (LoneTargetFor s r)`
|||   * `certifyLoneSound` : the ABI-`Result` certifier is sound
||| with a positive control (a zero-target source is `lone`), a negative control
||| (a two-target source is NOT `lone`), AND a non-vacuity control proving the
||| converse FAILS (`lone` does not imply `one`): the entailment is strict.

module Alloyiser.ABI.Invariants

import Alloyiser.ABI.Types
import Alloyiser.ABI.Semantics
import Data.Nat
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- The `lone` multiplicity property (AT MOST one target), as a propositional LTE
--------------------------------------------------------------------------------

||| `LoneTargetFor s r`: source `s` maps to AT MOST ONE target under `r` — the
||| meaning of Alloy's `lone` keyword. Stated as the order bound
||| `countTargets s r <= 1`, which admits both the zero-target case (field unset)
||| and the one-target case (field set), but excludes count >= 2.
public export
data LoneTargetFor : Source -> Relation -> Type where
  MkLone : {0 s : Source} -> {0 r : Relation} ->
           LTE (countTargets s r) 1 -> LoneTargetFor s r

||| Every source in `sources` maps to at most one target — the model-level
||| meaning of declaring the field with multiplicity `Lone` over those atoms.
public export
data ConformsLone : List Source -> Relation -> Type where
  LoneNil  : {0 r : Relation} -> ConformsLone [] r
  LoneCons : {0 s : Source} -> {0 ss : List Source} -> {0 r : Relation} ->
             LoneTargetFor s r -> ConformsLone ss r -> ConformsLone (s :: ss) r

--------------------------------------------------------------------------------
-- Layer-3 theorem: `one` entails `lone` (multiplicity subsumption)
--------------------------------------------------------------------------------

||| THE THEOREM. If a source has exactly one target (`one`), it has at most one
||| target (`lone`). Distinct from Layer 2: this is an implication BETWEEN two
||| constraints, not the establishment of one. The count-equality `n = 1` is
||| rewritten into the order bound `LTE 1 1`, discharged by `LTESucc LTEZero`.
export
oneImpliesLone : {0 s : Source} -> {0 r : Relation} ->
                 OneTargetFor s r -> LoneTargetFor s r
oneImpliesLone (MkOne prf) = MkLone (rewrite prf in LTESucc LTEZero)

||| Field-level lift: a relation conforming to `one` over a source list also
||| conforms to `lone` over the same list. Structural induction applying the
||| pointwise subsumption at each source.
export
conformsOneImpliesLone : {0 sources : List Source} -> {0 r : Relation} ->
                         ConformsOne sources r -> ConformsLone sources r
conformsOneImpliesLone ConfNil          = LoneNil
conformsOneImpliesLone (ConfCons h rest) =
  LoneCons (oneImpliesLone h) (conformsOneImpliesLone rest)

--------------------------------------------------------------------------------
-- Sound + complete decision for `lone`
--------------------------------------------------------------------------------

public export
decLoneTargetFor : (s : Source) -> (r : Relation) -> Dec (LoneTargetFor s r)
decLoneTargetFor s r = case isLTE (countTargets s r) 1 of
  Yes prf => Yes (MkLone prf)
  No  no  => No (\(MkLone p) => no p)

public export
decConformsLone : (sources : List Source) -> (r : Relation) -> Dec (ConformsLone sources r)
decConformsLone []        r = Yes LoneNil
decConformsLone (s :: ss) r = case decLoneTargetFor s r of
  No contra => No (\(LoneCons h _) => contra h)
  Yes h     => case decConformsLone ss r of
    No contra => No (\(LoneCons _ rest) => contra rest)
    Yes rest  => Yes (LoneCons h rest)

--------------------------------------------------------------------------------
-- Certifier into the ABI Result codes + soundness
--------------------------------------------------------------------------------

||| Certify a field's `lone` multiplicity over its live sources: `Ok` when it
||| holds, `CounterexampleFound` otherwise.
public export
certifyLone : (sources : List Source) -> (r : Relation) -> Result
certifyLone sources r = case decConformsLone sources r of
  Yes _ => Ok
  No  _ => CounterexampleFound

||| Soundness: an `Ok` verdict recovers a genuine `ConformsLone` witness.
export
certifyLoneSound : (sources : List Source) -> (r : Relation) ->
  certifyLone sources r = Ok -> ConformsLone sources r
certifyLoneSound sources r prf with (decConformsLone sources r)
  certifyLoneSound sources r prf  | Yes ok = ok
  certifyLoneSound sources r Refl | No _ impossible

||| Cross-certifier corollary: whatever the `one` certifier accepts, the `lone`
||| certifier accepts too — the relaxation `one |-> lone` never loses a model.
||| (Connects the two ABI verdicts via the entailment theorem above.)
export
certifyOneEntailsLone : (sources : List Source) -> (r : Relation) ->
  certifyOne sources r = Ok -> certifyLone sources r = Ok
certifyOneEntailsLone sources r prf with (decConformsLone sources r)
  certifyOneEntailsLone sources r prf | Yes _ = Refl
  certifyOneEntailsLone sources r prf | No contra =
    absurd (contra (conformsOneImpliesLone (certifyOneSound sources r prf)))

--------------------------------------------------------------------------------
-- Positive control: a zero-target source IS `lone` (and the `one` -> `lone`
-- lift produces a real witness on a conforming instance)
--------------------------------------------------------------------------------

||| source 5 appears in no tuple, so its target-count is 0 — `lone` (<= 1) holds,
||| but `one` (= 1) does NOT. The witness that `lone` is strictly weaker.
public export
emptyForFive : Relation
emptyForFive = [MkTuple 0 10, MkTuple 1 11]

export
fiveIsLone : LoneTargetFor 5 Invariants.emptyForFive
fiveIsLone = MkLone LTEZero

||| The Layer-3 theorem applied to Semantics' positive control yields a genuine
||| `ConformsLone` witness — the entailment is computational, not just stated.
export
goodConformsLone : ConformsLone [0, 1] Semantics.goodRelation
goodConformsLone = conformsOneImpliesLone goodConformsOne

--------------------------------------------------------------------------------
-- Negative control: a two-target source is NOT `lone` (non-vacuity)
--------------------------------------------------------------------------------

||| `badRelation` (from Semantics) maps source 0 to BOTH 10 and 20: count 2.
||| count 2 <= 1 is uninhabited, so source 0 is provably not `lone`.
export
badNotLoneTarget : Not (LoneTargetFor 0 Semantics.badRelation)
badNotLoneTarget (MkLone (LTESucc LTEZero)) impossible

||| Therefore the whole instance fails the `lone` constraint too.
export
badNotConformsLone : Not (ConformsLone [0] Semantics.badRelation)
badNotConformsLone (LoneCons h _) = badNotLoneTarget h

--------------------------------------------------------------------------------
-- Non-vacuity of the strictness: `lone` does NOT entail `one`
--------------------------------------------------------------------------------

||| The converse of the Layer-3 theorem is FALSE. Source 5 over `emptyForFive`
||| is `lone` (count 0) yet not `one` (count 0 /= 1). Machine-checked refutation
||| confirms the entailment `one -> lone` is strict, so it is not vacuous.
export
fiveNotOneTarget : Not (OneTargetFor 5 Invariants.emptyForFive)
fiveNotOneTarget (MkOne Refl) impossible
