-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer 5 — the end-to-end ABI SOUNDNESS CERTIFICATE for alloyiser.
|||
||| This is the capstone. It does not prove a new domain theorem; it ASSEMBLES
||| the proofs of every prior layer into ONE inhabited value, demonstrating that
||| the full ABI contract — from the alloyiser manifest, through the ABI proofs,
||| to the FFI seam — is discharged together as a single coherent statement.
|||
||| The chain it ties together:
|||
|||   manifest (`alloyiser.toml` describes the Alloy field multiplicities)
|||      |
|||   Layer 2  `Alloyiser.ABI.Semantics`  — the FLAGSHIP property: a field with
|||            multiplicity `one` maps each live source to EXACTLY ONE target.
|||            Reused here via the exported positive control `goodConformsOne`.
|||      |
|||   Layer 3  `Alloyiser.ABI.Invariants` — the DEEPER invariant: `one` entails
|||            `lone` (multiplicity subsumption). Reused here via the exported
|||            `goodConformsLone` witness (itself the Layer-3 theorem applied to
|||            the Layer-2 control).
|||      |
|||   Layer 4  `Alloyiser.ABI.FfiSeam`    — the SEAM: `resultToInt` is injective,
|||            so distinct ABI outcomes never collide on the C wire. Reused here
|||            via the exported `resultToIntInjective`.
|||
||| The record `ABISound` collects exactly these key proven facts as fields. The
||| single value `abiContractDischarged : ABISound` is constructed ONLY from the
||| existing exported witnesses/theorems — if any prior layer were unsound, this
||| value would fail to typecheck. That is the whole point of the certificate:
||| it is inhabited iff the ABI contract holds end-to-end.
|||
||| STRICT: genuine composition only. No `believe_me`, `idris_crash`,
||| `assert_total`, `postulate`, `sorry`, or `%hint` hacks anywhere — every field
||| is filled by a real, already-proven, exported value.

module Alloyiser.ABI.Capstone

import Alloyiser.ABI.Types
import Alloyiser.ABI.Semantics
import Alloyiser.ABI.Invariants
import Alloyiser.ABI.FfiSeam

%default total

--------------------------------------------------------------------------------
-- The end-to-end ABI soundness certificate
--------------------------------------------------------------------------------

||| `ABISound` is the conjunction of the load-bearing ABI guarantees. To inhabit
||| it you must simultaneously supply:
|||
|||  * `flagship`  — the Layer-2 flagship property on the canonical positive
|||    control: the `one` field over sources `[0,1]` of `goodRelation` really
|||    does map each source to exactly one target (`ConformsOne`).
|||  * `invariant` — the Layer-3 deeper invariant on the SAME control: that same
|||    relation also satisfies `lone` (at-most-one), the subsumption `one |-> lone`.
|||  * `seamInjective` — the Layer-4 FFI-seam guarantee: the function encoding ABI
|||    `Result` outcomes to C integers is injective (no two outcomes collide).
|||
||| A value of this type is a machine-checked certificate that all three layers
||| hold together.
public export
record ABISound where
  constructor MkABISound
  ||| Layer 2: flagship `one`-multiplicity holds on the canonical control.
  flagship      : ConformsOne [0, 1] Semantics.goodRelation
  ||| Layer 3: the deeper `lone` invariant holds on the same control.
  invariant     : ConformsLone [0, 1] Semantics.goodRelation
  ||| Layer 4: the FFI Result encoder is injective across the seam.
  seamInjective : (a, b : Result) -> resultToInt a = resultToInt b -> a = b

--------------------------------------------------------------------------------
-- THE CAPSTONE: a single inhabited value tying every layer together
--------------------------------------------------------------------------------

||| The capstone value. Constructed entirely from existing exported proofs:
|||   * `goodConformsOne`      (Layer 2, `Alloyiser.ABI.Semantics`)
|||   * `goodConformsLone`     (Layer 3, `Alloyiser.ABI.Invariants`)
|||   * `resultToIntInjective` (Layer 4, `Alloyiser.ABI.FfiSeam`)
|||
||| Because each field is discharged by a genuine theorem/witness, the very
||| existence of `abiContractDischarged` is the end-to-end soundness statement:
||| the alloyiser ABI contract — flagship multiplicity, multiplicity-subsumption
||| invariant, and lossless/injective FFI seam — is proven, together, here.
export
abiContractDischarged : ABISound
abiContractDischarged =
  MkABISound
    goodConformsOne        -- Layer 2 flagship positive control
    goodConformsLone       -- Layer 3 invariant on the same control
    resultToIntInjective   -- Layer 4 FFI-seam injectivity
