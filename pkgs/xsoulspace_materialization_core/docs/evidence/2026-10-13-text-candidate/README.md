# Text candidate contract qualification

2026-10-13: `just check xsoulspace_materialization_core` exit zero, analyzer
clean, all 14 tests passed (four existing materialization controls plus ten new
text-candidate controls). Source/export/test hashes and the native owning gate
stages are retained alongside this record.

New controls prove exact null/empty/CRLF/Unicode preservation; immutable copies
and fresh exported JSON; sorted keys at every object level; normalized relative
path refusal; observed-change and per-file no-op refusal; strict shape/version;
exact UTF-8 JSON budget; unsupported/cyclic/deep/nonfinite/malformed values;
canonical decoding and duplicate-key rejection; lexical workspace shapes.

Non-claims: filesystem canonicalization, actual identity or actor authority,
fresh verification, consent, promotion, native artifact-store integrity,
mutation/recovery or external-agent acceptance. Those remain with the native
owner and its existing recovery journal. The original frozen external oracle
was neither edited nor used as the contract's checker.
