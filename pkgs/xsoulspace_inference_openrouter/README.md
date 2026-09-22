# xsoulspace_inference_openrouter

OpenRouter chat-completions transport for the provider-neutral inference
contracts. The current client supports text, structured output, and native
tool-call responses; the consumer executes tools.

An [optional decision provider plan](../xsoulspace_inference_core/docs/decision_provider_PLAN.md)
and separate [Jev pilot plan](docs/jev_pilot_PLAN.md) describe proposed work.
The decision adapter is not implemented and Jev is not a drop-in model setting
for the existing chat client. The proposed adapter remains disabled unless a
consumer explicitly constructs and registers it; it is not a harness feature
required for release.

The pilot separately evaluates target selection, evidence/hypothesis reasoning,
unseen semantic program composition, and mixed actors. Jev's API does not emit
source text; this does not rule out composing new behavior through successive
semantic choices materialized by a host. Such capability remains unmeasured.

From the workspace root, validate this package with
`just check xsoulspace_inference_openrouter`.
