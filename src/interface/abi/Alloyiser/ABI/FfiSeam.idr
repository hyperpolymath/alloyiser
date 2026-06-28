-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
||| Layer 4 — sealing the ABI <-> FFI seam for alloyiser.
|||
||| The structural gate (scripts/abi-ffi-gate.py) checks that the Idris2 ABI
||| enum and the Zig FFI enum agree by name+value. This module supplies the
||| PROOF-SIDE guarantee that the encoding itself is SOUND:
|||
|||  * `resultToInt` is injective — distinct ABI outcomes never collide on the
|||    C wire (no two `Result` values share an integer code), so a C consumer
|||    can never confuse two outcomes.
|||  * The encoding is FAITHFUL / lossless — there is a decoder `intToResult`
|||    such that decoding an encoded value recovers exactly the original
|||    `Result`. Injectivity is then DERIVED from the round-trip.
|||
||| Scope note: the other FFI enum encoder in this ABI, `multToInt`
||| (`Alloyiser.ABI.Foreign`), is declared `export` rather than `public export`,
||| so its defining clauses do not reduce in importing modules and no
||| computational property of it can be honestly proved from here. We therefore
||| seal the `Result` encoder, which is `public export` and reduces. (Extending
||| the seam to `multToInt` would require widening its visibility in Foreign,
||| which is out of scope for this proof module.)
|||
||| Idiom note: the decoder is written with boolean `Bits32` equality
||| (`if x == 0 then ... else ...`), which reduces on concrete literals, so
||| every round-trip clause checks by `Refl`. Distinct primitive `Bits32`
||| literals are provably unequal, which discharges the negative control.
|||
||| STRICT: genuine proof only. No `believe_me`, `idris_crash`, `assert_total`,
||| `postulate`, `sorry`, or `%hint` hacks anywhere in this module.

module Alloyiser.ABI.FfiSeam

import Alloyiser.ABI.Types

%default total

--------------------------------------------------------------------------------
-- Local lemma: Just is injective
--------------------------------------------------------------------------------

||| Injectivity of the `Just` constructor, proved by pattern matching on the
||| equality witness (no library dependency, no axioms).
justInj : {0 x, y : a} -> Just x = Just y -> x = y
justInj Refl = Refl

--------------------------------------------------------------------------------
-- Result : faithful decoder
--------------------------------------------------------------------------------

||| Decode a C integer back into a `Result`. Built with boolean `Bits32`
||| equality so it reduces definitionally on the concrete literals produced by
||| `resultToInt`, which is what lets the round-trip below check by `Refl`.
public export
intToResult : Bits32 -> Maybe Result
intToResult x =
  if x == 0 then Just Ok
  else if x == 1 then Just Error
  else if x == 2 then Just InvalidParam
  else if x == 3 then Just OutOfMemory
  else if x == 4 then Just NullPointer
  else if x == 5 then Just ModelParseError
  else if x == 6 then Just SolverTimeout
  else if x == 7 then Just CounterexampleFound
  else Nothing

||| Faithfulness: encoding then decoding recovers exactly the original Result.
||| The C integer round-trips back to the ABI value with no loss and no aliasing.
export
resultRoundTrip : (r : Result) -> intToResult (resultToInt r) = Just r
resultRoundTrip Ok                  = Refl
resultRoundTrip Error               = Refl
resultRoundTrip InvalidParam        = Refl
resultRoundTrip OutOfMemory         = Refl
resultRoundTrip NullPointer         = Refl
resultRoundTrip ModelParseError     = Refl
resultRoundTrip SolverTimeout       = Refl
resultRoundTrip CounterexampleFound = Refl

||| Injectivity of `resultToInt`, DERIVED from the round-trip via
||| `justInj . cong intToResult`. Distinct ABI outcomes never collide on the
||| wire: if their integer codes are equal, the outcomes are equal.
|||
||| Derivation: if `resultToInt a = resultToInt b`, then applying `intToResult`
||| to both sides gives `intToResult (resultToInt a) = intToResult (resultToInt b)`;
||| by `resultRoundTrip` both sides are `Just a` and `Just b`, so `Just a = Just b`,
||| and `justInj` yields `a = b`.
export
resultToIntInjective : (a, b : Result)
                    -> resultToInt a = resultToInt b
                    -> a = b
resultToIntInjective a b prf =
  justInj $
    trans (sym (resultRoundTrip a)) $
    trans (cong intToResult prf) (resultRoundTrip b)

--------------------------------------------------------------------------------
-- Positive controls (concrete decodes, machine-checked = Refl)
--------------------------------------------------------------------------------

||| The integer 0 decodes to Ok.
export
decodeZeroIsOk : intToResult 0 = Just Ok
decodeZeroIsOk = Refl

||| The integer 7 decodes to CounterexampleFound (the highest Result code).
export
decodeSevenIsCounterexample : intToResult 7 = Just CounterexampleFound
decodeSevenIsCounterexample = Refl

||| An out-of-range code decodes to Nothing (the decoder is partial, faithfully).
export
decodeOutOfRangeIsNothing : intToResult 8 = Nothing
decodeOutOfRangeIsNothing = Refl

--------------------------------------------------------------------------------
-- Negative / non-vacuity control
--------------------------------------------------------------------------------

||| Two DISTINCT result codes have DISTINCT integer encodings — machine-checked.
||| This rules out the vacuous reading of injectivity: the seam is genuinely
||| discriminating, not trivially collapsing every outcome onto one code.
export
okNotError : Not (resultToInt Ok = resultToInt Error)
okNotError = \case Refl impossible

||| A second distinct pair, for good measure.
export
solverTimeoutNotCounterexample
  : Not (resultToInt SolverTimeout = resultToInt CounterexampleFound)
solverTimeoutNotCounterexample = \case Refl impossible
